// Authors examples/signup — the R14 example.
//
// A signup form's validation is the smallest thing that honestly needs fifty
// nodes: three fields, each with its own length rule and shape rule, joined
// into one "is the form valid" answer. Folded, it fits on a screen; unfolded,
// every rule is visible. That is the whole claim R14 makes.
//
//   dart run tool/make_signup_example.dart
import 'dart:convert';
import 'dart:io';

import 'package:lattice_core/io.dart';
import 'package:lattice_core/lattice_core.dart';

/// One field's rules, as a cluster of nodes.
class _Field {
  const _Field({
    required this.prefix,
    required this.signal,
    required this.label,
    required this.minLength,
    required this.shapeExpr,
    required this.complaint,
    this.shapeInputs = const {'text': 'String'},
    this.extraShapeEdge,
  });

  final String prefix;
  final String signal;
  final String label;
  final int minLength;
  final String shapeExpr;
  final String complaint;
  final Map<String, String> shapeInputs;

  /// A second input to the shape check — "confirm" needs the password too.
  final (PinRef, String)? extraShapeEdge;

  String get lengthNode => 'n_${prefix}_len';
  String get minNode => 'n_${prefix}_min';
  String get longNode => 'n_${prefix}_long';
  String get shapeNode => 'n_${prefix}_shape';
  String get okNode => 'n_${prefix}_ok';
  String get emptyNode => 'n_${prefix}_blank';
  String get complaintNode => 'n_${prefix}_say';
  String get messageNode => 'n_${prefix}_msg';

  List<String> get members => [
        lengthNode,
        minNode,
        longNode,
        shapeNode,
        okNode,
        emptyNode,
        complaintNode,
        messageNode,
      ];

  List<GraphNode> nodes() => [
        GraphNode(
          id: lengthNode,
          type: 'Computed',
          config: {
            'name': '${prefix}Length',
            'dartType': 'int',
            'inputs': const {'text': 'String'},
            'expr': 'text.trim().length',
          },
        ),
        GraphNode(
          id: minNode,
          type: 'Const',
          config: {'dartType': 'int', 'value': minLength},
        ),
        GraphNode(
          id: longNode,
          type: 'GreaterOrEqual',
          config: const {'dartType': 'int'},
        ),
        GraphNode(
          id: shapeNode,
          type: 'Computed',
          config: {
            'name': '${prefix}Shape',
            'dartType': 'bool',
            'inputs': shapeInputs,
            'expr': shapeExpr,
          },
        ),
        GraphNode(id: okNode, type: 'And'),
        GraphNode(
          id: emptyNode,
          type: 'Const',
          config: const {'dartType': 'String', 'value': ''},
        ),
        GraphNode(
          id: complaintNode,
          type: 'Const',
          config: {'dartType': 'String', 'value': complaint},
        ),
        GraphNode(
          id: messageNode,
          type: 'Conditional',
          config: {'dartType': 'String', 'name': '${prefix}Message'},
        ),
      ];

  List<Edge> edges() => [
        Edge(PinRef(signal, 'value'), PinRef(lengthNode, 'text')),
        Edge(PinRef(signal, 'value'), PinRef(shapeNode, 'text')),
        Edge(PinRef(lengthNode, 'out'), PinRef(longNode, 'a')),
        Edge(PinRef(minNode, 'value'), PinRef(longNode, 'b')),
        Edge(PinRef(longNode, 'out'), PinRef(okNode, 'a')),
        Edge(PinRef(shapeNode, 'out'), PinRef(okNode, 'b')),
        Edge(PinRef(okNode, 'out'), PinRef(messageNode, 'condition')),
        Edge(PinRef(emptyNode, 'value'), PinRef(messageNode, 'ifTrue')),
        Edge(PinRef(complaintNode, 'value'), PinRef(messageNode, 'ifFalse')),
        if (extraShapeEdge case (final source, final pin)?)
          Edge(source, PinRef(shapeNode, pin)),
      ];

  Map<String, CanvasPos> layout(double x, double y) => {
        lengthNode: CanvasPos(x, y),
        minNode: CanvasPos(x, y + 80),
        longNode: CanvasPos(x + 208, y + 32),
        shapeNode: CanvasPos(x, y + 160),
        okNode: CanvasPos(x + 416, y + 96),
        emptyNode: CanvasPos(x + 208, y + 160),
        complaintNode: CanvasPos(x + 208, y + 240),
        messageNode: CanvasPos(x + 624, y + 144),
      };
}

const _fields = [
  _Field(
    prefix: 'email',
    signal: 'n_email',
    label: 'Email',
    minLength: 5,
    shapeExpr: "text.contains('@') && text.split('@').last.contains('.')",
    complaint: 'That does not look like an email address.',
  ),
  _Field(
    prefix: 'pass',
    signal: 'n_password',
    label: 'Password',
    minLength: 8,
    shapeExpr: r"text.contains(RegExp('[0-9]'))",
    complaint: 'Use at least 8 characters and one digit.',
  ),
  _Field(
    prefix: 'again',
    signal: 'n_confirm',
    label: 'Repeat password',
    minLength: 1,
    shapeExpr: 'text == other',
    complaint: 'The two passwords do not match.',
    shapeInputs: {'text': 'String', 'other': 'String'},
    extraShapeEdge: (PinRef('n_password', 'value'), 'other'),
  ),
];

Future<void> main() async {
  final project = Project(
    id: 'signup',
    config: const ProjectConfig(
      appName: 'Signup',
      packageName: 'signup_app',
      bundleId: 'com.example.signup_app',
      description: 'A Lattice example: form validation, folded into groups.',
      targets: [BuildTarget.linux, BuildTarget.web],
    ),
    pages: [_home()],
  );

  await ProjectIo.save(project, 'examples/signup');

  // The editor bundles this one as its demo, so a build with no filesystem
  // still opens something worth looking at.
  final bundle = File('apps/lattice_editor/assets/demo/signup.json');
  await bundle.parent.create(recursive: true);
  await bundle.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(project.toBundleJson())}\n',
  );

  final result = const Validator().validate(project);
  if (!result.isValid) {
    throw StateError('the fixture does not validate:\n$result');
  }
  final page = project.pages.single;
  print(
    'Wrote examples/signup — ${page.graph.nodes.length} nodes, '
    '${page.graph.edges.length} edges, '
    '${page.graph.ofType('Subgraph').length} folds '
    '(${result.diagnostics.length} diagnostics)',
  );
}

Page _home() => Page(
      id: 'page_home',
      name: 'Sign up',
      route: '/',
      isHome: true,
      hierarchy: _hierarchy(),
      graph: _graph(),
      layout: _layout(),
    );

WidgetNode _textField(String id, String label, String signal, String event) =>
    WidgetNode(
      id: id,
      type: 'TextField',
      props: {
        'labelText': LiteralProp(label),
        'text': BindProp(PinRef(signal, 'value')),
        'onChanged': EventProp(event),
        if (id != 'w_email') 'obscureText': const LiteralProp(true),
      },
    );

WidgetNode _message(String id, String node) => WidgetNode(
      id: id,
      type: 'Text',
      props: {
        'data': BindProp(PinRef(node, 'out')),
        'style': const LiteralProp({'fontSize': 12, 'color': '#B3261E'}),
      },
    );

WidgetNode _gap(String id) => WidgetNode(
      id: id,
      type: 'SizedBox',
      props: {'height': const LiteralProp(14)},
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
                  props: {'data': const LiteralProp('Create an account')},
                ),
              ),
            },
          ),
        ),
      },
      children: [
        WidgetNode(
          id: 'w_pad',
          type: 'Padding',
          props: {'padding': const LiteralProp(24)},
          children: [
            WidgetNode(
              id: 'w_col',
              type: 'Column',
              props: {
                'crossAxisAlignment': const LiteralProp('stretch'),
                'mainAxisSize': const LiteralProp('min'),
              },
              children: [
                _textField('w_email', 'Email', 'n_email', 'ev_email'),
                _message('w_email_msg', 'n_email_msg'),
                _gap('w_gap1'),
                _textField('w_pass', 'Password', 'n_password', 'ev_pass'),
                _message('w_pass_msg', 'n_pass_msg'),
                _gap('w_gap2'),
                _textField(
                    'w_again', 'Repeat password', 'n_confirm', 'ev_again'),
                _message('w_again_msg', 'n_again_msg'),
                _gap('w_gap3'),
                WidgetNode(
                  id: 'w_terms',
                  type: 'Row',
                  children: [
                    WidgetNode(
                      id: 'w_accept',
                      type: 'Checkbox',
                      props: {
                        'value': const BindProp(PinRef('n_accepted', 'value')),
                        'onChanged': const EventProp('ev_accept'),
                      },
                    ),
                    WidgetNode(
                      id: 'w_terms_text',
                      type: 'Text',
                      props: {
                        'data': const LiteralProp('I accept the terms'),
                      },
                    ),
                  ],
                ),
                _gap('w_gap4'),
                WidgetNode(
                  id: 'w_status',
                  type: 'Text',
                  props: {
                    'data': const BindProp(PinRef('n_status', 'out')),
                  },
                ),
                _gap('w_gap5'),
                WidgetNode(
                  id: 'w_submit',
                  type: 'ElevatedButton',
                  props: {'onPressed': const EventProp('ev_submit')},
                  children: [
                    WidgetNode(
                      id: 'w_submit_label',
                      type: 'Text',
                      props: {'data': const LiteralProp('Create account')},
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
          id: 'n_email',
          type: 'Signal',
          config: const {'dartType': 'String', 'init': '', 'name': 'email'},
        ),
        GraphNode(
          id: 'n_password',
          type: 'Signal',
          config: const {'dartType': 'String', 'init': '', 'name': 'password'},
        ),
        GraphNode(
          id: 'n_confirm',
          type: 'Signal',
          config: const {'dartType': 'String', 'init': '', 'name': 'confirm'},
        ),
        GraphNode(
          id: 'n_accepted',
          type: 'Signal',
          config: const {
            'dartType': 'bool',
            'init': false,
            'name': 'accepted',
          },
        ),

        for (final field in _fields) ...field.nodes(),

        // --- the form's own answer ------------------------------------
        GraphNode(id: 'n_creds_ok', type: 'And'),
        GraphNode(id: 'n_fields_ok', type: 'And'),
        GraphNode(id: 'n_form_ok', type: 'And'),
        GraphNode(
          id: 'n_ready',
          type: 'Const',
          config: const {'dartType': 'String', 'value': 'Ready to go.'},
        ),
        GraphNode(
          id: 'n_incomplete',
          type: 'Const',
          config: const {
            'dartType': 'String',
            'value': 'Fill in every field to continue.',
          },
        ),
        GraphNode(
          id: 'n_status',
          type: 'Conditional',
          config: const {'dartType': 'String', 'name': 'status'},
        ),
        // Two reroutes, purely to keep the long wires from the fields to the
        // summary out of the middle of the canvas.
        GraphNode(
            id: 'n_bend_a',
            type: 'Reroute',
            config: const {'dartType': 'bool'}),
        GraphNode(
            id: 'n_bend_b',
            type: 'Reroute',
            config: const {'dartType': 'bool'}),

        // --- events and actions ---------------------------------------
        GraphNode(
          id: 'ev_email',
          type: 'Event',
          config: const {'widget': 'w_email', 'event': 'onChanged'},
        ),
        GraphNode(
          id: 'a_email',
          type: 'SetSignal',
          config: const {'signal': 'n_email'},
        ),
        GraphNode(
          id: 'ev_pass',
          type: 'Event',
          config: const {'widget': 'w_pass', 'event': 'onChanged'},
        ),
        GraphNode(
          id: 'a_pass',
          type: 'SetSignal',
          config: const {'signal': 'n_password'},
        ),
        GraphNode(
          id: 'ev_again',
          type: 'Event',
          config: const {'widget': 'w_again', 'event': 'onChanged'},
        ),
        GraphNode(
          id: 'a_again',
          type: 'SetSignal',
          config: const {'signal': 'n_confirm'},
        ),
        GraphNode(
          id: 'ev_accept',
          type: 'Event',
          config: const {'widget': 'w_accept', 'event': 'onChanged'},
        ),
        GraphNode(
          id: 'a_accept',
          type: 'ToggleSignal',
          config: const {'signal': 'n_accepted'},
        ),
        GraphNode(
          id: 'ev_submit',
          type: 'Event',
          config: const {'widget': 'w_submit', 'event': 'onPressed'},
        ),
        GraphNode(id: 'a_submit', type: 'ShowSnackBar'),

        // --- organisation (R14) ---------------------------------------
        for (final field in _fields)
          GraphNode(
            id: 'g_${field.prefix}',
            type: 'Subgraph',
            config: {
              'name': '${field.label} rules',
              'members': field.members,
              'collapsed': true,
            },
          ),
        GraphNode(
          id: 'c_state',
          type: 'Comment',
          config: const {
            'text': 'State — one signal per field',
            'width': 240,
            'height': 400,
          },
        ),
        GraphNode(
          id: 'c_summary',
          type: 'Comment',
          config: const {
            'text': 'Is the form valid?',
            'width': 400,
            'height': 280,
          },
        ),
      ],
      edges: [
        for (final field in _fields) ...field.edges(),
        Edge(
          PinRef(_fields[0].okNode, 'out'),
          const PinRef('n_creds_ok', 'a'),
        ),
        Edge(
          PinRef(_fields[1].okNode, 'out'),
          const PinRef('n_bend_a', 'in'),
        ),
        const Edge(PinRef('n_bend_a', 'out'), PinRef('n_creds_ok', 'b')),
        const Edge(PinRef('n_creds_ok', 'out'), PinRef('n_fields_ok', 'a')),
        Edge(
          PinRef(_fields[2].okNode, 'out'),
          const PinRef('n_bend_b', 'in'),
        ),
        const Edge(PinRef('n_bend_b', 'out'), PinRef('n_fields_ok', 'b')),
        const Edge(PinRef('n_fields_ok', 'out'), PinRef('n_form_ok', 'a')),
        const Edge(PinRef('n_accepted', 'value'), PinRef('n_form_ok', 'b')),
        const Edge(PinRef('n_form_ok', 'out'), PinRef('n_status', 'condition')),
        const Edge(PinRef('n_ready', 'value'), PinRef('n_status', 'ifTrue')),
        const Edge(
          PinRef('n_incomplete', 'value'),
          PinRef('n_status', 'ifFalse'),
        ),
        const Edge(PinRef('ev_email', 'fire'), PinRef('a_email', 'exec')),
        const Edge(PinRef('ev_email', 'payload'), PinRef('a_email', 'value')),
        const Edge(PinRef('ev_pass', 'fire'), PinRef('a_pass', 'exec')),
        const Edge(PinRef('ev_pass', 'payload'), PinRef('a_pass', 'value')),
        const Edge(PinRef('ev_again', 'fire'), PinRef('a_again', 'exec')),
        const Edge(PinRef('ev_again', 'payload'), PinRef('a_again', 'value')),
        const Edge(PinRef('ev_accept', 'fire'), PinRef('a_accept', 'exec')),
        const Edge(PinRef('ev_submit', 'fire'), PinRef('a_submit', 'exec')),
        const Edge(PinRef('n_status', 'out'), PinRef('a_submit', 'message')),
      ],
    );

Map<String, CanvasPos> _layout() {
  // Laid out for the *folded* view, because that is the one R14 is about:
  // state on the left, three folded rule groups in the middle, the summary on
  // the right, events along the bottom. The members sit far to the right,
  // where they are only in the way once you have opened a group on purpose.
  final layout = <String, CanvasPos>{
    'c_state': const CanvasPos(32, 32),
    'n_email': const CanvasPos(48, 80),
    'n_password': const CanvasPos(48, 160),
    'n_confirm': const CanvasPos(48, 240),
    'n_accepted': const CanvasPos(48, 320),
    'c_summary': const CanvasPos(624, 32),
    'n_creds_ok': const CanvasPos(640, 80),
    'n_bend_a': const CanvasPos(592, 160),
    'n_fields_ok': const CanvasPos(640, 160),
    'n_bend_b': const CanvasPos(592, 224),
    'n_form_ok': const CanvasPos(640, 240),
    'n_ready': const CanvasPos(848, 80),
    'n_incomplete': const CanvasPos(848, 160),
    'n_status': const CanvasPos(848, 240),
    'ev_email': const CanvasPos(48, 512),
    'a_email': const CanvasPos(272, 512),
    'ev_pass': const CanvasPos(48, 608),
    'a_pass': const CanvasPos(272, 608),
    'ev_again': const CanvasPos(48, 704),
    'a_again': const CanvasPos(272, 704),
    'ev_accept': const CanvasPos(480, 512),
    'a_accept': const CanvasPos(704, 512),
    'ev_submit': const CanvasPos(480, 608),
    'a_submit': const CanvasPos(704, 608),
  };

  var foldY = 80.0;
  var membersY = 80.0;
  for (final field in _fields) {
    layout['g_${field.prefix}'] = CanvasPos(368, foldY);
    layout.addAll(field.layout(1264, membersY));
    foldY += 144;
    membersY += 384;
  }
  return layout;
}
