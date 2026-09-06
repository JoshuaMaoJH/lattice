import 'graph.dart';
import 'hierarchy.dart';
import 'page.dart';
import 'pin_ref.dart';
import 'project.dart';

/// The project a brand new Lattice project starts as: the §8 counter.
///
/// It lives here rather than inside the CLI because the editor needs the same
/// thing when it creates a project, and two starter projects that drift apart
/// is exactly the kind of difference nobody notices until it confuses someone.
class Starter {
  const Starter._();

  static Project project(
    String folder, {
    String? appName,
    String? package,
    RuntimeBackend runtime = RuntimeBackend.signals,
  }) {
    final name = appName ?? titleCase(folder);
    final pkg = package ?? packageName(folder);
    return Project(
      id: packageName(folder),
      config: ProjectConfig(
        appName: name,
        packageName: pkg,
        bundleId: 'com.example.$pkg',
        description: 'A Lattice project.',
        runtime: runtime,
      ),
      pages: [counterPage(name)],
    );
  }

  /// The §8 counter, expressed in the project model rather than in JSON, so
  /// this doubles as a worked example of the data structures.
  static Page counterPage(String appName) => Page(
        id: 'page_home',
        name: 'Home',
        route: '/',
        isHome: true,
        hierarchy: WidgetNode(
          id: 'w_root',
          type: 'Scaffold',
          props: {
            'appBar': WidgetProp(
              WidgetNode(
                id: 'w_appbar',
                type: 'AppBar',
                props: {
                  'title': WidgetProp(
                    WidgetNode(
                      id: 'w_title',
                      type: 'Text',
                      props: {'data': LiteralProp(appName)},
                    ),
                  ),
                },
              ),
            ),
          },
          children: [
            WidgetNode(
              id: 'w_center',
              type: 'Center',
              children: [
                WidgetNode(
                  id: 'w_col',
                  type: 'Column',
                  props: {
                    'mainAxisAlignment': const LiteralProp('center'),
                  },
                  children: [
                    WidgetNode(
                      id: 'w_txt',
                      type: 'Text',
                      props: {
                        'data': const BindProp(PinRef('n_fmt', 'out')),
                      },
                    ),
                    WidgetNode(
                      id: 'w_gap',
                      type: 'SizedBox',
                      props: {'height': const LiteralProp(12)},
                    ),
                    WidgetNode(
                      id: 'w_btn',
                      type: 'ElevatedButton',
                      props: {
                        'onPressed': const EventProp('ev_btn'),
                      },
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
              ],
            ),
          ],
        ),
        graph: Graph(
          nodes: [
            GraphNode(
              id: 'n_count',
              type: 'Signal',
              config: {'dartType': 'int', 'init': 0, 'name': 'count'},
            ),
            GraphNode(
              id: 'n_fmt',
              type: 'Format',
              config: {'template': 'Count: {0}'},
            ),
            GraphNode(
              id: 'ev_btn',
              type: 'Event',
              config: {'widget': 'w_btn', 'event': 'onPressed'},
            ),
            GraphNode(
              id: 'a_inc',
              type: 'UpdateSignal',
              config: {'signal': 'n_count', 'fn': '(x) => x + 1'},
            ),
          ],
          edges: const [
            Edge(PinRef('n_count', 'value'), PinRef('n_fmt', 'args', index: 0)),
            Edge(PinRef('ev_btn', 'fire'), PinRef('a_inc', 'exec')),
          ],
        ),
        layout: const {
          'n_count': CanvasPos(120, 80),
          'n_fmt': CanvasPos(340, 80),
          'ev_btn': CanvasPos(120, 260),
          'a_inc': CanvasPos(340, 260),
        },
      );


  static String packageName(String raw) {
    final cleaned = raw
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '_')
        .replaceAll(RegExp('^_+|_+\$'), '');
    final safe = cleaned.isEmpty ? 'lattice_app' : cleaned;
    return RegExp('^[0-9]').hasMatch(safe) ? 'app_$safe' : safe;
  }

  static String titleCase(String raw) => raw
      .split(RegExp('[^A-Za-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
