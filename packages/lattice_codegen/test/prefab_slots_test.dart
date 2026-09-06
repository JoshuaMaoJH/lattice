import 'package:lattice_codegen/lattice_codegen.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

/// R9's second half: a prefab that takes a subtree and hands an event back.
void main() {
  // A card that wraps whatever it is given and reports taps to its host.
  Prefab panel() => Prefab(
        id: 'prefab_panel',
        name: 'Panel',
        parameters: [
          FieldDef(name: 'title', type: PrimitiveType.string),
          FieldDef(name: 'body', type: const WidgetType()),
          FieldDef(name: 'onTap', type: const EventType()),
        ],
        hierarchy: WidgetNode(
          id: 'w_root',
          type: 'Card',
          children: [
            WidgetNode(id: 'w_col', type: 'Column', children: [
              WidgetNode(
                id: 'w_title',
                type: 'Text',
                props: {'data': BindProp(PinRef('p_title', 'value'))},
              ),
              // The caller's subtree goes here.
              WidgetNode(
                id: 'w_slot',
                type: 'Slot',
                props: {'name': const LiteralProp('body')},
              ),
              WidgetNode(
                id: 'w_btn',
                type: 'TextButton',
                props: {'onPressed': const EventProp('ev_tap')},
                children: [
                  WidgetNode(
                    id: 'w_l',
                    type: 'Text',
                    props: {'data': const LiteralProp('More')},
                  ),
                ],
              ),
            ]),
          ],
        ),
        graph: Graph(
          nodes: [
            GraphNode(
              id: 'p_title',
              type: 'PageParam',
              config: {'name': 'title'},
            ),
            GraphNode(
              id: 'ev_tap',
              type: 'Event',
              config: {'widget': 'w_btn', 'event': 'onPressed'},
            ),
            GraphNode(
              id: 'a_cb',
              type: 'InvokeCallback',
              config: {'name': 'onTap'},
            ),
          ],
          edges: const [
            Edge(PinRef('ev_tap', 'fire'), PinRef('a_cb', 'exec')),
          ],
        ),
      );

  Project project() => Project(
        id: 'p',
        config: const ProjectConfig(
          appName: 'Slots',
          packageName: 'slots_app',
          bundleId: 'com.example.slots_app',
        ),
        prefabs: [panel()],
        pages: [
          Page(
            id: 'page_home',
            name: 'Home',
            route: '/',
            isHome: true,
            hierarchy: WidgetNode(
              id: 'w_root',
              type: 'Scaffold',
              children: [
                WidgetNode(
                  id: 'w_panel',
                  type: 'Panel',
                  props: {
                    'title': const LiteralProp('Hello'),
                    'body': WidgetProp(WidgetNode(
                      id: 'w_body',
                      type: 'Text',
                      props: {'data': const LiteralProp('inside')},
                    )),
                    'onTap': const EventProp('ev_panel'),
                  },
                ),
              ],
            ),
            graph: Graph(
              nodes: [
                GraphNode(
                  id: 'n_seen',
                  type: 'Signal',
                  config: {'dartType': 'bool', 'init': false, 'name': 'seen'},
                ),
                GraphNode(
                  id: 'ev_panel',
                  type: 'Event',
                  config: {'widget': 'w_panel', 'event': 'onTap'},
                ),
                GraphNode(
                  id: 'a_set',
                  type: 'ToggleSignal',
                  config: {'signal': 'n_seen'},
                ),
              ],
              edges: const [
                Edge(PinRef('ev_panel', 'fire'), PinRef('a_set', 'exec')),
              ],
            ),
          ),
        ],
      );

  late Map<String, String> files;

  setUpAll(() {
    final result = const LatticeGenerator().generate(project());
    expect(result.isSuccess, isTrue, reason: result.diagnostics.join('\n'));
    files = result.files;
  });

  String file(String suffix) =>
      files.entries.firstWhere((e) => e.key.endsWith(suffix)).value;

  test('the project validates', () {
    final result = const Validator().validate(project());
    expect(result.diagnostics, isEmpty, reason: result.toString());
  });

  test('a Widget parameter becomes a Widget field', () {
    expect(file('panel.dart'), contains('final Widget body;'));
    expect(file('panel.dart'), contains('required this.body'));
  });

  test('an Event parameter becomes an optional nullable callback', () {
    final panel = file('panel.dart');
    expect(panel, contains('final VoidCallback? onTap;'));
    // Optional: a host that does not care about the event passes nothing.
    expect(panel, isNot(contains('required this.onTap')));
  });

  test('a Slot compiles to the parameter, not to a widget call', () {
    final panel = file('panel.dart');
    expect(panel, contains('widget.body'));
    expect(panel, isNot(contains('Slot(')));
  });

  test('InvokeCallback calls it through the null check', () {
    expect(file('panel.dart'), contains('widget.onTap?.call();'));
  });

  test('a payloadless callback handler takes no argument', () {
    // The prefab declares `Event`, whose Dart form is `VoidCallback`. Reading
    // the payload off the parameter type without unwrapping produced
    // `void _onPanelTap(VoidCallback value)`, which Flutter rejects.
    expect(file('home_page.dart'), contains('void _onPanelTap()'));
  });

  test('the host passes a subtree and wires the callback', () {
    final home = file('home_page.dart').replaceAll(RegExp(r'\s+'), ' ');
    expect(home, contains("body: const Text('inside')"));
    expect(home, contains('onTap: _onPanelTap'));
  });
}
