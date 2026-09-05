import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

/// A prefab's name becomes a Dart class *and* a Hierarchy type, so the rules
/// around it are stricter than for anything else a user names (R9).
void main() {
  const validator = Validator();

  Prefab card({
    String name = 'StatCard',
    List<FieldDef>? parameters,
    WidgetNode? hierarchy,
  }) =>
      Prefab(
        id: 'prefab_card',
        name: name,
        parameters: parameters ??
            [const FieldDef(name: 'label', type: PrimitiveType.string)],
        hierarchy: hierarchy ??
            WidgetNode(
              id: 'c_root',
              type: 'Text',
              props: {'data': const BindProp(PinRef('c_label', 'value'))},
            ),
        graph: Graph(
          nodes: [
            GraphNode(
              id: 'c_label',
              type: 'PageParam',
              config: const {'name': 'label'},
            ),
          ],
        ),
      );

  Project projectWith(List<Prefab> prefabs, {WidgetNode? usage}) => Project(
        id: 'p',
        config: const ProjectConfig(appName: 'P', packageName: 'p'),
        prefabs: prefabs,
        pages: [
          Page(
            id: 'page_home',
            name: 'Home',
            isHome: true,
            hierarchy: usage ??
                WidgetNode(
                  id: 'w_root',
                  type: 'Column',
                  children: [
                    WidgetNode(
                      id: 'w_card',
                      type: 'StatCard',
                      props: {'label': const LiteralProp('Total')},
                    ),
                  ],
                ),
          ),
        ],
      );

  Iterable<String> codesFor(Project project) =>
      validator.validate(project).diagnostics.map((d) => d.code);

  test('a prefab used as a widget validates clean', () {
    final result = validator.validate(projectWith([card()]));
    expect(result.isValid, isTrue, reason: result.toString());
  });

  test('its parameters behave like widget parameters', () {
    // Required parameter missing.
    final missing = projectWith(
      [card()],
      usage: WidgetNode(
        id: 'w_root',
        type: 'Column',
        children: [WidgetNode(id: 'w_card', type: 'StatCard')],
      ),
    );
    expect(codesFor(missing), contains('missing_required_param'));

    // And they are type-checked.
    final wrongType = projectWith(
      [card()],
      usage: WidgetNode(
        id: 'w_root',
        type: 'Column',
        children: [
          WidgetNode(
            id: 'w_card',
            type: 'StatCard',
            props: {
              'label': const LiteralProp('x'),
              'nope': const LiteralProp(1)
            },
          ),
        ],
      ),
    );
    expect(codesFor(wrongType), contains('unknown_param'));
  });

  group('naming', () {
    test('rejects a name that is not a Dart class name', () {
      expect(
        codesFor(projectWith([card(name: 'stat card')])),
        contains('bad_prefab_name'),
      );
    });

    test('rejects shadowing a built-in widget', () {
      expect(
        codesFor(projectWith([card(name: 'Column')])),
        contains('prefab_shadows_widget'),
      );
    });

    test('rejects two prefabs with the same name', () {
      final duplicate = Prefab(
        id: 'prefab_other',
        name: 'StatCard',
        hierarchy: WidgetNode(
          id: 'o_root',
          type: 'Text',
          props: {'data': const LiteralProp('x')},
        ),
      );
      expect(
        codesFor(projectWith([card(), duplicate])),
        contains('duplicate_prefab'),
      );
    });
  });

  test('rejects a prefab that contains itself', () {
    final recursive = Prefab(
      id: 'prefab_card',
      name: 'StatCard',
      hierarchy: WidgetNode(
        id: 'c_root',
        type: 'Column',
        children: [WidgetNode(id: 'c_self', type: 'StatCard')],
      ),
    );
    expect(codesFor(projectWith([recursive])), contains('prefab_recursion'));
  });

  test('a prefab with no state of its own is const-constructible', () {
    expect(WidgetLookup.schemaFor(card()).constCtor, isTrue);

    final stateful = Prefab(
      id: 'prefab_counter',
      name: 'Counter',
      hierarchy: WidgetNode(
        id: 'k_root',
        type: 'Text',
        props: {'data': const LiteralProp('0')},
      ),
      graph: Graph(
        nodes: [
          GraphNode(
            id: 'k_n',
            type: 'Signal',
            config: const {'dartType': 'int', 'init': 0},
          ),
        ],
      ),
    );
    expect(WidgetLookup.schemaFor(stateful).constCtor, isFalse);
  });

  test('survives a JSON round trip', () {
    final original = card();
    final decoded = Prefab.fromJson(original.toJson());
    expect(decoded, original);
    expect(decoded.parameters.single.name, 'label');
    expect(decoded.className, 'StatCard');
    expect(decoded.fileName, 'stat_card.dart');
    expect(decoded.directory, 'prefabs');
  });
}
