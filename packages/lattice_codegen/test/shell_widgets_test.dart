import 'package:lattice_codegen/lattice_codegen.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

/// The navigation shell, overlays and layout pieces added alongside R20 —
/// plus the two compiler bugs they surfaced.
void main() {
  Project pageWith({
    required WidgetNode hierarchy,
    Graph? graph,
  }) =>
      Project(
        id: 'p',
        config: const ProjectConfig(
          appName: 'Shell',
          packageName: 'shell_app',
          bundleId: 'com.example.shell_app',
        ),
        pages: [
          Page(
            id: 'page_home',
            name: 'Home',
            route: '/',
            isHome: true,
            hierarchy: hierarchy,
            graph: graph ?? Graph(),
          ),
        ],
      );

  String generate(Project project) {
    final result = const LatticeGenerator().generate(project);
    expect(result.isSuccess, isTrue, reason: result.diagnostics.join('\n'));
    return result.files.entries
        .firstWhere((e) => e.key.endsWith('home_page.dart'))
        .value;
  }

  test('a required parameter survives even when it equals the default', () {
    // AspectRatio declares aspectRatio required with a sensible default. The
    // emitter used to drop any value equal to its default, which produced
    // `AspectRatio(child: …)` — a call Flutter rejects.
    final page = generate(pageWith(
      hierarchy: WidgetNode(id: 'w_root', type: 'Scaffold', children: [
        WidgetNode(
          id: 'w_ar',
          type: 'AspectRatio',
          props: {'aspectRatio': const LiteralProp(1.0)},
          children: [
            WidgetNode(
              id: 'w_t',
              type: 'Text',
              props: {'data': const LiteralProp('x')},
            ),
          ],
        ),
      ]),
    ));

    expect(page, contains('aspectRatio: 1'));
  });

  test('an optional parameter at its default is still dropped', () {
    final page = generate(pageWith(
      hierarchy: WidgetNode(id: 'w_root', type: 'Scaffold', children: [
        WidgetNode(
          id: 'w_grid',
          type: 'GridView',
          props: {
            'crossAxisCount': const LiteralProp(2),
            // The default; nothing is gained by writing it out.
            'mainAxisSpacing': const LiteralProp(0.0),
          },
        ),
      ]),
    ));

    expect(page, isNot(contains('mainAxisSpacing')));
  });

  test('context use after an await is guarded', () {
    final page = generate(pageWith(
      hierarchy: WidgetNode(id: 'w_root', type: 'Scaffold', children: [
        WidgetNode(
          id: 'w_btn',
          type: 'ElevatedButton',
          props: {'onPressed': const EventProp('ev')},
          children: [
            WidgetNode(
              id: 'w_l',
              type: 'Text',
              props: {'data': const LiteralProp('go')},
            ),
          ],
        ),
      ]),
      graph: Graph(
        nodes: [
          GraphNode(
            id: 'ev',
            type: 'Event',
            config: {'widget': 'w_btn', 'event': 'onPressed'},
          ),
          GraphNode(
            id: 'c_t',
            type: 'Const',
            config: {'dartType': 'String', 'value': 'T'},
          ),
          GraphNode(
            id: 'c_m',
            type: 'Const',
            config: {'dartType': 'String', 'value': 'M'},
          ),
          GraphNode(id: 'a_dlg', type: 'ShowDialog'),
          GraphNode(
            id: 'c_s',
            type: 'Const',
            config: {'dartType': 'String', 'value': 'S'},
          ),
          GraphNode(id: 'a_snack', type: 'ShowSnackBar'),
        ],
        edges: const [
          Edge(PinRef('ev', 'fire'), PinRef('a_dlg', 'exec')),
          Edge(PinRef('c_t', 'value'), PinRef('a_dlg', 'title')),
          Edge(PinRef('c_m', 'value'), PinRef('a_dlg', 'message')),
          Edge(PinRef('a_dlg', 'next'), PinRef('a_snack', 'exec')),
          Edge(PinRef('c_s', 'value'), PinRef('a_snack', 'message')),
        ],
      ),
    ));

    expect(page, contains('await showDialog'));
    expect(page, contains('if (!mounted) return;'));
    // The guard goes between the two, not at the end where it would be dead.
    expect(
      page.indexOf('if (!mounted) return;'),
      lessThan(page.indexOf('showSnackBar')),
    );
  });

  test('a chain that never awaits gets no guard', () {
    final page = generate(pageWith(
      hierarchy: WidgetNode(id: 'w_root', type: 'Scaffold', children: [
        WidgetNode(
          id: 'w_btn',
          type: 'ElevatedButton',
          props: {'onPressed': const EventProp('ev')},
          children: [
            WidgetNode(
              id: 'w_l',
              type: 'Text',
              props: {'data': const LiteralProp('go')},
            ),
          ],
        ),
      ]),
      graph: Graph(
        nodes: [
          GraphNode(
            id: 'ev',
            type: 'Event',
            config: {'widget': 'w_btn', 'event': 'onPressed'},
          ),
          GraphNode(
            id: 'c_s',
            type: 'Const',
            config: {'dartType': 'String', 'value': 'S'},
          ),
          GraphNode(id: 'a_snack', type: 'ShowSnackBar'),
        ],
        edges: const [
          Edge(PinRef('ev', 'fire'), PinRef('a_snack', 'exec')),
          Edge(PinRef('c_s', 'value'), PinRef('a_snack', 'message')),
        ],
      ),
    ));

    expect(page, isNot(contains('mounted')));
  });

  test('Positioned is refused outside a Stack', () {
    final result = const Validator().validate(pageWith(
      hierarchy: WidgetNode(id: 'w_root', type: 'Scaffold', children: [
        WidgetNode(
          id: 'w_col',
          type: 'Column',
          children: [
            WidgetNode(
              id: 'w_pos',
              type: 'Positioned',
              props: {'left': const LiteralProp(4.0)},
            ),
          ],
        ),
      ]),
    ));

    expect(result.isValid, isFalse);
  });
}
