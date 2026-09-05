import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// Every diagnostic the editor promises to show while the user is still
/// editing (§7.1, §7.2, R15) gets a test, because "the analyzer would have
/// caught it eventually" is exactly the experience Lattice exists to avoid.
void main() {
  const validator = Validator();

  Iterable<String> codesFor(Page page) => validator
      .validate(counterProject().copyWith(pages: [page]))
      .diagnostics
      .map((d) => d.code);

  test('the reference project is clean', () {
    final result = validator.validate(counterProject());
    expect(result.isValid, isTrue, reason: result.toString());
    expect(result.diagnostics, isEmpty);
  });

  group('hierarchy', () {
    test('rejects a widget outside the whitelist', () {
      final page = counterPage().copyWith(
        hierarchy: WidgetNode(id: 'w_root', type: 'Sliver3DHologram'),
      );
      expect(codesFor(page), contains('unknown_widget'));
    });

    test('rejects Expanded outside a Flex', () {
      final page = counterPage().copyWith(
        hierarchy: WidgetNode(
          id: 'w_root',
          type: 'Scaffold',
          children: [
            WidgetNode(
              id: 'w_center',
              type: 'Center',
              children: [WidgetNode(id: 'w_exp', type: 'Expanded')],
            ),
          ],
        ),
      );
      expect(codesFor(page), contains('illegal_parent'));
    });

    test('accepts Expanded inside a Column', () {
      final page = counterPage().copyWith(
        hierarchy: WidgetNode(
          id: 'w_root',
          type: 'Scaffold',
          children: [
            WidgetNode(
              id: 'w_col',
              type: 'Column',
              children: [WidgetNode(id: 'w_exp', type: 'Expanded')],
            ),
          ],
        ),
      );
      expect(codesFor(page), isNot(contains('illegal_parent')));
    });

    test('rejects two children on a single-child widget', () {
      final page = counterPage().copyWith(
        hierarchy: WidgetNode(
          id: 'w_root',
          type: 'Center',
          children: [
            WidgetNode(id: 'a', type: 'Divider'),
            WidgetNode(id: 'b', type: 'Divider'),
          ],
        ),
      );
      expect(codesFor(page), contains('too_many_children'));
    });

    test('reports a missing required parameter', () {
      final page = counterPage().copyWith(
        hierarchy: WidgetNode(id: 'w_root', type: 'Text'),
      );
      expect(codesFor(page), contains('missing_required_param'));
    });

    test('reports an unknown parameter', () {
      final page = counterPage().copyWith(
        hierarchy: WidgetNode(
          id: 'w_root',
          type: 'Text',
          props: {
            'data': const LiteralProp('x'),
            'colour': const LiteralProp(1)
          },
        ),
      );
      expect(codesFor(page), contains('unknown_param'));
    });

    test('reports duplicate widget ids', () {
      final page = counterPage().copyWith(
        hierarchy: WidgetNode(
          id: 'w_root',
          type: 'Column',
          children: [
            WidgetNode(id: 'dup', type: 'Divider'),
            WidgetNode(id: 'dup', type: 'Divider'),
          ],
        ),
      );
      expect(codesFor(page), contains('duplicate_widget_id'));
    });
  });

  group('bindings', () {
    test('rejects a type mismatch at a widget parameter', () {
      // Text.data is String; bind it to the int signal instead.
      final page = counterPage();
      final text = WidgetNode(
        id: 'w_txt',
        type: 'Text',
        props: {'data': const BindProp(PinRef('n_count', 'value'))},
      );
      final broken = page.copyWith(
        hierarchy: WidgetNode(
          id: 'w_root',
          type: 'Scaffold',
          children: [
            WidgetNode(id: 'w_col', type: 'Column', children: [text]),
          ],
        ),
      );
      expect(codesFor(broken), contains('type_mismatch'));
    });

    test('rejects a binding to a pin that does not exist', () {
      final page = counterPage();
      final broken = page.copyWith(
        hierarchy: WidgetNode(
          id: 'w_root',
          type: 'Text',
          props: {'data': const BindProp(PinRef('n_fmt', 'nope'))},
        ),
      );
      expect(codesFor(broken), contains('unknown_pin'));
    });

    test('rejects a callback wired to the wrong widget', () {
      final page = withNode(
        counterPage(),
        GraphNode(
          id: 'ev_btn',
          type: 'Event',
          config: const {'widget': 'w_txt', 'event': 'onPressed'},
        ),
      );
      expect(codesFor(page), contains('event_binding_mismatch'));
    });

    test('rejects a value in a callback slot', () {
      final page = counterPage().copyWith(
        hierarchy: WidgetNode(
          id: 'w_root',
          type: 'ElevatedButton',
          props: {'onPressed': const LiteralProp('nope')},
        ),
      );
      expect(codesFor(page), contains('param_kind_mismatch'));
    });
  });

  group('graph', () {
    test('rejects an unknown node type', () {
      final page = withNode(
        counterPage(),
        GraphNode(id: 'n_fmt', type: 'Teleport'),
      );
      expect(codesFor(page), contains('unknown_node_type'));
    });

    test('rejects an action targeting a non-signal', () {
      final page = withNode(
        counterPage(),
        GraphNode(
          id: 'a_inc',
          type: 'UpdateSignal',
          config: const {'signal': 'n_fmt', 'fn': '(x) => x'},
        ),
      );
      expect(codesFor(page), contains('not_a_signal'));
    });

    test('rejects two edges into one input pin', () {
      final page = withEdges(counterPage(), const [
        Edge(PinRef('n_count', 'value'), PinRef('n_fmt', 'args', index: 0)),
      ]);
      expect(codesFor(page), contains('multiple_inputs'));
    });

    test('rejects a data edge into an event pin', () {
      final page = withEdges(counterPage(), const [
        Edge(PinRef('n_count', 'value'), PinRef('a_inc', 'exec')),
      ]);
      expect(codesFor(page), contains('pin_kind_mismatch'));
    });

    test('detects a cycle in the data flow', () {
      final page = counterPage().copyWith(
        graph: Graph(
          nodes: [
            GraphNode(
              id: 'n_a',
              type: 'Add',
              config: const {'dartType': 'int'},
            ),
            GraphNode(
              id: 'n_b',
              type: 'Add',
              config: const {'dartType': 'int'},
            ),
          ],
          edges: const [
            Edge(PinRef('n_a', 'out'), PinRef('n_b', 'a')),
            Edge(PinRef('n_b', 'out'), PinRef('n_a', 'a')),
          ],
        ),
        hierarchy: WidgetNode(
          id: 'w_root',
          type: 'Text',
          props: {'data': const LiteralProp('x')},
        ),
      );
      expect(codesFor(page), contains('cycle'));
    });

    test('reports a required input with nothing connected', () {
      final page = counterPage().copyWith(
        graph: Graph(
          nodes: [
            GraphNode(
              id: 'n_add',
              type: 'Add',
              config: const {'dartType': 'int'},
            ),
          ],
        ),
        hierarchy: WidgetNode(
          id: 'w_root',
          type: 'Text',
          props: {'data': const LiteralProp('x')},
        ),
      );
      expect(codesFor(page), contains('unconnected_input'));
    });

    test('accepts an event edge looping back to the signal it reads', () {
      // count -> Format -> Text, and the button writes count. This is a cycle
      // in the picture but not in the data flow, and must not be rejected.
      final result = const Validator().validate(counterProject());
      expect(result.withCode('cycle'), isEmpty);
    });
  });

  group('project', () {
    test('rejects two pages on the same route', () {
      final project = counterProject().copyWith(
        pages: [
          counterPage(),
          counterPage().copyWith(name: 'Other'),
        ],
      );
      final codes =
          const Validator().validate(project).diagnostics.map((d) => d.code);
      expect(codes, contains('duplicate_route'));
    });

    test('rejects a model reference with no model behind it', () {
      final page = withNode(
        counterPage(),
        GraphNode(
          id: 'n_count',
          type: 'Signal',
          config: const {'dartType': 'Ghost', 'init': null},
        ),
      );
      expect(codesFor(page), contains('unknown_model'));
    });
  });
}
