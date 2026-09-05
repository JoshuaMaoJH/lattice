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

/// A page with a `ForEach` over `List<Todo>`, for the scope tests.
///
/// `w_list` (a Column) holds the ForEach; `w_tile` is the template;
/// `n_item` is the ForEachItem, `n_title` a per-item computation.
Page listPage({
  Object? itemKey = 'id',
  bool titleOutsideTemplate = false,
  String listParent = 'Column',
}) {
  final tile = WidgetNode(
    id: 'w_tile',
    type: 'ListTile',
    props: {
      if (!titleOutsideTemplate)
        'title': WidgetProp(
          WidgetNode(
            id: 'w_tile_title',
            type: 'Text',
            props: {'data': const BindProp(PinRef('n_title', 'out'))},
          ),
        ),
    },
  );

  final forEach = WidgetNode(
    id: 'w_each',
    type: 'ForEach',
    props: {
      'items': const BindProp(PinRef('n_todos', 'value')),
      if (itemKey != null) 'itemKey': LiteralProp(itemKey),
    },
    children: [tile],
  );

  return Page(
    id: 'page_home',
    name: 'Home',
    route: '/',
    isHome: true,
    hierarchy: WidgetNode(
      id: 'w_root',
      type: 'Scaffold',
      children: [
        WidgetNode(
          id: 'w_list',
          type: listParent,
          children: [
            forEach,
            if (titleOutsideTemplate)
              WidgetNode(
                id: 'w_outside',
                type: 'Text',
                props: {'data': const BindProp(PinRef('n_title', 'out'))},
              ),
          ],
        ),
      ],
    ),
    graph: Graph(
      nodes: [
        GraphNode(
          id: 'n_todos',
          type: 'Signal',
          config: const {'dartType': 'List<Todo>', 'name': 'todos'},
        ),
        GraphNode(
          id: 'n_item',
          type: 'ForEachItem',
          config: const {'forEach': 'w_each'},
        ),
        GraphNode(
          id: 'n_title',
          type: 'Computed',
          config: const {
            'name': 'titleOf',
            'dartType': 'String',
            'inputs': {'item': 'Todo'},
            'expr': 'item.title',
          },
        ),
      ],
      edges: const [
        Edge(PinRef('n_item', 'item'), PinRef('n_title', 'item')),
      ],
    ),
  );
}

/// A project wrapping [listPage] with the `Todo` model it needs.
Project listProject({
  Object? itemKey = 'id',
  bool titleOutsideTemplate = false,
  String listParent = 'Column',
}) =>
    Project(
      id: 'list',
      config: const ProjectConfig(appName: 'List', packageName: 'list_app'),
      models: [
        DataModelDef.fromJson(const {
          'name': 'Todo',
          'fields': {'id': 'String', 'title': 'String', 'done': 'bool'},
          'defaults': {'done': false},
        }, 'fixture'),
      ],
      pages: [
        listPage(
          itemKey: itemKey,
          titleOutsideTemplate: titleOutsideTemplate,
          listParent: listParent,
        ),
      ],
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
