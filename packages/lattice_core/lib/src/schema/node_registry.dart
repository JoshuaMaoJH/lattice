import '../model/graph.dart';
import '../model/data_model.dart';
import '../types/lattice_type.dart';
import 'node_schema.dart';
import 'pin_schema.dart';

const _dyn = PrimitiveType.dynamic_;
const _bool = PrimitiveType.bool_;
const _int = PrimitiveType.int_;
const _string = PrimitiveType.string;

PinSchema _in(String name, LatticeType type,
        {bool req = true, bool variadic = false}) =>
    PinSchema(name: name, type: type, required: req, variadic: variadic);

PinSchema _out(String name, LatticeType type) =>
    PinSchema(name: name, type: type);

/// Every action shares the same event plumbing: one `exec` in, one `next` out,
/// so a chain of actions reads top-to-bottom (§7.2).
const PinSchema _exec = PinSchema.event('exec');
const PinSchema _next = PinSchema.event('next', required: false);

/// The built-in node library (§7.2).
class NodeRegistry {
  NodeRegistry._();

  static final Map<String, NodeSchema> _byType = {
    for (final s in _schemas) s.type: s,
  };

  static NodeSchema? lookup(String type) => _byType[type];

  static bool isKnown(String type) => _byType.containsKey(type);

  static List<NodeSchema> get all => List.unmodifiable(_schemas);

  static Iterable<NodeSchema> byCategory(NodeCategory category) =>
      _schemas.where((s) => s.category == category);

  /// Registers a node contributed by a plugin library (R20). Built-ins go
  /// through this same path, so nothing about them is special-cased.
  static void register(NodeSchema schema) => _byType[schema.type] = schema;

  /// Binary operator nodes over one configured numeric type.
  static NodeSchema _arith(String type, String summary) => NodeSchema(
        type: type,
        category: NodeCategory.compute,
        summary: summary,
        configKeys: const ['dartType'],
        inputsFor: (node, ctx) {
          final t = ctx.resolve(node.get<String>('dartType'), fallback: _int);
          return [_in('a', t), _in('b', t)];
        },
        outputsFor: (node, ctx) => [
          _out(
              'out', ctx.resolve(node.get<String>('dartType'), fallback: _int)),
        ],
      );

  /// Comparison nodes: two values of the configured type in, a bool out.
  static NodeSchema _compare(String type, String summary) => NodeSchema(
        type: type,
        category: NodeCategory.compute,
        summary: summary,
        configKeys: const ['dartType'],
        inputsFor: (node, ctx) {
          final t = ctx.resolve(node.get<String>('dartType'), fallback: _int);
          return [_in('a', t), _in('b', t)];
        },
        outputsFor: (_, __) => [_out('out', _bool)],
      );

  static final List<NodeSchema> _schemas = [
    // ---- state -------------------------------------------------------------
    NodeSchema(
      type: 'Signal',
      category: NodeCategory.state,
      summary: 'The only mutable state source. Reads are reactive.',
      configKeys: const ['dartType', 'init', 'name'],
      inputsFor: (_, __) => const [],
      outputsFor: (node, ctx) => [_out('value', ctx.signalType(node.id))],
    ),
    NodeSchema(
      type: 'Const',
      category: NodeCategory.compute,
      summary: 'A literal value.',
      configKeys: const ['dartType', 'value'],
      inputsFor: (_, __) => const [],
      outputsFor: (node, ctx) => [
        _out('value',
            ctx.resolve(node.get<String>('dartType'), fallback: _string)),
      ],
    ),

    // ---- compute -----------------------------------------------------------
    NodeSchema(
      type: 'Format',
      category: NodeCategory.compute,
      summary: 'Interpolates arguments into a template, e.g. "Count: {0}".',
      configKeys: const ['template'],
      inputsFor: (_, __) => [_in('args', _dyn, variadic: true, req: false)],
      outputsFor: (_, __) => [_out('out', _string)],
    ),
    NodeSchema(
      type: 'Computed',
      category: NodeCategory.compute,
      summary: 'A pure Dart expression over named inputs.',
      configKeys: const ['dartType', 'expr', 'inputs', 'imports'],
      inputsFor: (node, ctx) {
        final declared = node.get<Map<String, Object?>>('inputs') ?? const {};
        return [
          for (final entry in declared.entries)
            _in(entry.key, ctx.resolve(entry.value as String?)),
        ];
      },
      outputsFor: (node, ctx) =>
          [_out('out', ctx.resolve(node.get<String>('dartType')))],
    ),
    _arith('Add', 'a + b'),
    _arith('Subtract', 'a - b'),
    _arith('Multiply', 'a * b'),
    // Dart's `/` yields a double even for two ints, so this node's output
    // type is not the configured operand type.
    NodeSchema(
      type: 'Divide',
      category: NodeCategory.compute,
      summary: 'a / b (always a double, as in Dart)',
      configKeys: const ['dartType'],
      inputsFor: (node, ctx) {
        final t = ctx.resolve(node.get<String>('dartType'), fallback: _int);
        return [_in('a', t), _in('b', t)];
      },
      outputsFor: (_, __) => [_out('out', PrimitiveType.double_)],
    ),
    NodeSchema(
      type: 'IntegerDivide',
      category: NodeCategory.compute,
      summary: 'a ~/ b',
      configKeys: const [],
      inputsFor: (_, __) => [_in('a', _int), _in('b', _int)],
      outputsFor: (_, __) => [_out('out', _int)],
    ),
    _arith('Modulo', 'a % b'),
    _compare('Equals', 'a == b'),
    _compare('NotEquals', 'a != b'),
    _compare('GreaterThan', 'a > b'),
    _compare('LessThan', 'a < b'),
    _compare('GreaterOrEqual', 'a >= b'),
    _compare('LessOrEqual', 'a <= b'),
    NodeSchema.fixed(
      type: 'And',
      category: NodeCategory.compute,
      summary: 'a && b',
      inputs: [
        PinSchema(name: 'a', type: _bool, required: true),
        PinSchema(name: 'b', type: _bool, required: true)
      ],
      outputs: [PinSchema(name: 'out', type: _bool)],
    ),
    NodeSchema.fixed(
      type: 'Or',
      category: NodeCategory.compute,
      summary: 'a || b',
      inputs: [
        PinSchema(name: 'a', type: _bool, required: true),
        PinSchema(name: 'b', type: _bool, required: true)
      ],
      outputs: [PinSchema(name: 'out', type: _bool)],
    ),
    NodeSchema.fixed(
      type: 'Not',
      category: NodeCategory.compute,
      summary: '!a',
      inputs: [PinSchema(name: 'a', type: _bool, required: true)],
      outputs: [PinSchema(name: 'out', type: _bool)],
    ),
    NodeSchema.fixed(
      type: 'Concat',
      category: NodeCategory.compute,
      summary: 'a + b, for strings',
      inputs: [
        PinSchema(name: 'a', type: _string, required: true),
        PinSchema(name: 'b', type: _string, required: true)
      ],
      outputs: [PinSchema(name: 'out', type: _string)],
    ),
    NodeSchema.fixed(
      type: 'ToString',
      category: NodeCategory.compute,
      summary: 'value.toString()',
      inputs: [PinSchema(name: 'value', type: _dyn, required: true)],
      outputs: [PinSchema(name: 'out', type: _string)],
    ),
    NodeSchema(
      type: 'Conditional',
      category: NodeCategory.compute,
      summary: 'condition ? ifTrue : ifFalse',
      configKeys: const ['dartType'],
      inputsFor: (node, ctx) {
        final t = ctx.resolve(node.get<String>('dartType'), fallback: _string);
        return [_in('condition', _bool), _in('ifTrue', t), _in('ifFalse', t)];
      },
      outputsFor: (node, ctx) => [
        _out('out',
            ctx.resolve(node.get<String>('dartType'), fallback: _string)),
      ],
    ),
    NodeSchema(
      type: 'ListLength',
      category: NodeCategory.compute,
      summary: 'list.length',
      configKeys: const ['elementType'],
      inputsFor: (node, ctx) => [
        _in('list', ListType(ctx.resolve(node.get<String>('elementType')))),
      ],
      outputsFor: (_, __) => [_out('out', _int)],
    ),
    NodeSchema(
      type: 'ListIsEmpty',
      category: NodeCategory.compute,
      summary: 'list.isEmpty',
      configKeys: const ['elementType'],
      inputsFor: (node, ctx) => [
        _in('list', ListType(ctx.resolve(node.get<String>('elementType')))),
      ],
      outputsFor: (_, __) => [_out('out', _bool)],
    ),
    NodeSchema(
      type: 'ListAppend',
      category: NodeCategory.compute,
      summary: 'A new list with one item appended.',
      configKeys: const ['elementType'],
      inputsFor: (node, ctx) {
        final e = ctx.resolve(node.get<String>('elementType'));
        return [_in('list', ListType(e)), _in('item', e)];
      },
      outputsFor: (node, ctx) => [
        _out('out', ListType(ctx.resolve(node.get<String>('elementType')))),
      ],
    ),
    NodeSchema(
      type: 'ListRemoveAt',
      category: NodeCategory.compute,
      summary: 'A new list with one index removed.',
      configKeys: const ['elementType'],
      inputsFor: (node, ctx) => [
        _in('list', ListType(ctx.resolve(node.get<String>('elementType')))),
        _in('index', _int),
      ],
      outputsFor: (node, ctx) => [
        _out('out', ListType(ctx.resolve(node.get<String>('elementType')))),
      ],
    ),

    NodeSchema(
      type: 'ListSetAt',
      category: NodeCategory.compute,
      summary: 'A new list with one index replaced.',
      configKeys: const ['elementType'],
      inputsFor: (node, ctx) {
        final e = ctx.resolve(node.get<String>('elementType'));
        return [_in('list', ListType(e)), _in('index', _int), _in('item', e)];
      },
      outputsFor: (node, ctx) => [
        _out('out', ListType(ctx.resolve(node.get<String>('elementType')))),
      ],
    ),
    NodeSchema(
      type: 'MapGet',
      category: NodeCategory.compute,
      summary: 'map[key]. The workhorse for per-item UI state keyed by id.',
      configKeys: const ['keyType', 'valueType'],
      inputsFor: (node, ctx) {
        final k = ctx.resolve(node.get<String>('keyType'), fallback: _string);
        final v = ctx.resolve(node.get<String>('valueType'));
        return [_in('map', MapType(k, v)), _in('key', k)];
      },
      outputsFor: (node, ctx) => [
        _out('value', NullableType(ctx.resolve(node.get<String>('valueType')))),
      ],
    ),
    NodeSchema(
      type: 'MapPut',
      category: NodeCategory.compute,
      summary: 'A new map with one key set.',
      configKeys: const ['keyType', 'valueType'],
      inputsFor: (node, ctx) {
        final k = ctx.resolve(node.get<String>('keyType'), fallback: _string);
        final v = ctx.resolve(node.get<String>('valueType'));
        return [_in('map', MapType(k, v)), _in('key', k), _in('value', v)];
      },
      outputsFor: (node, ctx) {
        final k = ctx.resolve(node.get<String>('keyType'), fallback: _string);
        final v = ctx.resolve(node.get<String>('valueType'));
        return [_out('out', MapType(k, v))];
      },
    ),

    // ---- control -----------------------------------------------------------
    NodeSchema(
      type: 'PageParam',
      category: NodeCategory.ui,
      summary: 'A parameter of the page or prefab this graph belongs to '
          '(R12, R9).',
      configKeys: const ['name'],
      inputsFor: (_, __) => const [],
      outputsFor: (node, ctx) {
        final name = node.get<String>('name');
        final parameter = name == null ? null : ctx.unit?.parameter(name);
        return [_out('value', parameter?.type ?? PrimitiveType.dynamic_)];
      },
    ),
    NodeSchema(
      type: 'ForEachItem',
      category: NodeCategory.control,
      summary: 'The current item and index inside a ForEach template. '
          'Readable only by widgets inside that template.',
      configKeys: const ['forEach'],
      inputsFor: (_, __) => const [],
      outputsFor: (node, ctx) => [
        _out('item', ctx.forEachElementType(node.get<String>('forEach'))),
        _out('index', _int),
      ],
    ),

    // ---- events ------------------------------------------------------------
    NodeSchema(
      type: 'Event',
      category: NodeCategory.event,
      summary: 'Fires when a widget callback runs.',
      configKeys: const ['widget', 'event'],
      inputsFor: (_, __) => const [],
      outputsFor: (node, ctx) {
        final payload = ctx.eventPayload(
          node.get<String>('widget'),
          node.get<String>('event'),
        );
        return [
          PinSchema(
            name: 'fire',
            type: payload == PrimitiveType.void_
                ? const EventType()
                : EventType(payload),
            kind: PinKind.event,
          ),
          if (payload != PrimitiveType.void_) _out('payload', payload),
        ];
      },
    ),

    // ---- actions -----------------------------------------------------------
    NodeSchema(
      type: 'SetSignal',
      category: NodeCategory.action,
      summary: 'Writes a value into a Signal.',
      configKeys: const ['signal'],
      inputsFor: (node, ctx) => [
        _exec,
        _in('value', ctx.signalType(node.get<String>('signal'))),
      ],
      outputsFor: (_, __) => const [_next],
    ),
    NodeSchema(
      type: 'UpdateSignal',
      category: NodeCategory.action,
      summary: 'Applies a pure function to a Signal\'s current value.',
      configKeys: const ['signal', 'fn'],
      inputsFor: (_, __) => const [_exec],
      outputsFor: (_, __) => const [_next],
    ),
    NodeSchema(
      type: 'ToggleSignal',
      category: NodeCategory.action,
      summary: 'Inverts a bool Signal.',
      configKeys: const ['signal'],
      inputsFor: (_, __) => const [_exec],
      outputsFor: (_, __) => const [_next],
    ),
    NodeSchema(
      type: 'Navigate',
      category: NodeCategory.action,
      summary: 'Pushes or replaces a route. One input pin appears per '
          'parameter the target page declares.',
      configKeys: const ['route', 'replace'],
      inputsFor: (node, ctx) {
        final target = ctx.pageForRoute(node.get<String>('route'));
        return [
          _exec,
          for (final parameter in target?.parameters ?? const <FieldDef>[])
            _in(
              parameter.name,
              parameter.type,
              req: parameter.defaultValue == null &&
                  parameter.type is! NullableType,
            ),
        ];
      },
      outputsFor: (_, __) => const [_next],
    ),
    NodeSchema(
      type: 'HttpRequest',
      category: NodeCategory.action,
      summary: 'Fetches a URL and decodes the body into a Signal. '
          'The handler it sits in becomes async (R13).',
      configKeys: const [
        'method',
        'signal',
        'loadingSignal',
        'errorSignal',
        'decode',
      ],
      inputsFor: (node, ctx) => [
        _exec,
        _in('url', _string),
        if ((node.get<String>('method') ?? 'GET').toUpperCase() != 'GET')
          _in('body', _string, req: false),
      ],
      outputsFor: (_, __) => const [_next],
    ),
    NodeSchema.fixed(
      type: 'ShowSnackBar',
      category: NodeCategory.action,
      summary: 'Shows a snack bar on the current Scaffold.',
      inputs: [
        _exec,
        PinSchema(name: 'message', type: _string, required: true)
      ],
      outputs: [_next],
    ),
    NodeSchema.fixed(
      type: 'Print',
      category: NodeCategory.action,
      summary: 'debugPrint, for tracing a graph.',
      inputs: [_exec, PinSchema(name: 'message', type: _dyn, required: true)],
      outputs: [_next],
    ),

    // ---- escape hatch ------------------------------------------------------
    NodeSchema(
      type: 'DartCode',
      category: NodeCategory.escape,
      summary: 'A hand-written pure function body (§7.8). '
          '"imports" reaches your own files under lib/custom/, which codegen '
          'never overwrites.',
      configKeys: const ['inputs', 'dartType', 'body', 'name', 'imports'],
      inputsFor: (node, ctx) {
        final declared = node.get<Map<String, Object?>>('inputs') ?? const {};
        return [
          for (final entry in declared.entries)
            _in(entry.key, ctx.resolve(entry.value as String?)),
        ];
      },
      outputsFor: (node, ctx) =>
          [_out('out', ctx.resolve(node.get<String>('dartType')))],
    ),

    // ---- organisation ------------------------------------------------------
    NodeSchema.fixed(
      type: 'Subgraph',
      category: NodeCategory.organize,
      summary: 'Folds a group of nodes into one box (§7.2, R14). '
          'Purely organisational: the members stay in the graph, so nothing '
          'about the generated code changes.',
      configKeys: const ['name', 'members', 'collapsed'],
    ),
    NodeSchema.fixed(
      type: 'Comment',
      category: NodeCategory.organize,
      summary: 'A note on the canvas. Ignored by codegen.',
      configKeys: const ['text', 'width', 'height'],
    ),
    NodeSchema(
      type: 'Reroute',
      category: NodeCategory.organize,
      summary: 'A pass-through, for tidying edges.',
      configKeys: const ['dartType'],
      inputsFor: (node, ctx) =>
          [_in('in', ctx.resolve(node.get<String>('dartType')))],
      outputsFor: (node, ctx) =>
          [_out('out', ctx.resolve(node.get<String>('dartType')))],
    ),
  ];

  /// Convenience for the validator: the schema of [node], or null if the type
  /// is not registered.
  static NodeSchema? forNode(GraphNode node) => lookup(node.type);
}
