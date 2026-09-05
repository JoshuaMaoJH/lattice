import 'package:lattice_core/lattice_core.dart';

/// The §8 counter, in memory.
///
/// What `lattice new` writes, so the editor opens on the same program the
/// documentation walks through — and so a build with no filesystem still has
/// something real to edit.
Project sampleProject() => Project(
      id: 'counter',
      config: const ProjectConfig(
        appName: 'Counter',
        packageName: 'counter_app',
        bundleId: 'com.example.counter_app',
      ),
      pages: [
        Page(
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
                id: 'w_center',
                type: 'Center',
                children: [
                  WidgetNode(
                    id: 'w_col',
                    type: 'Column',
                    props: {'mainAxisAlignment': const LiteralProp('center')},
                    children: [
                      WidgetNode(
                        id: 'w_txt',
                        type: 'Text',
                        props: {
                          'data': const BindProp(PinRef('n_fmt', 'out')),
                          'style': const LiteralProp({
                            'fontSize': 32,
                            'fontWeight': 'bold',
                          }),
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
            ],
          ),
          graph: Graph(
            nodes: [
              GraphNode(
                id: 'n_count',
                type: 'Signal',
                config: const {'dartType': 'int', 'init': 0, 'name': 'count'},
              ),
              GraphNode(
                id: 'n_fmt',
                type: 'Format',
                config: const {'template': 'Count: {0}'},
              ),
              GraphNode(
                id: 'ev_btn',
                type: 'Event',
                config: const {'widget': 'w_btn', 'event': 'onPressed'},
              ),
              GraphNode(
                id: 'a_inc',
                type: 'UpdateSignal',
                config: const {'signal': 'n_count', 'fn': '(x) => x + 1'},
              ),
            ],
            edges: const [
              Edge(PinRef('n_count', 'value'),
                  PinRef('n_fmt', 'args', index: 0)),
              Edge(PinRef('ev_btn', 'fire'), PinRef('a_inc', 'exec')),
            ],
          ),
          layout: const {
            'n_count': CanvasPos(96, 96),
            'n_fmt': CanvasPos(368, 96),
            'ev_btn': CanvasPos(96, 320),
            'a_inc': CanvasPos(368, 320),
          },
        ),
      ],
    );
