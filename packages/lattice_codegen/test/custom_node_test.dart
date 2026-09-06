import 'package:lattice_codegen/lattice_codegen.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

/// R20: a node the project defines compiles like one the compiler knows.
void main() {
  const clamp = CustomNodeDef(
    type: 'Clamp',
    category: NodeCategory.compute,
    summary: 'Constrains a number to a range.',
    inputs: [
      CustomPin(name: 'value', type: PrimitiveType.int_),
      CustomPin(name: 'low', type: PrimitiveType.int_),
      CustomPin(name: 'high', type: PrimitiveType.int_),
    ],
    outputs: [CustomPin(name: 'out', type: PrimitiveType.int_)],
    template: 'max({low}, min({high}, {value}))',
    imports: ['dart:math'],
  );

  const beep = CustomNodeDef(
    type: 'Beep',
    category: NodeCategory.action,
    inputs: [CustomPin(name: 'note', type: PrimitiveType.string)],
    template: "debugPrint('beep \${note}');",
  );

  Project projectWith(
    List<CustomNodeDef> nodes, {
    List<GraphNode> extraNodes = const [],
    List<Edge> edges = const [],
    WidgetNode? hierarchy,
  }) =>
      Project(
        id: 'p',
        config: const ProjectConfig(
          appName: 'Custom',
          packageName: 'custom_app',
          bundleId: 'com.example.custom_app',
        ),
        customNodes: nodes,
        pages: [
          Page(
            id: 'page_home',
            name: 'Home',
            route: '/',
            isHome: true,
            hierarchy: hierarchy ??
                WidgetNode(id: 'w_root', type: 'Scaffold', children: [
                  WidgetNode(
                    id: 'w_text',
                    type: 'Text',
                    props: {'data': const LiteralProp('hi')},
                  ),
                ]),
            graph: Graph(nodes: extraNodes, edges: edges),
          ),
        ],
      );

  group('validation', () {
    test('a definition that collides with a built-in is refused', () {
      final result = const Validator().validate(projectWith([
        CustomNodeDef(
          type: 'Signal',
          category: NodeCategory.compute,
          inputs: [CustomPin(name: 'a', type: PrimitiveType.int_)],
          outputs: [CustomPin(name: 'out', type: PrimitiveType.int_)],
          template: '{a}',
        ),
      ]));
      expect(
        result.diagnostics.map((d) => d.code),
        contains('custom_node_shadows_builtin'),
      );
    });

    test('a placeholder with no matching input is refused', () {
      final result = const Validator().validate(projectWith([
        CustomNodeDef(
          type: 'Oops',
          category: NodeCategory.compute,
          inputs: [CustomPin(name: 'a', type: PrimitiveType.int_)],
          outputs: [CustomPin(name: 'out', type: PrimitiveType.int_)],
          template: '{a} + {b}',
        ),
      ]));
      expect(
        result.diagnostics.map((d) => d.code),
        contains('custom_node_unknown_placeholder'),
      );
    });

    test('a compute node with no output is refused', () {
      final result = const Validator().validate(projectWith([
        CustomNodeDef(
          type: 'Nothing',
          category: NodeCategory.compute,
          inputs: [CustomPin(name: 'a', type: PrimitiveType.int_)],
          template: '{a}',
        ),
      ]));
      expect(
        result.diagnostics.map((d) => d.code),
        contains('custom_node_output_count'),
      );
    });

    test('an action that claims data outputs is refused', () {
      final result = const Validator().validate(projectWith([
        CustomNodeDef(
          type: 'Loud',
          category: NodeCategory.action,
          inputs: [CustomPin(name: 'a', type: PrimitiveType.string)],
          outputs: [CustomPin(name: 'out', type: PrimitiveType.int_)],
          template: 'print({a});',
        ),
      ]));
      expect(
        result.diagnostics.map((d) => d.code),
        contains('custom_node_action_outputs'),
      );
    });

    test('a well-formed pair validates clean', () {
      final result = const Validator().validate(projectWith([clamp, beep]));
      expect(result.diagnostics, isEmpty, reason: result.toString());
    });
  });

  group('codegen', () {
    // A page whose Text reads Clamp(value: count, 0, 10).
    Project clampPage() => projectWith(
          [clamp],
          extraNodes: [
            GraphNode(
              id: 'n_count',
              type: 'Signal',
              config: {'name': 'count', 'dartType': 'int', 'init': 3},
            ),
            GraphNode(
              id: 'n_low',
              type: 'Const',
              config: {'dartType': 'int', 'value': 0},
            ),
            GraphNode(
              id: 'n_high',
              type: 'Const',
              config: {'dartType': 'int', 'value': 10},
            ),
            GraphNode(id: 'n_clamp', type: 'Clamp'),
            GraphNode(
              id: 'n_str',
              type: 'ToString',
              config: {'dartType': 'int'},
            ),
          ],
          edges: [
            Edge(PinRef('n_count', 'value'), PinRef('n_clamp', 'value')),
            Edge(PinRef('n_low', 'value'), PinRef('n_clamp', 'low')),
            Edge(PinRef('n_high', 'value'), PinRef('n_clamp', 'high')),
            Edge(PinRef('n_clamp', 'out'), PinRef('n_str', 'value')),
          ],
          hierarchy: WidgetNode(id: 'w_root', type: 'Scaffold', children: [
            WidgetNode(
              id: 'w_text',
              type: 'Text',
              props: {'data': BindProp(PinRef('n_str', 'out'))},
            ),
          ]),
        );

    test('the template lands in the page, with its import', () {
      final result = const LatticeGenerator().generate(clampPage());
      expect(result.isSuccess, isTrue, reason: result.diagnostics.join('\n'));

      final page = result.files.entries
          .firstWhere((e) => e.key.endsWith('home_page.dart'))
          .value;
      expect(page, contains("import 'dart:math'"));
      expect(page, contains('max('));
      expect(page, contains('min('));
      // The signal read is threaded through the template, so the Text is
      // wrapped in a rebuild boundary rather than baked as a constant.
      expect(page, contains('count.value'));
      expect(page, contains('SignalBuilder'));
    });

    test('inputs are parenthesised so the template cannot re-associate', () {
      const sum = CustomNodeDef(
        type: 'Doubled',
        category: NodeCategory.compute,
        inputs: [CustomPin(name: 'n', type: PrimitiveType.int_)],
        outputs: [CustomPin(name: 'out', type: PrimitiveType.int_)],
        // If `n` arrived unwrapped, `1 + 2` here would compile as `1 + 2 * 2`.
        template: '{n} * 2',
      );
      final project = projectWith(
        [sum],
        extraNodes: [
          GraphNode(
              id: 'n_a',
              type: 'Const',
              config: {'dartType': 'int', 'value': 1}),
          GraphNode(
              id: 'n_b',
              type: 'Const',
              config: {'dartType': 'int', 'value': 2}),
          GraphNode(id: 'n_add', type: 'Add', config: {'dartType': 'int'}),
          GraphNode(id: 'n_dbl', type: 'Doubled'),
          GraphNode(id: 'n_str', type: 'ToString', config: {'dartType': 'int'}),
        ],
        edges: [
          Edge(PinRef('n_a', 'value'), PinRef('n_add', 'a')),
          Edge(PinRef('n_b', 'value'), PinRef('n_add', 'b')),
          Edge(PinRef('n_add', 'out'), PinRef('n_dbl', 'n')),
          Edge(PinRef('n_dbl', 'out'), PinRef('n_str', 'value')),
        ],
        hierarchy: WidgetNode(id: 'w_root', type: 'Scaffold', children: [
          WidgetNode(
            id: 'w_text',
            type: 'Text',
            props: {'data': BindProp(PinRef('n_str', 'out'))},
          ),
        ]),
      );

      final result = const LatticeGenerator().generate(project);
      expect(result.isSuccess, isTrue, reason: result.diagnostics.join('\n'));
      final page = result.files.entries
          .firstWhere((e) => e.key.endsWith('home_page.dart'))
          .value
          .replaceAll(RegExp(r'\s+'), '');
      expect(page, contains('(1+2)*2'));
    });
  });
}
