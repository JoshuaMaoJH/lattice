// Authors examples/todo. The JSON it writes is the artifact; this file exists
// so the fixture is type-checked rather than hand-edited.
//
//   dart run tool/make_todo_example.dart
import 'package:lattice_core/io.dart';
import 'package:lattice_core/lattice_core.dart';

Future<void> main() async {
  final project = Project(
    id: 'todo',
    config: const ProjectConfig(
      appName: 'Todos',
      packageName: 'todo_app',
      bundleId: 'com.example.todo_app',
      description:
          'A Lattice example: a list you can add to, tick off and delete.',
      targets: [BuildTarget.linux, BuildTarget.web, BuildTarget.android],
    ),
    models: [
      DataModelDef.fromJson(const {
        'name': 'Todo',
        'fields': {'id': 'String', 'title': 'String', 'done': 'bool'},
        'defaults': {'done': false},
      }, 'todo'),
    ],
    pages: [_home(), _detail()],
    prefabs: [_statCard()],
  );

  await ProjectIo.save(project, 'examples/todo');
  final result = const Validator().validate(project);
  if (!result.isValid) {
    throw StateError('the fixture does not validate:\n$result');
  }
  print('Wrote examples/todo (${result.diagnostics.length} diagnostics)');
}

Page _home() => Page(
      id: 'page_home',
      name: 'Home',
      route: '/',
      isHome: true,
      hierarchy: _hierarchy(),
      graph: _graph(),
      layout: const {
        'n_todos': CanvasPos(80, 60),
        'n_draft': CanvasPos(80, 180),
        'n_seq': CanvasPos(80, 260),
        'n_item': CanvasPos(80, 420),
        'n_isEmpty': CanvasPos(520, 60),
        'n_newTodo': CanvasPos(320, 200),
        'n_appended': CanvasPos(540, 200),
        'n_itemTitle': CanvasPos(320, 400),
        'n_itemDone': CanvasPos(320, 470),
        'n_toggled': CanvasPos(320, 540),
        'n_replaced': CanvasPos(560, 540),
        'n_removed': CanvasPos(560, 640),
      },
    );

/// A reusable stat tile, placed three times on the home page (R9).
///
/// Its three parameters become constructor arguments; because it holds no
/// state of its own it compiles to a `StatelessWidget` with a const
/// constructor, so each placement is free.
Prefab _statCard() => Prefab(
      id: 'prefab_stat_card',
      name: 'StatCard',
      parameters: [
        const FieldDef(name: 'label', type: PrimitiveType.string),
        const FieldDef(name: 'value', type: PrimitiveType.string),
        FieldDef(
          name: 'accent',
          type: NullableType(PrimitiveType.color),
        ),
      ],
      hierarchy: WidgetNode(
        id: 's_root',
        type: 'Container',
        props: {
          'padding': const LiteralProp({'horizontal': 20, 'vertical': 12}),
          'color': const BindProp(PinRef('s_accent', 'value')),
        },
        children: [
          WidgetNode(
            id: 's_col',
            type: 'Column',
            props: {'mainAxisSize': const LiteralProp('min')},
            children: [
              WidgetNode(
                id: 's_value',
                type: 'Text',
                props: {
                  'data': const BindProp(PinRef('s_valueParam', 'value')),
                  'style': const LiteralProp({
                    'fontSize': 22,
                    'fontWeight': 'bold',
                  }),
                },
              ),
              WidgetNode(
                id: 's_label',
                type: 'Text',
                props: {
                  'data': const BindProp(PinRef('s_labelParam', 'value')),
                  'style': const LiteralProp({'fontSize': 12}),
                },
              ),
            ],
          ),
        ],
      ),
      graph: Graph(
        nodes: [
          GraphNode(
            id: 's_labelParam',
            type: 'PageParam',
            config: const {'name': 'label'},
          ),
          GraphNode(
            id: 's_valueParam',
            type: 'PageParam',
            config: const {'name': 'value'},
          ),
          GraphNode(
            id: 's_accent',
            type: 'PageParam',
            config: const {'name': 'accent'},
          ),
        ],
      ),
      layout: const {
        's_labelParam': CanvasPos(80, 60),
        's_valueParam': CanvasPos(80, 140),
        's_accent': CanvasPos(80, 220),
      },
    );

/// A second route, reached by tapping a row. Its two values arrive as
/// navigation arguments and become constructor parameters (R12).
Page _detail() => Page(
      id: 'page_detail',
      name: 'Detail',
      route: '/detail',
      parameters: [
        const FieldDef(name: 'title', type: PrimitiveType.string),
        const FieldDef(
            name: 'done', type: PrimitiveType.bool_, defaultValue: false),
      ],
      hierarchy: WidgetNode(
        id: 'd_root',
        type: 'Scaffold',
        props: {
          'appBar': WidgetProp(
            WidgetNode(
              id: 'd_appbar',
              type: 'AppBar',
              props: {
                'title': WidgetProp(
                  WidgetNode(
                    id: 'd_appbar_title',
                    type: 'Text',
                    props: {'data': const LiteralProp('Detail')},
                  ),
                ),
              },
            ),
          ),
        },
        children: [
          WidgetNode(
            id: 'd_pad',
            type: 'Padding',
            props: {'padding': const LiteralProp(24)},
            children: [
              WidgetNode(
                id: 'd_col',
                type: 'Column',
                props: {
                  'crossAxisAlignment': const LiteralProp('start'),
                  'mainAxisSize': const LiteralProp('min'),
                },
                children: [
                  WidgetNode(
                    id: 'd_title',
                    type: 'Text',
                    props: {
                      'data': const BindProp(PinRef('p_title', 'value')),
                      'style': const LiteralProp({
                        'fontSize': 24,
                        'fontWeight': 'bold',
                      }),
                    },
                  ),
                  WidgetNode(
                    id: 'd_gap',
                    type: 'SizedBox',
                    props: {'height': const LiteralProp(12)},
                  ),
                  WidgetNode(
                    id: 'd_status',
                    type: 'Text',
                    props: {
                      'data': const BindProp(PinRef('n_status', 'out')),
                    },
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
            id: 'p_title',
            type: 'PageParam',
            config: const {'name': 'title'},
          ),
          GraphNode(
            id: 'p_done',
            type: 'PageParam',
            config: const {'name': 'done'},
          ),
          GraphNode(
            id: 'n_doneText',
            type: 'Const',
            config: const {'dartType': 'String', 'value': 'Done'},
          ),
          GraphNode(
            id: 'n_openText',
            type: 'Const',
            config: const {'dartType': 'String', 'value': 'Still to do'},
          ),
          GraphNode(
            id: 'n_status',
            type: 'Conditional',
            config: const {'dartType': 'String', 'name': 'status'},
          ),
        ],
        edges: const [
          Edge(PinRef('p_done', 'value'), PinRef('n_status', 'condition')),
          Edge(PinRef('n_doneText', 'value'), PinRef('n_status', 'ifTrue')),
          Edge(PinRef('n_openText', 'value'), PinRef('n_status', 'ifFalse')),
        ],
      ),
      layout: const {
        'p_title': CanvasPos(80, 60),
        'p_done': CanvasPos(80, 160),
        'n_status': CanvasPos(360, 160),
      },
    );

WidgetNode _hierarchy() => WidgetNode(
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
                  props: {'data': const LiteralProp('Todos')},
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
          children: [
            // --- the composer -------------------------------------------
            WidgetNode(
              id: 'w_pad',
              type: 'Padding',
              props: {'padding': const LiteralProp(16)},
              children: [
                WidgetNode(
                  id: 'w_row',
                  type: 'Row',
                  children: [
                    WidgetNode(
                      id: 'w_exp',
                      type: 'Expanded',
                      children: [
                        WidgetNode(
                          id: 'w_input',
                          type: 'TextField',
                          props: {
                            'hintText': const LiteralProp('What needs doing?'),
                            'text': const BindProp(PinRef('n_draft', 'value')),
                            'onChanged': const EventProp('ev_input'),
                          },
                        ),
                      ],
                    ),
                    WidgetNode(
                      id: 'w_gap',
                      type: 'SizedBox',
                      props: {'width': const LiteralProp(12)},
                    ),
                    WidgetNode(
                      id: 'w_add',
                      type: 'ElevatedButton',
                      props: {'onPressed': const EventProp('ev_add')},
                      children: [
                        WidgetNode(
                          id: 'w_add_label',
                          type: 'Text',
                          props: {'data': const LiteralProp('Add')},
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),

            // --- three placements of the same prefab (R9) ---------------
            WidgetNode(
              id: 'w_stats',
              type: 'Row',
              props: {
                'mainAxisAlignment': const LiteralProp('spaceEvenly'),
              },
              children: [
                WidgetNode(
                  id: 'w_stat_total',
                  type: 'StatCard',
                  props: {
                    'label': const LiteralProp('Total'),
                    'value': const BindProp(PinRef('n_totalText', 'out')),
                    'accent': const LiteralProp('#E8DEF8'),
                  },
                ),
                WidgetNode(
                  id: 'w_stat_done',
                  type: 'StatCard',
                  props: {
                    'label': const LiteralProp('Done'),
                    'value': const BindProp(PinRef('n_doneText', 'out')),
                    'accent': const LiteralProp('#D7F0DB'),
                  },
                ),
                WidgetNode(
                  id: 'w_stat_left',
                  type: 'StatCard',
                  props: {
                    'label': const LiteralProp('Left'),
                    'value': const BindProp(PinRef('n_leftText', 'out')),
                    'accent': const LiteralProp('#FFE0E0'),
                  },
                ),
              ],
            ),

            // --- empty state --------------------------------------------
            WidgetNode(
              id: 'w_empty',
              type: 'If',
              props: {
                'condition': const BindProp(PinRef('n_isEmpty', 'out')),
              },
              children: [
                WidgetNode(
                  id: 'w_empty_pad',
                  type: 'Padding',
                  props: {'padding': const LiteralProp(24)},
                  children: [
                    WidgetNode(
                      id: 'w_empty_text',
                      type: 'Text',
                      props: {
                        'data': const LiteralProp('Nothing here yet.'),
                      },
                    ),
                  ],
                ),
              ],
            ),

            // --- the list -----------------------------------------------
            WidgetNode(
              id: 'w_listexp',
              type: 'Expanded',
              children: [
                WidgetNode(
                  id: 'w_list',
                  type: 'ListView',
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
                          id: 'w_tile',
                          type: 'ListTile',
                          props: {
                            'onTap': const EventProp('ev_tap'),
                            'leading': WidgetProp(
                              WidgetNode(
                                id: 'w_check',
                                type: 'Checkbox',
                                props: {
                                  'value': const BindProp(
                                    PinRef('n_itemDone', 'out'),
                                  ),
                                  'onChanged': const EventProp('ev_toggle'),
                                },
                              ),
                            ),
                            'title': WidgetProp(
                              WidgetNode(
                                id: 'w_tile_title',
                                type: 'Text',
                                props: {
                                  'data': const BindProp(
                                    PinRef('n_itemTitle', 'out'),
                                  ),
                                },
                              ),
                            ),
                            'trailing': WidgetProp(
                              WidgetNode(
                                id: 'w_del',
                                type: 'IconButton',
                                props: {
                                  'onPressed': const EventProp('ev_del'),
                                  'icon': WidgetProp(
                                    WidgetNode(
                                      id: 'w_del_icon',
                                      type: 'Icon',
                                      props: {
                                        'icon':
                                            const LiteralProp('delete_outline'),
                                      },
                                    ),
                                  ),
                                },
                              ),
                            ),
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );

Graph _graph() => Graph(
      nodes: [
        GraphNode(
          id: 'n_todos',
          type: 'Signal',
          config: const {'dartType': 'List<Todo>', 'name': 'todos'},
        ),
        GraphNode(
          id: 'n_draft',
          type: 'Signal',
          config: const {'dartType': 'String', 'init': '', 'name': 'draft'},
        ),
        GraphNode(
          id: 'n_seq',
          type: 'Signal',
          config: const {'dartType': 'int', 'init': 0, 'name': 'seq'},
        ),
        GraphNode(
          id: 'n_empty_string',
          type: 'Const',
          config: const {'dartType': 'String', 'value': ''},
        ),
        GraphNode(
          id: 'n_total',
          type: 'ListLength',
          config: const {'elementType': 'Todo', 'name': 'total'},
        ),
        GraphNode(
          id: 'n_done',
          type: 'DartCode',
          config: const {
            'name': 'doneCount',
            'dartType': 'int',
            'inputs': {'todos': 'List<Todo>'},
            'imports': ['custom/labels.dart'],
            'body': 'return countDone(todos);',
          },
        ),
        GraphNode(
          id: 'n_left',
          type: 'Subtract',
          config: const {'dartType': 'int', 'name': 'left'},
        ),
        GraphNode(
          id: 'n_totalText',
          type: 'Format',
          config: const {'template': '{0}'},
        ),
        GraphNode(
          id: 'n_doneText',
          type: 'Format',
          config: const {'template': '{0}'},
        ),
        GraphNode(
          id: 'n_leftText',
          type: 'Format',
          config: const {'template': '{0}'},
        ),
        GraphNode(
          id: 'n_isEmpty',
          type: 'ListIsEmpty',
          config: const {'elementType': 'Todo', 'name': 'isEmpty'},
        ),
        GraphNode(
          id: 'n_newTodo',
          type: 'Computed',
          config: const {
            'name': 'buildTodo',
            'dartType': 'Todo',
            'inputs': {'id': 'int', 'title': 'String'},
            'expr': r"Todo(id: 'todo_$id', title: title.trim())",
          },
        ),
        GraphNode(
          id: 'n_appended',
          type: 'ListAppend',
          config: const {'elementType': 'Todo'},
        ),

        // --- inside the ForEach template ------------------------------
        GraphNode(
          id: 'n_item',
          type: 'ForEachItem',
          config: const {'forEach': 'w_each'},
        ),
        // Reaches into lib/custom/, which codegen never overwrites (§7.8).
        GraphNode(
          id: 'n_itemTitle',
          type: 'DartCode',
          config: const {
            'name': 'titleOf',
            'dartType': 'String',
            'inputs': {'item': 'Todo'},
            'imports': ['custom/labels.dart'],
            'body': 'return decorate(item.title, done: item.done);',
          },
        ),
        GraphNode(
          id: 'n_rawTitle',
          type: 'Computed',
          config: const {
            'name': 'rawTitleOf',
            'dartType': 'String',
            'inputs': {'item': 'Todo'},
            'expr': 'item.title',
          },
        ),
        GraphNode(
          id: 'n_itemDone',
          type: 'Computed',
          config: const {
            'name': 'doneOf',
            'dartType': 'bool',
            'inputs': {'item': 'Todo'},
            'expr': 'item.done',
          },
        ),
        GraphNode(
          id: 'n_toggled',
          type: 'Computed',
          config: const {
            'name': 'toggle',
            'dartType': 'Todo',
            'inputs': {'item': 'Todo'},
            'expr': 'item.copyWith(done: !item.done)',
          },
        ),
        GraphNode(
          id: 'n_replaced',
          type: 'ListSetAt',
          config: const {'elementType': 'Todo'},
        ),
        GraphNode(
          id: 'n_removed',
          type: 'ListRemoveAt',
          config: const {'elementType': 'Todo'},
        ),

        // --- events and actions ---------------------------------------
        GraphNode(
          id: 'ev_input',
          type: 'Event',
          config: const {'widget': 'w_input', 'event': 'onChanged'},
        ),
        GraphNode(
          id: 'a_draft',
          type: 'SetSignal',
          config: const {'signal': 'n_draft'},
        ),
        GraphNode(
          id: 'ev_add',
          type: 'Event',
          config: const {'widget': 'w_add', 'event': 'onPressed'},
        ),
        GraphNode(
          id: 'a_bump',
          type: 'UpdateSignal',
          config: const {'signal': 'n_seq', 'fn': '(x) => x + 1'},
        ),
        GraphNode(
          id: 'a_append',
          type: 'SetSignal',
          config: const {'signal': 'n_todos'},
        ),
        GraphNode(
          id: 'a_clear',
          type: 'SetSignal',
          config: const {'signal': 'n_draft'},
        ),
        GraphNode(
          id: 'ev_toggle',
          type: 'Event',
          config: const {'widget': 'w_check', 'event': 'onChanged'},
        ),
        GraphNode(
          id: 'a_toggle',
          type: 'SetSignal',
          config: const {'signal': 'n_todos'},
        ),
        GraphNode(
          id: 'ev_tap',
          type: 'Event',
          config: const {'widget': 'w_tile', 'event': 'onTap'},
        ),
        GraphNode(
          id: 'a_open',
          type: 'Navigate',
          config: const {'route': '/detail'},
        ),
        GraphNode(
          id: 'ev_del',
          type: 'Event',
          config: const {'widget': 'w_del', 'event': 'onPressed'},
        ),
        GraphNode(
          id: 'a_remove',
          type: 'SetSignal',
          config: const {'signal': 'n_todos'},
        ),
      ],
      edges: const [
        // counters feeding the three stat cards
        Edge(PinRef('n_todos', 'value'), PinRef('n_total', 'list')),
        Edge(PinRef('n_todos', 'value'), PinRef('n_done', 'todos')),
        Edge(PinRef('n_total', 'out'), PinRef('n_left', 'a')),
        Edge(PinRef('n_done', 'out'), PinRef('n_left', 'b')),
        Edge(PinRef('n_total', 'out'), PinRef('n_totalText', 'args', index: 0)),
        Edge(PinRef('n_done', 'out'), PinRef('n_doneText', 'args', index: 0)),
        Edge(PinRef('n_left', 'out'), PinRef('n_leftText', 'args', index: 0)),

        // empty state
        Edge(PinRef('n_todos', 'value'), PinRef('n_isEmpty', 'list')),

        // add
        Edge(PinRef('ev_input', 'payload'), PinRef('a_draft', 'value')),
        Edge(PinRef('ev_input', 'fire'), PinRef('a_draft', 'exec')),
        Edge(PinRef('n_seq', 'value'), PinRef('n_newTodo', 'id')),
        Edge(PinRef('n_draft', 'value'), PinRef('n_newTodo', 'title')),
        Edge(PinRef('n_todos', 'value'), PinRef('n_appended', 'list')),
        Edge(PinRef('n_newTodo', 'out'), PinRef('n_appended', 'item')),
        Edge(PinRef('ev_add', 'fire'), PinRef('a_bump', 'exec')),
        Edge(PinRef('a_bump', 'next'), PinRef('a_append', 'exec')),
        Edge(PinRef('n_appended', 'out'), PinRef('a_append', 'value')),
        Edge(PinRef('a_append', 'next'), PinRef('a_clear', 'exec')),
        Edge(PinRef('n_empty_string', 'value'), PinRef('a_clear', 'value')),

        // per-item reads
        Edge(PinRef('n_item', 'item'), PinRef('n_rawTitle', 'item')),
        Edge(PinRef('n_item', 'item'), PinRef('n_itemTitle', 'item')),
        Edge(PinRef('n_item', 'item'), PinRef('n_itemDone', 'item')),
        Edge(PinRef('n_item', 'item'), PinRef('n_toggled', 'item')),

        // toggle
        Edge(PinRef('n_todos', 'value'), PinRef('n_replaced', 'list')),
        Edge(PinRef('n_item', 'index'), PinRef('n_replaced', 'index')),
        Edge(PinRef('n_toggled', 'out'), PinRef('n_replaced', 'item')),
        Edge(PinRef('ev_toggle', 'fire'), PinRef('a_toggle', 'exec')),
        Edge(PinRef('n_replaced', 'out'), PinRef('a_toggle', 'value')),

        // open the detail route with this row's values
        Edge(PinRef('ev_tap', 'fire'), PinRef('a_open', 'exec')),
        Edge(PinRef('n_rawTitle', 'out'), PinRef('a_open', 'title')),
        Edge(PinRef('n_itemDone', 'out'), PinRef('a_open', 'done')),

        // delete
        Edge(PinRef('n_todos', 'value'), PinRef('n_removed', 'list')),
        Edge(PinRef('n_item', 'index'), PinRef('n_removed', 'index')),
        Edge(PinRef('ev_del', 'fire'), PinRef('a_remove', 'exec')),
        Edge(PinRef('n_removed', 'out'), PinRef('a_remove', 'value')),
      ],
    );
