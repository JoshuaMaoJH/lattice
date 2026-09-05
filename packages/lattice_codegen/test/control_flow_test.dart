import 'package:lattice_codegen/lattice_codegen.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// ForEach and If compile to collection-`for` and collection-`if` — the syntax
/// a Flutter developer already writes (ADR-009).
void main() {
  /// Generated source with runs of whitespace collapsed.
  ///
  /// Assertions are about what the code *says*; `dart_style` decides where the
  /// line breaks go, and that is not this suite's business.
  String pageSource(Project project) {
    final result = const LatticeGenerator().generate(project);
    expect(result.isSuccess, isTrue, reason: result.diagnostics.join('\n'));
    return result.files['lib/pages/home_page.dart']!
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  group('ForEach', () {
    test('expands into a collection-for inside the children list', () {
      final source = pageSource(listProject());
      expect(source, contains('for (final item in todos.value)'));
      expect(source, isNot(contains('ForEach')));
    });

    test('keys each row by the field itemKey names', () {
      final source = pageSource(listProject());
      expect(source, contains('KeyedSubtree('));
      expect(source, contains('key: ValueKey(item.id)'));
    });

    test('takes the indexed form only when something reads the index', () {
      expect(pageSource(listProject()), isNot(contains('.indexed')));

      final page = listPage();
      final withIndex = listProject().copyWith(
        pages: [
          page.copyWith(
            graph: Graph(
              nodes: [
                ...page.graph.nodes,
                GraphNode(
                  id: 'n_label',
                  type: 'Format',
                  config: const {'template': '#{0}'},
                ),
              ],
              edges: [
                ...page.graph.edges,
                const Edge(
                  PinRef('n_item', 'index'),
                  PinRef('n_label', 'args', index: 0),
                ),
              ],
            ),
            hierarchy: WidgetNode(
              id: 'w_root',
              type: 'Scaffold',
              children: [
                WidgetNode(
                  id: 'w_list',
                  type: 'Column',
                  children: [
                    WidgetNode(
                      id: 'w_each',
                      type: 'ForEach',
                      props: {
                        'items': const BindProp(PinRef('n_todos', 'value')),
                        'itemKey': const LiteralProp('id'),
                      },
                      children: [
                        WidgetNode(
                          id: 'w_tile_title',
                          type: 'Text',
                          props: {
                            'data': const BindProp(PinRef('n_label', 'out')),
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
      expect(
        pageSource(withIndex),
        contains('for (final (index, item) in todos.value.indexed)'),
      );
    });

    test('inlines a per-item computation instead of hoisting it', () {
      // `titleOf` is used once here, but the point is that a value depending on
      // `item` can never become a page-level `computed()` field.
      final source = pageSource(listProject());
      expect(source, contains('_titleOf(item)'));
      expect(source, isNot(contains('computed(')));
    });
  });

  group('If', () {
    Project withIf({bool orElse = false, String parent = 'Column'}) {
      final page = counterPage();
      final branch = WidgetNode(
        id: 'w_then',
        type: 'Text',
        props: {'data': const LiteralProp('yes')},
      );
      return counterProject().copyWith(
        pages: [
          page.copyWith(
            graph: Graph(
              nodes: [
                ...page.graph.nodes.where(
                  (n) => n.id == 'n_count' || n.id == 'n_fmt',
                ),
                GraphNode(
                  id: 'n_big',
                  type: 'GreaterThan',
                  config: const {'dartType': 'int'},
                ),
                GraphNode(
                  id: 'n_ten',
                  type: 'Const',
                  config: const {'dartType': 'int', 'value': 10},
                ),
              ],
              edges: [
                const Edge(PinRef('n_count', 'value'), PinRef('n_big', 'a')),
                const Edge(PinRef('n_ten', 'value'), PinRef('n_big', 'b')),
              ],
            ),
            hierarchy: WidgetNode(
              id: 'w_root',
              type: parent,
              children: [
                WidgetNode(
                  id: 'w_if',
                  type: 'If',
                  props: {
                    'condition': const BindProp(PinRef('n_big', 'out')),
                    if (orElse)
                      'orElse': WidgetProp(
                        WidgetNode(
                          id: 'w_else',
                          type: 'Text',
                          props: {'data': const LiteralProp('no')},
                        ),
                      ),
                  },
                  children: [branch],
                ),
              ],
            ),
          ),
        ],
      );
    }

    test('becomes a collection-if inside a children list', () {
      expect(
        pageSource(withIf()),
        contains("if (count.value > 10) const Text('yes')"),
      );
    });

    test('emits the else branch when there is one', () {
      expect(
        pageSource(withIf(orElse: true)),
        contains("else const Text('no')"),
      );
    });

    test('becomes a conditional expression in a single-child slot', () {
      final source = pageSource(withIf(parent: 'Center'));
      expect(
        source,
        contains(
            "count.value > 10 ? const Text('yes') : const SizedBox.shrink()"),
      );
    });
  });

  group('handlers inside a template', () {
    /// A delete button in each row: the handler is a method, so the loop
    /// variable has to be passed in explicitly.
    Project withRowAction() {
      final page = listPage();
      return listProject().copyWith(
        pages: [
          page.copyWith(
            graph: Graph(
              nodes: [
                ...page.graph.nodes,
                GraphNode(
                  id: 'n_removed',
                  type: 'ListRemoveAt',
                  config: const {'elementType': 'Todo'},
                ),
                GraphNode(
                  id: 'ev_del',
                  type: 'Event',
                  config: const {'widget': 'w_del', 'event': 'onPressed'},
                ),
                GraphNode(
                  id: 'a_del',
                  type: 'SetSignal',
                  config: const {'signal': 'n_todos'},
                ),
              ],
              edges: [
                ...page.graph.edges,
                const Edge(
                  PinRef('n_todos', 'value'),
                  PinRef('n_removed', 'list'),
                ),
                const Edge(
                  PinRef('n_item', 'index'),
                  PinRef('n_removed', 'index'),
                ),
                const Edge(PinRef('ev_del', 'fire'), PinRef('a_del', 'exec')),
                const Edge(
                  PinRef('n_removed', 'out'),
                  PinRef('a_del', 'value'),
                ),
              ],
            ),
            hierarchy: WidgetNode(
              id: 'w_root',
              type: 'Scaffold',
              children: [
                WidgetNode(
                  id: 'w_list',
                  type: 'Column',
                  children: [
                    WidgetNode(
                      id: 'w_each',
                      type: 'ForEach',
                      props: {
                        'items': const BindProp(PinRef('n_todos', 'value')),
                        'itemKey': const LiteralProp('id'),
                      },
                      children: [
                        WidgetNode(
                          id: 'w_del',
                          type: 'TextButton',
                          props: {'onPressed': const EventProp('ev_del')},
                          children: [
                            WidgetNode(
                              id: 'w_del_label',
                              type: 'Text',
                              props: {'data': const LiteralProp('x')},
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }

    test('takes the loop variable as a parameter', () {
      final source = pageSource(withRowAction());
      expect(source, contains('void _onDelPressed(int index)'));
    });

    test('passes it through a closure at the call site', () {
      expect(
        pageSource(withRowAction()),
        contains('onPressed: () => _onDelPressed(index)'),
      );
    });

    test('a handler outside any template stays a tear-off', () {
      expect(
        pageSource(counterProject()),
        contains('onPressed: _onBtnPressed'),
      );
    });
  });

  group('rebuild boundaries', () {
    test('does not nest one SignalBuilder inside another', () {
      // The Column reads `todos` through the ForEach, so it is the boundary;
      // the ListView beneath it must not get one of its own.
      final source = pageSource(listProject());
      expect('SignalBuilder'.allMatches(source).length, 1);
    });
  });
}
