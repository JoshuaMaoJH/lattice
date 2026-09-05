// Authors examples/todo. The JSON it writes is the artifact; this file exists
// so the fixture is type-checked rather than hand-edited.
//
//   dart run tool/make_todo_example.dart
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
    pages: [_home()],
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
        GraphNode(
          id: 'n_itemTitle',
          type: 'Computed',
          config: const {
            'name': 'titleOf',
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
        Edge(PinRef('n_item', 'item'), PinRef('n_itemTitle', 'item')),
        Edge(PinRef('n_item', 'item'), PinRef('n_itemDone', 'item')),
        Edge(PinRef('n_item', 'item'), PinRef('n_toggled', 'item')),

        // toggle
        Edge(PinRef('n_todos', 'value'), PinRef('n_replaced', 'list')),
        Edge(PinRef('n_item', 'index'), PinRef('n_replaced', 'index')),
        Edge(PinRef('n_toggled', 'out'), PinRef('n_replaced', 'item')),
        Edge(PinRef('ev_toggle', 'fire'), PinRef('a_toggle', 'exec')),
        Edge(PinRef('n_replaced', 'out'), PinRef('a_toggle', 'value')),

        // delete
        Edge(PinRef('n_todos', 'value'), PinRef('n_removed', 'list')),
        Edge(PinRef('n_item', 'index'), PinRef('n_removed', 'index')),
        Edge(PinRef('ev_del', 'fire'), PinRef('a_remove', 'exec')),
        Edge(PinRef('n_removed', 'out'), PinRef('a_remove', 'value')),
      ],
    );
