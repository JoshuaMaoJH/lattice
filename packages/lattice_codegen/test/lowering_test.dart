import 'package:lattice_codegen/lattice_codegen.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// These tests pin the two decisions lowering exists to make: where the
/// reactive boundary goes, and what gets hoisted out of the widget tree.
void main() {
  String pageSource(Project project) {
    final result = const LatticeGenerator().generate(project);
    expect(result.isSuccess, isTrue, reason: result.diagnostics.join('\n'));
    return result.files['lib/pages/home_page.dart']!;
  }

  group('reactive boundaries (§7.5)', () {
    test('wraps only the widget whose arguments read a signal', () {
      final source = pageSource(counterProject());
      expect(
        source,
        contains(
            "SignalBuilder(builder: (context) => Text('Count: \${count.value}'))"),
      );
      // The button's label does not depend on anything, so it stays const and
      // outside any rebuild boundary.
      expect(source, contains("const Text('+1')"));
      expect('SignalBuilder'.allMatches(source).length, 1);
    });

    test('keeps a fully static subtree const', () {
      final source = pageSource(counterProject());
      expect(source, contains("const Text('Counter')"));
    });

    test('does not wrap anything when no widget reads a signal', () {
      final project = counterProject().copyWith(
        pages: [
          counterPage().copyWith(
            graph: Graph(),
            hierarchy: WidgetNode(
              id: 'w_root',
              type: 'Text',
              props: {'data': const LiteralProp('static')},
            ),
          ),
        ],
      );
      final source = pageSource(project);
      expect(source, isNot(contains('SignalBuilder')));
      // Nothing stateful left, so no State class either.
      expect(source, contains('extends StatelessWidget'));
    });
  });

  group('event chains', () {
    test('beta-reduces a simple UpdateSignal lambda (§8)', () {
      expect(
        pageSource(counterProject()),
        contains('count.value = count.value + 1;'),
      );
    });

    test('falls back to applying the lambda when substitution is unsafe', () {
      final project = counterProject().copyWith(
        pages: [
          withNode(
            counterPage(),
            GraphNode(
              id: 'a_inc',
              type: 'UpdateSignal',
              config: const {
                'signal': 'n_count',
                // A string literal could contain the parameter name, so the
                // textual substitution is not attempted.
                'fn': "(x) => x + 'a'.length",
              },
            ),
          ),
        ],
      );
      expect(
        pageSource(project),
        contains("count.value = ((x) => x + 'a'.length)(count.value);"),
      );
    });

    test('names the handler after the widget and the callback', () {
      final source = pageSource(counterProject());
      expect(source, contains('void _onBtnPressed()'));
      expect(source, contains('onPressed: _onBtnPressed'));
    });

    test('chains several actions in order', () {
      final page = counterPage();
      final project = counterProject().copyWith(
        pages: [
          page.copyWith(
            graph: Graph(
              nodes: [
                ...page.graph.nodes,
                GraphNode(
                  id: 'a_reset',
                  type: 'SetSignal',
                  config: const {'signal': 'n_count'},
                ),
                GraphNode(
                  id: 'n_zero',
                  type: 'Const',
                  config: const {'dartType': 'int', 'value': 0},
                ),
              ],
              edges: [
                ...page.graph.edges,
                const Edge(PinRef('a_inc', 'next'), PinRef('a_reset', 'exec')),
                const Edge(
                    PinRef('n_zero', 'value'), PinRef('a_reset', 'value')),
              ],
            ),
          ),
        ],
      );
      final source = pageSource(project);
      final increment = source.indexOf('count.value = count.value + 1;');
      final reset = source.indexOf('count.value = 0;');
      expect(increment, greaterThan(-1));
      expect(reset, greaterThan(increment));
    });
  });

  group('hoisting (§7.5 step 3)', () {
    test('inlines a computation used once', () {
      expect(pageSource(counterProject()), isNot(contains('computed(')));
    });

    test('promotes a computation used twice to a computed field', () {
      final page = counterPage();
      final project = counterProject().copyWith(
        pages: [
          page.copyWith(
            hierarchy: WidgetNode(
              id: 'w_root',
              type: 'Column',
              children: [
                WidgetNode(
                  id: 'w_a',
                  type: 'Text',
                  props: {'data': const BindProp(PinRef('n_fmt', 'out'))},
                ),
                WidgetNode(
                  id: 'w_b',
                  type: 'Text',
                  props: {'data': const BindProp(PinRef('n_fmt', 'out'))},
                ),
                WidgetNode(
                  id: 'w_btn',
                  type: 'ElevatedButton',
                  props: {'onPressed': const EventProp('ev_btn')},
                  children: [
                    WidgetNode(
                      id: 'w_btn_label',
                      type: 'Text',
                      props: {'data': const LiteralProp('+1')},
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
      final source = pageSource(project);
      expect(
          source,
          contains(
              "late final fmt = computed(() => 'Count: \${count.value}')"));
      // Two readers, one definition.
      expect("'Count: ".allMatches(source).length, 1);
      expect('fmt.value'.allMatches(source).length, 2);
    });
  });

  group('expressions', () {
    test('parenthesises nested operators', () {
      final page = counterPage();
      final project = counterProject().copyWith(
        pages: [
          page.copyWith(
            graph: Graph(
              nodes: [
                ...page.graph.nodes,
                GraphNode(
                  id: 'n_two',
                  type: 'Const',
                  config: const {'dartType': 'int', 'value': 2},
                ),
                GraphNode(
                  id: 'n_add',
                  type: 'Add',
                  config: const {'dartType': 'int'},
                ),
                GraphNode(
                  id: 'n_mul',
                  type: 'Multiply',
                  config: const {'dartType': 'int'},
                ),
              ],
              edges: [
                ...page.graph.edges,
                const Edge(PinRef('n_count', 'value'), PinRef('n_add', 'a')),
                const Edge(PinRef('n_two', 'value'), PinRef('n_add', 'b')),
                const Edge(PinRef('n_add', 'out'), PinRef('n_mul', 'a')),
                const Edge(PinRef('n_two', 'value'), PinRef('n_mul', 'b')),
                const Edge(
                    PinRef('n_mul', 'out'), PinRef('n_fmt', 'args', index: 1)),
              ],
            ),
          ),
        ],
      );
      final withTemplate = project.copyWith(
        pages: [
          withNode(
            project.pages.single,
            GraphNode(
              id: 'n_fmt',
              type: 'Format',
              config: const {'template': 'Count: {0} doubled: {1}'},
            ),
          ),
        ],
      );
      expect(
        pageSource(withTemplate),
        contains(r'(count.value + 2) * 2'),
      );
    });

    test('escapes template text that looks like interpolation', () {
      final project = counterProject().copyWith(
        pages: [
          withNode(
            counterPage(),
            GraphNode(
              id: 'n_fmt',
              type: 'Format',
              config: const {'template': r"It's $50: {0}"},
            ),
          ),
        ],
      );
      expect(
        pageSource(project),
        contains(r"'It\'s \$50: ${count.value}'"),
      );
    });
  });

  group('failures', () {
    test('refuses to emit anything for an invalid project', () {
      final project = counterProject().copyWith(
        pages: [
          counterPage().copyWith(
            hierarchy: WidgetNode(id: 'w_root', type: 'NotAWidget'),
          ),
        ],
      );
      final result = const LatticeGenerator().generate(project);
      expect(result.isSuccess, isFalse);
      expect(result.files, isEmpty);
      expect(result.errors.map((e) => e.code), contains('unknown_widget'));
    });
  });

  group('runtime backends (§15)', () {
    test('signals and the zero-dependency runtime differ only in the import',
        () {
      final withSignals = pageSource(counterProject());
      final withNotifier =
          pageSource(counterProject(runtime: RuntimeBackend.valueNotifier));

      expect(withSignals,
          contains('package:signals_flutter/signals_flutter.dart'));
      expect(withNotifier,
          contains('package:lattice_runtime/lattice_runtime.dart'));
      expect(
        withSignals.replaceAll(
            'package:signals_flutter/signals_flutter.dart', 'X'),
        withNotifier.replaceAll(
            'package:lattice_runtime/lattice_runtime.dart', 'X'),
      );
    });
  });
}
