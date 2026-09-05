// Authors examples/quote — the M3 example.
//
// One server function, called from a page: the smallest thing that shows a
// graph crossing a network boundary and coming back typed (§7.7).
//
//   dart run tool/make_quote_example.dart
import 'package:lattice_core/io.dart';
import 'package:lattice_core/lattice_core.dart';

Future<void> main() async {
  final project = Project(
    id: 'quote',
    config: const ProjectConfig(
      appName: 'Quote',
      packageName: 'quote_app',
      bundleId: 'com.example.quote_app',
      description: 'A Lattice example: one graph, a client and a server.',
      targets: [BuildTarget.linux, BuildTarget.web],
    ),
    models: [
      DataModelDef.fromJson(const {
        'name': 'Quote',
        'fields': {
          'sku': 'String',
          'quantity': 'int',
          'unitPrice': 'double',
          'discount': 'double',
          'total': 'double',
        },
      }, 'quote'),
    ],
    serverFunctions: [_priceFor()],
    pages: [_home()],
  );

  await ProjectIo.save(project, 'examples/quote');
  final result = const Validator().validate(project);
  if (!result.isValid) {
    throw StateError('the fixture does not validate:\n$result');
  }
  print('Wrote examples/quote (${result.diagnostics.length} diagnostics)');
}

/// The pricing rules, which is exactly the sort of thing that should not be
/// shipped to a client: it is the business, not the interface.
ServerFunction _priceFor() => ServerFunction(
      id: 'fn_price',
      name: 'priceFor',
      returns: const ModelType('Quote'),
      parameters: [
        const FieldDef(name: 'sku', type: PrimitiveType.string),
        const FieldDef(name: 'quantity', type: PrimitiveType.int_),
      ],
      graph: Graph(
        nodes: [
          GraphNode(
            id: 'p_sku',
            type: 'PageParam',
            config: const {'name': 'sku'},
          ),
          GraphNode(
            id: 'p_qty',
            type: 'PageParam',
            config: const {'name': 'quantity'},
          ),
          // The price list is a table, so it lives in hand-written Dart —
          // on the server, where a price list belongs (§7.8).
          GraphNode(
            id: 'n_unit',
            type: 'DartCode',
            config: const {
              'name': 'unitPrice',
              'dartType': 'double',
              'inputs': {'sku': 'String'},
              'imports': ['custom/pricing.dart'],
              'body': 'return unitPriceFor(sku);',
            },
          ),
          GraphNode(
            id: 'n_discount',
            type: 'DartCode',
            config: const {
              'name': 'discountRate',
              'dartType': 'double',
              'inputs': {'quantity': 'int'},
              'imports': ['custom/pricing.dart'],
              'body': 'return discountFor(quantity);',
            },
          ),
          GraphNode(
            id: 'n_quote',
            type: 'Computed',
            config: const {
              'name': 'buildQuote',
              'dartType': 'Quote',
              'inputs': {
                'sku': 'String',
                'quantity': 'int',
                'unitPrice': 'double',
                'discount': 'double',
              },
              'expr': 'Quote(sku: sku, quantity: quantity, '
                  'unitPrice: unitPrice, discount: discount, '
                  'total: unitPrice * quantity * (1 - discount))',
            },
          ),
          GraphNode(id: 'r_out', type: 'Return'),
        ],
        edges: const [
          Edge(PinRef('p_sku', 'value'), PinRef('n_unit', 'sku')),
          Edge(PinRef('p_sku', 'value'), PinRef('n_quote', 'sku')),
          Edge(PinRef('p_qty', 'value'), PinRef('n_discount', 'quantity')),
          Edge(PinRef('p_qty', 'value'), PinRef('n_quote', 'quantity')),
          Edge(PinRef('n_unit', 'out'), PinRef('n_quote', 'unitPrice')),
          Edge(PinRef('n_discount', 'out'), PinRef('n_quote', 'discount')),
          Edge(PinRef('n_quote', 'out'), PinRef('r_out', 'value')),
        ],
      ),
      layout: const {
        'p_sku': CanvasPos(64, 64),
        'p_qty': CanvasPos(64, 176),
        'n_unit': CanvasPos(304, 64),
        'n_discount': CanvasPos(304, 176),
        'n_quote': CanvasPos(560, 96),
        'r_out': CanvasPos(816, 128),
      },
    );

Page _home() => Page(
      id: 'page_home',
      name: 'Quote',
      route: '/',
      isHome: true,
      hierarchy: _hierarchy(),
      graph: _graph(),
      layout: const {
        'n_sku': CanvasPos(64, 64),
        'n_qty': CanvasPos(64, 144),
        'n_quote': CanvasPos(64, 224),
        'n_loading': CanvasPos(64, 304),
        'n_error': CanvasPos(64, 384),
        'ev_fetch': CanvasPos(64, 560),
        'a_fetch': CanvasPos(320, 560),
      },
    );

WidgetNode _text(String id, String node, {Object? style}) => WidgetNode(
      id: id,
      type: 'Text',
      props: {
        'data': BindProp(PinRef(node, 'out')),
        if (style != null) 'style': LiteralProp(style),
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
                  props: {'data': const LiteralProp('Quote')},
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
                WidgetNode(
                  id: 'w_sku',
                  type: 'TextField',
                  props: {
                    'labelText': const LiteralProp('SKU'),
                    'hintText': const LiteralProp('PRO-1, LITE-2, BASIC-3'),
                    'text': const BindProp(PinRef('n_sku', 'value')),
                    'onChanged': const EventProp('ev_sku'),
                  },
                ),
                WidgetNode(
                  id: 'w_gap1',
                  type: 'SizedBox',
                  props: {'height': const LiteralProp(12)},
                ),
                WidgetNode(
                  id: 'w_qty',
                  type: 'TextField',
                  props: {
                    'labelText': const LiteralProp('Quantity'),
                    'keyboardType': const LiteralProp('number'),
                    'onChanged': const EventProp('ev_qty'),
                  },
                ),
                WidgetNode(
                  id: 'w_gap2',
                  type: 'SizedBox',
                  props: {'height': const LiteralProp(20)},
                ),
                WidgetNode(
                  id: 'w_go',
                  type: 'ElevatedButton',
                  props: {'onPressed': const EventProp('ev_fetch')},
                  children: [
                    WidgetNode(
                      id: 'w_go_label',
                      type: 'Text',
                      props: {'data': const LiteralProp('Get a price')},
                    ),
                  ],
                ),
                WidgetNode(
                  id: 'w_gap3',
                  type: 'SizedBox',
                  props: {'height': const LiteralProp(24)},
                ),
                WidgetNode(
                  id: 'w_if_loading',
                  type: 'If',
                  props: {
                    'condition': const BindProp(PinRef('n_loading', 'value')),
                  },
                  children: [
                    WidgetNode(
                      id: 'w_spinner',
                      type: 'CircularProgressIndicator',
                    ),
                  ],
                ),
                WidgetNode(
                  id: 'w_if_error',
                  type: 'If',
                  props: {
                    'condition': const BindProp(PinRef('n_hasError', 'out')),
                  },
                  children: [
                    _text(
                      'w_error',
                      'n_errorText',
                      style: const {'color': '#B3261E'},
                    ),
                  ],
                ),
                WidgetNode(
                  id: 'w_if_quote',
                  type: 'If',
                  props: {
                    'condition': const BindProp(PinRef('n_hasQuote', 'out')),
                  },
                  children: [
                    WidgetNode(
                      id: 'w_result',
                      type: 'Column',
                      props: {
                        'crossAxisAlignment': const LiteralProp('start'),
                        'mainAxisSize': const LiteralProp('min'),
                      },
                      children: [
                        _text(
                          'w_total',
                          'n_totalText',
                          style: const {'fontSize': 32, 'fontWeight': 'bold'},
                        ),
                        _text('w_break', 'n_breakdown'),
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
          id: 'n_sku',
          type: 'Signal',
          config: const {'dartType': 'String', 'init': 'PRO-1', 'name': 'sku'},
        ),
        GraphNode(
          id: 'n_qty',
          type: 'Signal',
          config: const {'dartType': 'int', 'init': 12, 'name': 'quantity'},
        ),
        GraphNode(
          id: 'n_quote',
          type: 'Signal',
          config: const {'dartType': 'Quote?', 'name': 'quote'},
        ),
        GraphNode(
          id: 'n_loading',
          type: 'Signal',
          config: const {
            'dartType': 'bool',
            'init': false,
            'name': 'loading',
          },
        ),
        GraphNode(
          id: 'n_error',
          type: 'Signal',
          config: const {'dartType': 'String?', 'name': 'error'},
        ),
        GraphNode(
          id: 'n_parseQty',
          type: 'Computed',
          config: const {
            'name': 'parseQuantity',
            'dartType': 'int',
            'inputs': {'text': 'String'},
            'expr': 'int.tryParse(text.trim()) ?? 0',
          },
        ),
        GraphNode(
          id: 'n_hasError',
          type: 'Computed',
          config: const {
            'name': 'hasError',
            'dartType': 'bool',
            'inputs': {'message': 'String?'},
            'expr': 'message != null',
          },
        ),
        GraphNode(
          id: 'n_errorText',
          type: 'Computed',
          config: const {
            'name': 'errorText',
            'dartType': 'String',
            'inputs': {'message': 'String?'},
            'expr': "message ?? ''",
          },
        ),
        GraphNode(
          id: 'n_hasQuote',
          type: 'Computed',
          config: const {
            'name': 'hasQuote',
            'dartType': 'bool',
            'inputs': {'quote': 'Quote?'},
            'expr': 'quote != null',
          },
        ),
        GraphNode(
          id: 'n_totalText',
          type: 'Computed',
          config: const {
            'name': 'totalText',
            'dartType': 'String',
            'inputs': {'quote': 'Quote?'},
            'expr': r"quote == null ? '' "
                r": '\$${quote.total.toStringAsFixed(2)}'",
          },
        ),
        GraphNode(
          id: 'n_breakdown',
          type: 'Computed',
          config: const {
            'name': 'breakdown',
            'dartType': 'String',
            'inputs': {'quote': 'Quote?'},
            'expr': r"quote == null ? '' "
                r": '${quote.quantity} x \$${quote.unitPrice.toStringAsFixed(2)}"
                r"  ·  ${(quote.discount * 100).round()}% off'",
          },
        ),
        GraphNode(
          id: 'ev_sku',
          type: 'Event',
          config: const {'widget': 'w_sku', 'event': 'onChanged'},
        ),
        GraphNode(
          id: 'a_sku',
          type: 'SetSignal',
          config: const {'signal': 'n_sku'},
        ),
        GraphNode(
          id: 'ev_qty',
          type: 'Event',
          config: const {'widget': 'w_qty', 'event': 'onChanged'},
        ),
        GraphNode(
          id: 'a_qty',
          type: 'SetSignal',
          config: const {'signal': 'n_qty'},
        ),
        GraphNode(
          id: 'ev_fetch',
          type: 'Event',
          config: const {'widget': 'w_go', 'event': 'onPressed'},
        ),
        GraphNode(
          id: 'a_fetch',
          type: 'CallServer',
          config: const {
            'function': 'priceFor',
            'signal': 'n_quote',
            'loadingSignal': 'n_loading',
            'errorSignal': 'n_error',
          },
        ),
      ],
      edges: const [
        Edge(PinRef('n_error', 'value'), PinRef('n_hasError', 'message')),
        Edge(PinRef('n_error', 'value'), PinRef('n_errorText', 'message')),
        Edge(PinRef('n_quote', 'value'), PinRef('n_hasQuote', 'quote')),
        Edge(PinRef('n_quote', 'value'), PinRef('n_totalText', 'quote')),
        Edge(PinRef('n_quote', 'value'), PinRef('n_breakdown', 'quote')),
        Edge(PinRef('ev_sku', 'fire'), PinRef('a_sku', 'exec')),
        Edge(PinRef('ev_sku', 'payload'), PinRef('a_sku', 'value')),
        Edge(PinRef('ev_qty', 'fire'), PinRef('a_qty', 'exec')),
        Edge(PinRef('ev_qty', 'payload'), PinRef('n_parseQty', 'text')),
        Edge(PinRef('n_parseQty', 'out'), PinRef('a_qty', 'value')),
        Edge(PinRef('ev_fetch', 'fire'), PinRef('a_fetch', 'exec')),
        Edge(PinRef('n_sku', 'value'), PinRef('a_fetch', 'sku')),
        Edge(PinRef('n_qty', 'value'), PinRef('a_fetch', 'quantity')),
      ],
    );
