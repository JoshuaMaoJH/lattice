// R19's acceptance example: a list that is still there after a restart.
import 'package:lattice_core/io.dart';
import 'package:lattice_core/lattice_core.dart';

Future<void> main() async {
  final project = Project(
    id: 'notes',
    config: const ProjectConfig(
      appName: 'Notes',
      packageName: 'notes_app',
      bundleId: 'com.example.notes_app',
      description: 'A Lattice example: a list that survives a restart.',
      targets: [BuildTarget.linux, BuildTarget.web],
    ),
    models: [
      DataModelDef.fromJson(const {
        'name': 'Note',
        'fields': {'text': 'String', 'done': 'bool'},
      }, 'models.Note'),
    ],
    // The whole data layer: one declaration.
    collections: const [CollectionDef(name: 'notes', element: 'Note')],
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
            'appBar': WidgetProp(WidgetNode(
              id: 'w_bar',
              type: 'AppBar',
              props: {
                'title': WidgetProp(WidgetNode(
                  id: 'w_title',
                  type: 'Text',
                  props: {'data': const LiteralProp('Notes')},
                )),
              },
            )),
          },
          children: [
            WidgetNode(id: 'w_col', type: 'Column', children: [
              WidgetNode(
                id: 'w_field',
                type: 'TextField',
                props: {
                  'text': const BindProp(PinRef('n_draft', 'value')),
                  'onChanged': const EventProp('ev_typed'),
                  'hintText': const LiteralProp('Write a note'),
                },
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
              WidgetNode(
                id: 'w_count',
                type: 'Text',
                props: {'data': const BindProp(PinRef('n_countText', 'out'))},
              ),
              WidgetNode(id: 'w_list', type: 'Expanded', children: [
                WidgetNode(id: 'w_lv', type: 'ListView', children: [
                  WidgetNode(
                    id: 'w_each',
                    type: 'ForEach',
                    props: {
                      'items': const BindProp(PinRef('n_notes', 'items')),
                      'itemKey': const LiteralProp('text'),
                    },
                    children: [
                      WidgetNode(
                        id: 'w_tile',
                        type: 'ListTile',
                        props: {
                          'title': WidgetProp(WidgetNode(
                            id: 'w_tile_text',
                            type: 'Text',
                            props: {
                              'data':
                                  const BindProp(PinRef('n_itemText', 'out')),
                            },
                          )),
                          'onTap': const EventProp('ev_remove'),
                        },
                      ),
                    ],
                  ),
                ]),
              ]),
            ]),
          ],
        ),
        graph: Graph(
          nodes: [
            GraphNode(
              id: 'n_draft',
              type: 'Signal',
              config: const {'dartType': 'String', 'init': '', 'name': 'draft'},
            ),
            GraphNode(
              id: 'n_notes',
              type: 'CollectionItems',
              config: const {'collection': 'notes'},
            ),
            GraphNode(
              id: 'n_item',
              type: 'ForEachItem',
              config: const {'forEach': 'w_each'},
            ),
            GraphNode(
              id: 'n_itemText',
              type: 'Computed',
              config: const {
                'name': 'noteLabel',
                'dartType': 'String',
                'inputs': {'note': 'Note'},
                'expr': 'note.text',
              },
            ),
            GraphNode(
              id: 'n_countText',
              type: 'Computed',
              config: const {
                'name': 'noteCount',
                'dartType': 'String',
                'inputs': {'notes': 'List<Note>'},
                'expr': r"'${notes.length} note(s)'",
              },
            ),
            GraphNode(
              id: 'n_newNote',
              type: 'Computed',
              config: const {
                'name': 'newNote',
                'dartType': 'Note',
                'inputs': {'text': 'String'},
                'expr': 'Note(text: text, done: false)',
              },
            ),
            GraphNode(
              id: 'ev_typed',
              type: 'Event',
              config: const {'widget': 'w_field', 'event': 'onChanged'},
            ),
            GraphNode(
              id: 'a_setDraft',
              type: 'SetSignal',
              config: const {'signal': 'n_draft'},
            ),
            GraphNode(
              id: 'ev_add',
              type: 'Event',
              config: const {'widget': 'w_add', 'event': 'onPressed'},
            ),
            GraphNode(
              id: 'a_add',
              type: 'CollectionAdd',
              config: const {'collection': 'notes'},
            ),
            GraphNode(
              id: 'a_clearDraft',
              type: 'SetSignal',
              config: const {'signal': 'n_draft'},
            ),
            GraphNode(
              id: 'c_empty',
              type: 'Const',
              config: const {'dartType': 'String', 'value': ''},
            ),
            GraphNode(
              id: 'ev_remove',
              type: 'Event',
              config: const {'widget': 'w_tile', 'event': 'onTap'},
            ),
            GraphNode(
              id: 'a_remove',
              type: 'CollectionRemoveAt',
              config: const {'collection': 'notes'},
            ),
          ],
          edges: const [
            Edge(PinRef('n_notes', 'items'), PinRef('n_countText', 'notes')),
            Edge(PinRef('n_item', 'item'), PinRef('n_itemText', 'note')),
            Edge(PinRef('ev_typed', 'payload'), PinRef('a_setDraft', 'value')),
            Edge(PinRef('ev_typed', 'fire'), PinRef('a_setDraft', 'exec')),
            Edge(PinRef('n_draft', 'value'), PinRef('n_newNote', 'text')),
            Edge(PinRef('ev_add', 'fire'), PinRef('a_add', 'exec')),
            Edge(PinRef('n_newNote', 'out'), PinRef('a_add', 'item')),
            Edge(PinRef('a_add', 'next'), PinRef('a_clearDraft', 'exec')),
            Edge(PinRef('c_empty', 'value'), PinRef('a_clearDraft', 'value')),
            Edge(PinRef('ev_remove', 'fire'), PinRef('a_remove', 'exec')),
            Edge(PinRef('n_item', 'index'), PinRef('a_remove', 'index')),
          ],
        ),
        layout: const {
          'n_draft': CanvasPos(80, 60),
          'n_notes': CanvasPos(80, 180),
          'n_countText': CanvasPos(340, 180),
          'n_item': CanvasPos(80, 300),
          'n_itemText': CanvasPos(340, 300),
          'n_newNote': CanvasPos(340, 60),
          'ev_typed': CanvasPos(80, 440),
          'a_setDraft': CanvasPos(340, 440),
          'ev_add': CanvasPos(80, 540),
          'a_add': CanvasPos(340, 540),
          'a_clearDraft': CanvasPos(600, 540),
          'c_empty': CanvasPos(600, 640),
          'ev_remove': CanvasPos(80, 700),
          'a_remove': CanvasPos(340, 700),
        },
      ),
    ],
  );

  final result = const Validator().validate(project);
  if (!result.isValid) {
    print(result);
    return;
  }
  await ProjectIo.save(project, 'examples/notes');
  print('Wrote examples/notes (${result.diagnostics.length} diagnostics)');
}
