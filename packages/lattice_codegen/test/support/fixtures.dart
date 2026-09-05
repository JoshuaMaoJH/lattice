import 'package:lattice_core/lattice_core.dart';

/// The §8 counter, as a project model. Shared by the validation, serialization
/// and codegen tests so they all describe the same reference program.
Project counterProject({RuntimeBackend runtime = RuntimeBackend.signals}) =>
    Project(
      id: 'counter',
      config: ProjectConfig(
        appName: 'Counter',
        packageName: 'counter_app',
        bundleId: 'com.example.counter_app',
        runtime: runtime,
      ),
      pages: [counterPage()],
    );

Page counterPage() => Page(
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
                    props: {'data': const LiteralProp('Counter')},
                  ),
                ),
              },
            ),
          ),
        },
        children: [
          WidgetNode(
            id: 'w_col',
            type: 'Column',
            props: {'mainAxisAlignment': const LiteralProp('center')},
            children: [
              WidgetNode(
                id: 'w_txt',
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
      layout: const {'n_count': CanvasPos(120, 80)},
    );

/// Replaces one graph node in [page], keeping everything else identical.
Page withNode(Page page, GraphNode replacement) => page.copyWith(
      graph: Graph(
        nodes: [
          for (final node in page.graph.nodes)
            if (node.id == replacement.id) replacement else node,
        ],
        edges: page.graph.edges,
      ),
    );

/// Adds edges to [page]'s graph.
Page withEdges(Page page, List<Edge> extra) => page.copyWith(
      graph: Graph(
        nodes: page.graph.nodes,
        edges: [...page.graph.edges, ...extra],
      ),
    );

/// A struct with a nested list and a defaulted field, to exercise the parts of
/// the model emitter that a flat all-required struct would not reach.
abstract final class DataModelDefFixture {
  static final DataModelDef todo = DataModelDef.fromJson(const {
    'name': 'Todo',
    'fields': {
      'id': 'String',
      'title': 'String',
      'done': 'bool',
      'tags': 'List<String>',
      'dueAt': 'String?',
    },
    'defaults': {'done': false},
  }, 'fixture');
}
