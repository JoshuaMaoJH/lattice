import 'dart:collection';

import 'package:code_builder/code_builder.dart';
import 'package:collection/collection.dart';
import 'package:lattice_core/lattice_core.dart';

import '../codegen_exception.dart';
import '../emit/emitted.dart';
import '../emit/literals.dart';
import '../emit/render.dart';
import '../naming.dart';
import 'page_ir.dart';

/// Step 2 of the pipeline (§7.5): turn a validated project into an IR where
/// every binding is already a Dart expression and every event chain is already
/// a statement list.
///
/// Two decisions are made here and nowhere else:
///
/// * **Hoisting** — a computation used in more than one place becomes a
///   `computed()` field instead of being inlined twice.
/// * **Reactive boundaries** — a widget is wrapped in `Watch` exactly when its
///   own arguments read a signal, which is what keeps the rest of the tree
///   `const` (§8).
class Lowering {
  const Lowering();

  ProjectIr lower(Project project) => ProjectIr(
        project: project,
        pages: [
          for (final unit in project.units) _PageLowering(project, unit).run(),
        ],
      );
}

class _PageLowering {
  _PageLowering(this.project, this.unit)
      : graph = unit.graph,
        literals = LiteralEmitter(models: project.models) {
    ctx = NodeContext(graph: graph, unit: unit, project: project);
  }

  final Project project;
  final WidgetUnit unit;
  final Graph graph;
  final LiteralEmitter literals;
  late final NodeContext ctx;

  final Namer namer = Namer(const ['context', 'widget', 'key', 'build']);
  late final ScopeMap scopes = ScopeMap.of(unit);
  late final WidgetLookup widgets = WidgetLookup(project);
  final SplayTreeSet<String> usedPrefabs = SplayTreeSet<String>();

  /// ForEach widget id -> the loop variables its template runs under.
  final Map<String, _ScopeVars> scopeVars = {};

  /// Event node id -> the loop variables its handler has to be handed.
  final Map<String, List<_ScopeArgument>> handlerScopeArgs = {};
  final Map<String, String> signalNames = {};
  final List<SignalIr> signals = [];
  final Map<PinRef, HoistedIr> hoists = {};
  final Map<String, HelperIr> helpers = {};
  final List<HandlerIr> handlers = [];
  final Map<String, String> handlerNames = {};
  final Map<String, Set<String>> _signalCache = {};
  final List<ControllerIr> controllers = [];
  final SplayTreeSet<String> extraImports = SplayTreeSet<String>();

  /// Whether this page compiles to a `StatefulWidget`.
  ///
  /// Decided structurally before anything is lowered, because `PageParam`
  /// reads a constructor field — reachable as `widget.x` from a State, and as
  /// plain `x` from a StatelessWidget.
  late final bool isStateful = unit.isStateful;

  bool _usesHttp = false;
  bool _usesJson = false;

  /// Set while lowering one handler; an awaited action flips it.
  bool _chainIsAsync = false;

  /// The parameter name for the payload of the handler currently being
  /// lowered; `Event.payload` resolves to it.
  String? _payloadName;

  bool _usesModels = false;

  PageIr run() {
    _collectSignals();
    _collectScopeVars();
    _collectHelpers();
    _planHoists();
    _lowerHandlers();

    final body = _lowerWidget(unit.hierarchy, insideBoundary: false);

    return PageIr(
      unit: unit,
      className: unit.className,
      fileName: unit.fileName,
      signals: signals,
      hoisted: hoists.values.toList(),
      helpers: helpers.values.toList(),
      handlers: handlers,
      controllers: controllers,
      body: body,
      usesModels: _usesModels,
      extraImports: extraImports.toList(),
      usesHttp: _usesHttp,
      usesJson: _usesJson,
      usedPrefabs: usedPrefabs.toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Collection passes
  // ---------------------------------------------------------------------------

  void _collectSignals() {
    for (final node in graph.ofType('Signal')) {
      final type = ctx.signalType(node.id);
      final name = namer.take(
        Naming.camel(node.get<String>('name') ?? node.id),
      );
      signalNames[node.id] = name;
      _noteModelUse(type);

      final raw = node.config['init'];
      final init = raw == null && type is! NullableType
          ? _zeroValue(type, node)
          : literals.emit(type, raw,
              where: 'Signal ${node.id} init',
              pageId: unit.id,
              nodeId: node.id);

      signals.add(
        SignalIr(nodeId: node.id, name: name, type: type, init: init),
      );
    }
  }

  /// A sensible initial value when a `Signal` declares no `init`, so an empty
  /// list or a zero counter does not have to be spelled out.
  Emitted _zeroValue(LatticeType type, GraphNode node) => switch (type) {
        PrimitiveType(kind: PrimitiveKind.int$) =>
          Emitted.constant(literalNum(0)),
        PrimitiveType(kind: PrimitiveKind.double$ || PrimitiveKind.num$) =>
          Emitted.constant(literalNum(0)),
        PrimitiveType(kind: PrimitiveKind.bool$) =>
          Emitted.constant(literalBool(false)),
        PrimitiveType(kind: PrimitiveKind.string$) =>
          Emitted.constant(literalString('')),
        ListType() => Emitted(
            (asConst) =>
                asConst ? literalConstList(const []) : literalList(const []),
            isConst: true,
          ),
        MapType() => Emitted(
            (asConst) =>
                asConst ? literalConstMap(const {}) : literalMap(const {}),
            isConst: true,
          ),
        _ => throw CodegenException(
            'Signal "${node.id}" of type ${type.dartName} needs an "init" value.',
            pageId: unit.id,
            nodeId: node.id,
          ),
      };

  /// Names the loop variables for every `ForEach` template.
  ///
  /// Done before anything else is lowered because handlers, which are emitted
  /// as methods rather than inline closures, need to know what to call their
  /// parameters (ADR-009).
  void _collectScopeVars() {
    for (final widget in unit.hierarchy.descendantsAndSelf) {
      if (widget.type != 'ForEach') continue;
      scopeVars[widget.id] = _ScopeVars(
        item: namer.take('item'),
        index: namer.take('index'),
        element: ctx.forEachElementType(widget.id),
      );
      _noteModelUse(ctx.forEachElementType(widget.id));
    }
  }

  /// `Computed` and `Dart Code` nodes become private functions, so the user's
  /// own Dart is embedded once and called, never pasted at each use site.
  void _collectHelpers() {
    for (final node in graph.nodes) {
      if (node.type != 'Computed' && node.type != 'DartCode') continue;
      final schema = NodeRegistry.forNode(node)!;
      final returnType = ctx.resolve(node.get<String>('dartType'));
      _noteModelUse(returnType);

      final parameters = <({String name, LatticeType type})>[];
      for (final pin in schema.inputs(node, ctx)) {
        _noteModelUse(pin.type);
        parameters.add((name: pin.name, type: pin.type));
      }

      final body = node.type == 'Computed'
          ? node.get<String>('expr')
          : node.get<String>('body');
      if (body == null || body.trim().isEmpty) {
        throw CodegenException(
          '${node.type} node "${node.id}" has no '
          '${node.type == 'Computed' ? 'expr' : 'body'}.',
          pageId: unit.id,
          nodeId: node.id,
        );
      }

      for (final entry in node.get<List<Object?>>('imports') ?? const []) {
        if (entry is String && entry.isNotEmpty) extraImports.add(entry);
      }

      final name = namer.take(
        '_${Naming.camel(node.get<String>('name') ?? node.id)}',
      );
      helpers[node.id] = HelperIr(
        nodeId: node.id,
        name: name,
        returnType: returnType,
        parameters: parameters,
        body: body.trim(),
        // A `Computed` holds an expression; a `Dart Code` node holds a body.
        isExpressionBody: node.type == 'Computed',
      );
    }
  }

  /// Counts how many places read each output pin. Two or more readers of a
  /// reactive computation earns a `computed()` field (§7.5 step 3).
  Map<PinRef, int> _referenceCounts() {
    final counts = <PinRef, int>{};
    void bump(PinRef ref) => counts[ref.base] = (counts[ref.base] ?? 0) + 1;

    for (final edge in graph.edges) {
      bump(edge.from);
    }
    for (final widget in unit.hierarchy.descendantsAndSelf) {
      for (final prop in widget.props.values) {
        if (prop is BindProp) bump(prop.source);
      }
    }
    return counts;
  }

  void _planHoists() {
    final counts = _referenceCounts();
    final candidates = <PinRef>[];

    for (final node in graph.nodes) {
      final schema = NodeRegistry.forNode(node);
      if (schema == null) continue;
      if (schema.category != NodeCategory.compute &&
          schema.category != NodeCategory.escape) {
        continue;
      }
      for (final pin in schema.outputs(node, ctx)) {
        if (pin.kind != PinKind.data) continue;
        final ref = PinRef(node.id, pin.name);
        if ((counts[ref] ?? 0) < 2) continue;
        // A constant used twice costs nothing to inline twice; only reactive
        // work is worth a field.
        if (_signalsFor(node.id).isEmpty) continue;
        // A value that depends on `item` is per-iteration and has no meaning
        // as a page-level field, so it stays inline (ADR-009).
        if (scopes.scopesOf(node.id).isNotEmpty) continue;
        candidates.add(ref);
      }
    }

    // Shallowest first, so a hoist's own dependencies already exist when its
    // body is lowered and can be referenced rather than re-inlined.
    candidates.sort((a, b) => _depth(a.nodeId).compareTo(_depth(b.nodeId)));

    for (final ref in candidates) {
      final node = graph.node(ref.nodeId)!;
      final schema = NodeRegistry.forNode(node)!;
      final type = schema.output(node, ctx, ref.pin)!.type;
      _noteModelUse(type);
      final body = _lowerPin(ref, skipHoist: ref);
      hoists[ref] = HoistedIr(
        pin: ref,
        name: namer.take(Naming.camel(node.get<String>('name') ?? node.id)),
        type: type,
        body: body,
        signalDeps: body.signalDeps,
      );
    }
  }

  /// Signals reachable backwards from [nodeId] through data edges.
  Set<String> _signalsFor(String nodeId) {
    final cached = _signalCache[nodeId];
    if (cached != null) return cached;
    _signalCache[nodeId] = const {}; // guards against a malformed cycle

    final node = graph.node(nodeId);
    if (node == null) return const {};

    final result = <String>{};
    if (node.type == 'Signal') {
      result.add(nodeId);
    } else {
      for (final edge in graph.edges) {
        if (edge.to.nodeId != nodeId) continue;
        result.addAll(_signalsFor(edge.from.nodeId));
      }
    }
    _signalCache[nodeId] = result;
    return result;
  }

  final Map<String, int> _depthCache = {};

  int _depth(String nodeId) {
    final cached = _depthCache[nodeId];
    if (cached != null) return cached;
    _depthCache[nodeId] = 0;
    var depth = 0;
    for (final edge in graph.edges) {
      if (edge.to.nodeId != nodeId) continue;
      depth = depth > _depth(edge.from.nodeId) + 1
          ? depth
          : _depth(edge.from.nodeId) + 1;
    }
    _depthCache[nodeId] = depth;
    return depth;
  }

  void _noteModelUse(LatticeType type) {
    switch (type) {
      case ModelType():
        _usesModels = true;
      case ListType(:final element):
        _noteModelUse(element);
      case NullableType(:final inner):
        _noteModelUse(inner);
      case FutureType(:final inner):
        _noteModelUse(inner);
      case MapType(:final key, :final value):
        _noteModelUse(key);
        _noteModelUse(value);
      default:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Expression lowering
  // ---------------------------------------------------------------------------

  Emitted _lowerPin(PinRef ref, {PinRef? skipHoist}) {
    final hoist = hoists[ref.base];
    if (hoist != null && ref.base != skipHoist) {
      return Emitted.reactive(
        refer(hoist.name).property('value'),
        hoist.signalDeps,
      );
    }

    final node = graph.node(ref.nodeId);
    if (node == null) {
      throw CodegenException('No node "${ref.nodeId}" for pin "$ref".',
          pageId: unit.id);
    }

    switch (node.type) {
      case 'Signal':
        final name = signalNames[node.id]!;
        return Emitted.reactive(refer(name).property('value'), {node.id});

      case 'Const':
        final type = ctx.resolve(node.get<String>('dartType'));
        _noteModelUse(type);
        return literals.emit(type, node.config['value'],
            where: 'Const ${node.id}', pageId: unit.id, nodeId: node.id);

      case 'Reroute':
        return _input(node, 'in');

      case 'PageParam':
        final name = node.get<String>('name');
        final parameter = name == null ? null : unit.parameter(name);
        if (parameter == null) {
          throw CodegenException(
            'PageParam "${node.id}" names no parameter of this page.',
            pageId: unit.id,
            nodeId: node.id,
          );
        }
        _noteModelUse(parameter.type);
        return Emitted.plain(
          isStateful
              ? refer('widget').property(parameter.name)
              : refer(parameter.name),
        );

      case 'ForEachItem':
        final owner = node.get<String>('forEach');
        final vars = owner == null ? null : scopeVars[owner];
        if (vars == null) {
          throw CodegenException(
            'ForEachItem "${node.id}" does not name a ForEach in this page.',
            pageId: unit.id,
            nodeId: node.id,
          );
        }
        return switch (ref.pin) {
          'item' => Emitted.plain(refer(vars.item)),
          'index' => Emitted.plain(refer(vars.index)),
          _ => throw CodegenException(
              'ForEachItem has no pin "${ref.pin}".',
              pageId: unit.id,
              nodeId: node.id,
            ),
        };

      case 'Format':
        return _format(node);

      case 'Add':
        return _binary(node, '+');
      case 'Subtract':
        return _binary(node, '-');
      case 'Multiply':
        return _binary(node, '*');
      case 'Divide':
        return _binary(node, '/');
      case 'IntegerDivide':
        return _binary(node, '~/');
      case 'Modulo':
        return _binary(node, '%');
      case 'Equals':
        return _binary(node, '==');
      case 'NotEquals':
        return _binary(node, '!=');
      case 'GreaterThan':
        return _binary(node, '>');
      case 'LessThan':
        return _binary(node, '<');
      case 'GreaterOrEqual':
        return _binary(node, '>=');
      case 'LessOrEqual':
        return _binary(node, '<=');
      case 'And':
        return _binary(node, '&&');
      case 'Or':
        return _binary(node, '||');
      case 'Concat':
        return _binary(node, '+');

      case 'Not':
        final a = _input(node, 'a');
        return Emitted.plain(
          CodeExpression(
            Code(
                '!${asOperand(renderExpression(a.bare()), isCompound: a.isCompound)}'),
          ),
          isConst: a.isConst,
          signalDeps: a.signalDeps,
        );

      case 'ToString':
        final value = _input(node, 'value');
        return Emitted.plain(
          value.bare().property('toString').call(const []),
          signalDeps: value.signalDeps,
        );

      case 'Conditional':
        final condition = _input(node, 'condition');
        final whenTrue = _input(node, 'ifTrue');
        final whenFalse = _input(node, 'ifFalse');
        final merged = Emitted.merge([condition, whenTrue, whenFalse]);
        final source =
            '${asOperand(renderExpression(condition.bare()), isCompound: condition.isCompound)} '
            '? ${asOperand(renderExpression(whenTrue.bare()), isCompound: whenTrue.isCompound)} '
            ': ${asOperand(renderExpression(whenFalse.bare()), isCompound: whenFalse.isCompound)}';
        return Emitted.plain(
          CodeExpression(Code(source)),
          isConst: merged.isConst,
          isCompound: true,
          signalDeps: merged.deps,
        );

      case 'ListIsEmpty':
        final list = _input(node, 'list');
        return Emitted.plain(
          list.bare().property('isEmpty'),
          signalDeps: list.signalDeps,
        );

      case 'ListLength':
        final list = _input(node, 'list');
        return Emitted.plain(
          list.bare().property('length'),
          signalDeps: list.signalDeps,
        );

      case 'ListAppend':
        final list = _input(node, 'list');
        final item = _input(node, 'item');
        final merged = Emitted.merge([list, item]);
        return Emitted.plain(
          CodeExpression(Code(
            '[...${renderExpression(list.bare())}, ${renderExpression(item.bare())}]',
          )),
          signalDeps: merged.deps,
        );

      case 'ListSetAt':
        final list = _input(node, 'list');
        final index = _input(node, 'index');
        final item = _input(node, 'item');
        final merged = Emitted.merge([list, index, item]);
        return Emitted.plain(
          CodeExpression(Code(
            '(List.of(${renderExpression(list.bare())})'
            '..[${renderExpression(index.bare())}] = '
            '${renderExpression(item.bare())})',
          )),
          signalDeps: merged.deps,
        );

      case 'MapGet':
        final map = _input(node, 'map');
        final key = _input(node, 'key');
        final merged = Emitted.merge([map, key]);
        return Emitted.plain(
          CodeExpression(Code(
            '${renderExpression(map.bare())}[${renderExpression(key.bare())}]',
          )),
          signalDeps: merged.deps,
        );

      case 'MapPut':
        final map = _input(node, 'map');
        final key = _input(node, 'key');
        final value = _input(node, 'value');
        final merged = Emitted.merge([map, key, value]);
        return Emitted.plain(
          CodeExpression(Code(
            '{...${renderExpression(map.bare())}, '
            '${renderExpression(key.bare())}: '
            '${renderExpression(value.bare())}}',
          )),
          signalDeps: merged.deps,
        );

      case 'ListRemoveAt':
        final list = _input(node, 'list');
        final index = _input(node, 'index');
        final merged = Emitted.merge([list, index]);
        return Emitted.plain(
          CodeExpression(Code(
            '(List.of(${renderExpression(list.bare())})'
            '..removeAt(${renderExpression(index.bare())}))',
          )),
          signalDeps: merged.deps,
        );

      case 'Computed':
      case 'DartCode':
        final helper = helpers[node.id]!;
        final args = [
          for (final parameter in helper.parameters)
            _input(node, parameter.name),
        ];
        final merged = Emitted.merge(args);
        return Emitted.plain(
          refer(helper.name).call([for (final a in args) a.bare()]),
          signalDeps: merged.deps,
        );

      case 'Event':
        if (ref.pin != 'payload') {
          throw CodegenException(
            'Event node "${node.id}" has no data pin "${ref.pin}".',
            pageId: unit.id,
            nodeId: node.id,
          );
        }
        final payload = _payloadName;
        if (payload == null) {
          throw CodegenException(
            'Event payload of "${node.id}" is only readable inside its own '
            'handler chain.',
            pageId: unit.id,
            nodeId: node.id,
          );
        }
        return Emitted.plain(refer(payload));

      default:
        throw CodegenException(
          'No lowering for node type "${node.type}".',
          pageId: unit.id,
          nodeId: node.id,
        );
    }
  }

  Emitted _input(GraphNode node, String pin, {int? index}) {
    final ref = PinRef(node.id, pin, index: index);
    final edge = graph.source(ref);
    if (edge == null) {
      throw CodegenException(
        '${node.type}.$pin has no incoming edge.',
        pageId: unit.id,
        nodeId: node.id,
      );
    }
    return _lowerPin(edge.from);
  }

  Emitted _binary(GraphNode node, String op) {
    final a = _input(node, 'a');
    final b = _input(node, 'b');
    final merged = Emitted.merge([a, b]);
    final source =
        '${asOperand(renderExpression(a.bare()), isCompound: a.isCompound)} '
        '$op ${asOperand(renderExpression(b.bare()), isCompound: b.isCompound)}';
    return Emitted.plain(
      CodeExpression(Code(source)),
      isConst: merged.isConst,
      isCompound: true,
      signalDeps: merged.deps,
    );
  }

  /// `Format` compiles to a Dart interpolated string, which is what a person
  /// would have written: `'Count: ${count.value}'`.
  Emitted _format(GraphNode node) {
    final template = node.get<String>('template') ?? '{0}';
    final buffer = StringBuffer("'");
    final deps = <String>{};
    var allConst = true;

    final pattern = RegExp(r'\{(\d+)\}');
    var cursor = 0;
    for (final match in pattern.allMatches(template)) {
      buffer.write(_escape(template.substring(cursor, match.start)));
      final index = int.parse(match.group(1)!);
      final argument = _input(node, 'args', index: index);
      deps.addAll(argument.signalDeps);
      allConst = allConst && argument.isConst;
      buffer.write('\${${renderExpression(argument.bare())}}');
      cursor = match.end;
    }
    buffer
      ..write(_escape(template.substring(cursor)))
      ..write("'");

    return Emitted.plain(
      CodeExpression(Code(buffer.toString())),
      isConst: allConst && deps.isEmpty,
      signalDeps: deps,
    );
  }

  static String _escape(String text) => text
      .replaceAll(r'\', r'\\')
      .replaceAll(r'$', r'\$')
      .replaceAll("'", r"\'")
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');

  // ---------------------------------------------------------------------------
  // Event chains
  // ---------------------------------------------------------------------------

  void _lowerHandlers() {
    for (final node in graph.ofType('Event')) {
      final widgetId = node.get<String>('widget');
      final eventName = node.get<String>('event');
      if (widgetId == null || eventName == null) {
        throw CodegenException(
          'Event node "${node.id}" must name a widget and an event.',
          pageId: unit.id,
          nodeId: node.id,
        );
      }
      final name = namer.take(Naming.handler(widgetId, eventName));
      handlerNames[node.id] = name;

      // A handler fired from inside a template is still a method on the State
      // class, so the loop variables it reads have to be handed in. The call
      // site becomes a closure that passes them (ADR-009).
      handlerScopeArgs[node.id] = _scopeArgumentsFor(node.id, widgetId);

      final payloadType = ctx.eventPayload(widgetId, eventName);
      final hasPayload = payloadType != PrimitiveType.void_;
      _payloadName = hasPayload ? 'value' : null;

      final statements = <Code>[];
      final trace = <String>[node.id];
      _chainIsAsync = false;

      var edge = graph.outgoing(PinRef(node.id, 'fire')).firstOrNull;
      final visited = <String>{};
      while (edge != null) {
        final action = graph.node(edge.to.nodeId);
        if (action == null) break;
        if (!visited.add(action.id)) {
          throw CodegenException(
            'Action chain from "${node.id}" loops at "${action.id}".',
            pageId: unit.id,
            nodeId: action.id,
          );
        }
        trace.add(action.id);
        statements.addAll(_lowerAction(action));
        edge = graph.outgoing(PinRef(action.id, 'next')).firstOrNull;
      }

      _payloadName = null;
      handlers.add(
        HandlerIr(
          eventNodeId: node.id,
          name: name,
          payloadType: hasPayload ? payloadType : null,
          payloadName: 'value',
          isAsync: _chainIsAsync,
          scopeParameters: [
            for (final argument in handlerScopeArgs[node.id]!)
              (name: argument.variable, type: argument.type),
          ],
          statements: statements,
          trace: trace,
        ),
      );
    }
  }

  /// The loop variables an event's action chain reads, in outermost-first
  /// order, restricted to the templates the firing widget actually sits in.
  List<_ScopeArgument> _scopeArgumentsFor(String eventNodeId, String widgetId) {
    final enclosing = scopes.enclosing(widgetId);
    if (enclosing.isEmpty) return const [];

    final used = <String, Set<String>>{};
    for (final actionId in _actionChain(eventNodeId)) {
      for (final edge in graph.edges) {
        if (edge.to.nodeId != actionId) continue;
        _collectScopePins(edge.from, used, {});
      }
    }

    final arguments = <_ScopeArgument>[];
    for (final forEachId in enclosing) {
      final pins = used[forEachId];
      final vars = scopeVars[forEachId];
      if (pins == null || vars == null) continue;
      if (pins.contains('item')) {
        arguments.add(_ScopeArgument(vars.item, vars.element));
      }
      if (pins.contains('index')) {
        arguments.add(_ScopeArgument(vars.index, PrimitiveType.int_));
      }
    }
    return arguments;
  }

  /// Walks back through data edges recording which `ForEachItem` pins a value
  /// ultimately reads.
  void _collectScopePins(
    PinRef pin,
    Map<String, Set<String>> into,
    Set<String> visiting,
  ) {
    final node = graph.node(pin.nodeId);
    if (node == null || !visiting.add(pin.nodeId)) return;

    if (node.type == 'ForEachItem') {
      final owner = node.get<String>('forEach');
      if (owner != null) into.putIfAbsent(owner, () => {}).add(pin.pin);
    }
    for (final edge in graph.edges) {
      if (edge.to.nodeId != pin.nodeId) continue;
      _collectScopePins(edge.from, into, visiting);
    }
    visiting.remove(pin.nodeId);
  }

  List<String> _actionChain(String eventNodeId) {
    final chain = <String>[];
    final seen = <String>{};
    var edge = graph.outgoing(PinRef(eventNodeId, 'fire')).firstOrNull;
    while (edge != null) {
      final id = edge.to.nodeId;
      if (!seen.add(id)) break;
      chain.add(id);
      edge = graph.outgoing(PinRef(id, 'next')).firstOrNull;
    }
    return chain;
  }

  List<Code> _lowerAction(GraphNode action) {
    String signalName() {
      final id = action.get<String>('signal');
      final name = id == null ? null : signalNames[id];
      if (name == null) {
        throw CodegenException(
          '${action.type} "${action.id}" targets an unknown signal.',
          pageId: unit.id,
          nodeId: action.id,
        );
      }
      return name;
    }

    switch (action.type) {
      case 'SetSignal':
        final name = signalName();
        final value = _input(action, 'value');
        return [Code('$name.value = ${renderExpression(value.bare())};')];

      case 'UpdateSignal':
        final name = signalName();
        final fn = action.get<String>('fn');
        if (fn == null || fn.trim().isEmpty) {
          throw CodegenException(
            'UpdateSignal "${action.id}" needs an "fn".',
            pageId: unit.id,
            nodeId: action.id,
          );
        }
        return [Code('$name.value = ${_apply(fn, '$name.value')};')];

      case 'ToggleSignal':
        final name = signalName();
        return [Code('$name.value = !$name.value;')];

      case 'Navigate':
        final route = action.get<String>('route');
        if (route == null) {
          throw CodegenException(
            'Navigate "${action.id}" needs a "route".',
            pageId: unit.id,
            nodeId: action.id,
          );
        }
        final method = (action.get<bool>('replace') ?? false)
            ? 'pushReplacementNamed'
            : 'pushNamed';

        // One argument per parameter the target page declares; the route table
        // unpacks them on the other side.
        final target = ctx.pageForRoute(route);
        final arguments = <String>[];
        for (final parameter in target?.parameters ?? const <FieldDef>[]) {
          final edge = graph.source(PinRef(action.id, parameter.name));
          if (edge == null) continue;
          final value = _lowerPin(edge.from);
          arguments.add(
            "'${parameter.name}': ${renderExpression(value.bare())}",
          );
        }

        final call = StringBuffer(
          "Navigator.of(context).$method('${_escape(route)}'",
        );
        if (arguments.isNotEmpty) {
          call.write(', arguments: {${arguments.join(', ')}}');
        }
        call.write(');');
        return [Code(call.toString())];

      case 'ShowSnackBar':
        final message = _input(action, 'message');
        return [
          Code(
            'ScaffoldMessenger.of(context).showSnackBar('
            'SnackBar(content: Text(${renderExpression(message.bare())})));',
          ),
        ];

      case 'HttpRequest':
        return _lowerHttpRequest(action);

      case 'Print':
        final message = _input(action, 'message');
        return [
          Code('debugPrint(\'\${${renderExpression(message.bare())}}\');')
        ];

      default:
        throw CodegenException(
          'No lowering for action "${action.type}".',
          pageId: unit.id,
          nodeId: action.id,
        );
    }
  }

  /// An HTTP call plus the loading and error bookkeeping a person would write
  /// around it by hand.
  List<Code> _lowerHttpRequest(GraphNode action) {
    _usesHttp = true;
    _chainIsAsync = true;

    final method = (action.get<String>('method') ?? 'GET').toLowerCase();
    final url = _input(action, 'url');

    final targetId = action.get<String>('signal');
    final target = targetId == null ? null : signalNames[targetId];
    final targetType = ctx.signalType(targetId);
    if (target == null) {
      throw CodegenException(
        'HttpRequest "${action.id}" needs a "signal" to write the result into.',
        pageId: unit.id,
        nodeId: action.id,
      );
    }

    final loading = signalNames[action.get<String>('loadingSignal')];
    final failure = signalNames[action.get<String>('errorSignal')];

    final response = namer.take('response');
    final caught = namer.take('failure');
    final decoded = _decodeExpression(targetType, '$response.body', action);

    final request = StringBuffer('http.$method(Uri.parse(');
    request.write(renderExpression(url.bare()));
    request.write(')');
    if (method != 'get') {
      final edge = graph.source(PinRef(action.id, 'body'));
      if (edge != null) {
        request
            .write(', body: ${renderExpression(_lowerPin(edge.from).bare())}');
      }
    }
    request.write(')');

    final body = StringBuffer()
      ..writeln('try {')
      ..writeln('  final $response = await $request;')
      ..writeln('  if ($response.statusCode >= 400) {')
      ..writeln(
        "    throw Exception('Request failed: \${$response.statusCode}');",
      )
      ..writeln('  }')
      ..writeln('  $target.value = $decoded;')
      ..writeln('} catch ($caught) {');
    if (failure != null) {
      body.writeln('  $failure.value = $caught.toString();');
    } else {
      body.writeln('  debugPrint(\'Request failed: \$$caught\');');
    }
    body.writeln('}');
    if (loading != null) {
      body.writeln('finally {');
      body.writeln('  $loading.value = false;');
      body.writeln('}');
    }

    return [
      if (loading != null) Code('$loading.value = true;'),
      if (failure != null) Code('$failure.value = null;'),
      Code(body.toString()),
    ];
  }

  /// How a response body turns into the target signal's type.
  String _decodeExpression(
    LatticeType type,
    String bodyExpression,
    GraphNode action,
  ) {
    switch (type) {
      case NullableType(:final inner):
        return _decodeExpression(inner, bodyExpression, action);
      case PrimitiveType(kind: PrimitiveKind.string$):
        return bodyExpression;
      case ModelType(:final name):
        _usesJson = true;
        _noteModelUse(type);
        return '$name.fromJson('
            'jsonDecode($bodyExpression) as Map<String, Object?>)';
      case ListType(element: ModelType(:final name)):
        _usesJson = true;
        _noteModelUse(type);
        return '[for (final entry in jsonDecode($bodyExpression) as List<Object?>) '
            '$name.fromJson(entry as Map<String, Object?>)]';
      case MapType() || ListType():
        _usesJson = true;
        return 'jsonDecode($bodyExpression) as ${type.dartName}';
      default:
        throw CodegenException(
          'HttpRequest cannot decode a response into ${type.dartName}. '
          'Use String for the raw body, or a model / list of models for JSON.',
          pageId: unit.id,
          nodeId: action.id,
        );
    }
  }

  /// Applies a single-argument lambda to an argument, beta-reducing when it is
  /// safe to do so: `(x) => x + 1` against `count.value` becomes
  /// `count.value + 1` rather than `((x) => x + 1)(count.value)` (§8).
  static String _apply(String fn, String argument) {
    final match = RegExp(
      r'^\(\s*([A-Za-z_$][A-Za-z0-9_$]*)\s*\)\s*=>\s*(.+)$',
      dotAll: true,
    ).firstMatch(fn.trim());

    if (match != null) {
      final parameter = match.group(1)!;
      final body = match.group(2)!.trim();
      // Substitution is textual, so it is only attempted when there is no
      // string literal that could contain the parameter name.
      if (!body.contains("'") && !body.contains('"')) {
        return body.replaceAllMapped(
          RegExp('(?<![A-Za-z0-9_\$])$parameter(?![A-Za-z0-9_\$])'),
          (_) => argument,
        );
      }
    }
    return '($fn)($argument)';
  }

  // ---------------------------------------------------------------------------
  // Widget tree
  // ---------------------------------------------------------------------------

  Emitted _lowerWidget(WidgetNode widget, {required bool insideBoundary}) {
    final schema = widgets.lookup(widget.type);
    if (schema == null) {
      throw CodegenException(
        '"${widget.type}" is not a known widget.',
        pageId: unit.id,
        widgetId: widget.id,
      );
    }
    final prefab = project.prefab(widget.type);
    if (prefab != null) usedPrefabs.add(prefab.fileName);

    if (schema.isPseudo) {
      // ForEach and If are not expressions on their own; they are expanded by
      // whichever slot contains them.
      throw CodegenException(
        '${widget.type} cannot be used here.',
        pageId: unit.id,
        widgetId: widget.id,
      );
    }

    // Decided up front, so everything below knows whether it is already
    // covered by a rebuild boundary.
    final wrap = !insideBoundary && _ownSignalDeps(widget).isNotEmpty;
    final covered = insideBoundary || wrap;

    final positional = <Emitted>[];
    final named = <String, Emitted>{};
    final composites = <String, Map<String, Emitted>>{};

    for (final param in schema.params) {
      final prop = widget.props[param.name];
      if (prop == null) continue;
      final value =
          _lowerProp(widget, schema, param, prop, insideBoundary: covered);
      if (value == null) continue;

      final binding = param.controller;
      if (binding != null) {
        named[binding.argument] = _allocateController(widget, binding, value);
      } else if (param.emitInto != null) {
        composites.putIfAbsent(param.emitInto!, () => {})[param.name] = value;
      } else if (param.positional) {
        positional.add(value);
      } else {
        named[param.name] = value;
      }
    }

    for (final entry in composites.entries) {
      final constructor = schema.composites[entry.key];
      if (constructor == null) continue;
      final merged = Emitted.merge(entry.value.values);
      named[entry.key] = Emitted(
        (asConst) {
          final args = {
            for (final arg in entry.value.entries)
              arg.key: arg.value.inContext(parentIsConst: asConst),
          };
          final target = refer(constructor);
          return asConst
              ? target.constInstance(const [], args)
              : target.newInstance(const [], args);
        },
        isConst: merged.isConst,
        signalDeps: merged.deps,
      );
    }

    final childrenParam = schema.childrenParam;
    if (childrenParam != null && widget.children.isNotEmpty) {
      named[childrenParam] = schema.childArity == ChildArity.one
          ? _lowerSingleChild(widget.children.first, insideBoundary: covered)
          : _lowerChildList(widget.children, insideBoundary: covered);
    }

    final parts = [...positional, ...named.values];
    final merged = Emitted.merge(parts);
    final constructor = schema.constructor;

    final call = Emitted(
      (asConst) {
        final args = [
          for (final p in positional) p.inContext(parentIsConst: asConst),
        ];
        final kwargs = {
          for (final n in named.entries)
            n.key: n.value.inContext(parentIsConst: asConst),
        };
        final target = refer(widget.type);
        if (asConst) {
          return constructor == null
              ? target.constInstance(args, kwargs)
              : target.constInstanceNamed(constructor, args, kwargs);
        }
        return constructor == null
            ? target.newInstance(args, kwargs)
            : target.newInstanceNamed(constructor, args, kwargs);
      },
      isConst: schema.constCtor && merged.isConst,
      signalDeps: merged.deps,
    );

    if (!wrap) return call;

    // The reactive boundary lands here: the outermost widget in this branch
    // whose own arguments read a signal. Descendants were lowered knowing they
    // are already covered, so boundaries never nest (§7.5).
    // `SignalBuilder` is the one name both runtime backends expose.
    final closure = Method(
      (b) => b
        ..requiredParameters.add(Parameter((p) => p..name = 'context'))
        ..lambda = true
        ..body = Code(renderExpression(call.bare())),
    ).closure;

    return Emitted.plain(
      refer('SignalBuilder').call(const [], {'builder': closure}),
    );
  }

  /// Records a controller for [widget] and returns the reference to pass as
  /// the constructor argument.
  Emitted _allocateController(
    WidgetNode widget,
    ControllerBinding binding,
    Emitted value,
  ) {
    final name = namer.take('_${Naming.camel(widget.id)}Controller');
    controllers.add(
      ControllerIr(
        widgetId: widget.id,
        name: name,
        type: binding.type,
        property: binding.property,
        initial: value,
        isReactive: value.isReactive,
      ),
    );
    return Emitted.plain(refer(name));
  }

  /// Signals read by a widget's *own* arguments — not its children's.
  ///
  /// Computed structurally off the graph rather than from lowered
  /// expressions, because the boundary has to be decided before the subtree is
  /// emitted. A directly nested `ForEach` or `If` counts as the container's
  /// own dependency: those expand inline into its children list, so it is the
  /// container that must rebuild when the list or the condition changes.
  Set<String> _ownSignalDeps(WidgetNode widget) {
    final schema = widgets.lookup(widget.type);
    final deps = <String>{};
    for (final entry in widget.props.entries) {
      // A controller pushes updates into the widget itself, so rebuilding the
      // widget would be wasteful and would reset the cursor.
      if (schema?.param(entry.key)?.controller != null) continue;
      final prop = entry.value;
      switch (prop) {
        case BindProp(:final source):
          deps.addAll(_signalsFor(source.nodeId));
        case ExprProp(:final code):
          deps.addAll(_signalsMentionedIn(code));
        default:
          break;
      }
    }
    for (final child in widget.children) {
      if (child.type == 'ForEach' || child.type == 'If') {
        deps.addAll(_ownSignalDeps(child));
      }
    }
    return deps;
  }

  /// A single-widget slot (`child`, `body`). `If` becomes a conditional
  /// expression here, because there is no collection-`if` outside a list.
  Emitted _lowerSingleChild(
    WidgetNode child, {
    required bool insideBoundary,
  }) {
    if (child.type == 'If') {
      return _lowerIfExpression(child, insideBoundary: insideBoundary);
    }
    if (child.type == 'ForEach') {
      throw CodegenException(
        'ForEach can produce any number of widgets, so it needs a slot that '
        'takes a list of children.',
        pageId: unit.id,
        widgetId: child.id,
      );
    }
    return _lowerWidget(child, insideBoundary: insideBoundary);
  }

  /// A `children:` slot. Structural directives expand into collection-`for`
  /// and collection-`if` here — exactly the syntax a person reaches for.
  Emitted _lowerChildList(
    List<WidgetNode> children, {
    required bool insideBoundary,
  }) {
    final hasStructure =
        children.any((c) => c.type == 'ForEach' || c.type == 'If');

    if (!hasStructure) {
      final lowered = [
        for (final c in children)
          _lowerWidget(c, insideBoundary: insideBoundary),
      ];
      final merged = Emitted.merge(lowered);
      return Emitted(
        (asConst) {
          final items = [
            for (final c in lowered) c.inContext(parentIsConst: asConst),
          ];
          return asConst ? literalConstList(items) : literalList(items);
        },
        isConst: merged.isConst,
        signalDeps: merged.deps,
      );
    }

    final deps = <String>{};
    final elements = <String>[];
    for (final child in children) {
      switch (child.type) {
        case 'ForEach':
          elements.add(
            _forEachElement(child, deps, insideBoundary: insideBoundary),
          );
        case 'If':
          elements.add(_ifElement(child, deps, insideBoundary: insideBoundary));
        default:
          final lowered = _lowerWidget(child, insideBoundary: insideBoundary);
          deps.addAll(lowered.signalDeps);
          elements.add(
            renderExpression(lowered.inContext(parentIsConst: false)),
          );
      }
    }

    // A list holding a `for` or an `if` is never a constant.
    return Emitted.plain(
      CodeExpression(Code('[${elements.join(', ')}]')),
      signalDeps: deps,
    );
  }

  /// `for (final item in todos.value) KeyedSubtree(key: ..., child: ...)`.
  String _forEachElement(
    WidgetNode widget,
    Set<String> deps, {
    required bool insideBoundary,
  }) {
    final vars = scopeVars[widget.id];
    if (vars == null) {
      throw CodegenException(
        'ForEach "${widget.id}" has no loop variables.',
        pageId: unit.id,
        widgetId: widget.id,
      );
    }

    final items =
        _lowerNamedProp(widget, 'items', insideBoundary: insideBoundary);
    if (items == null) {
      throw CodegenException(
        'ForEach "${widget.id}" has no "items".',
        pageId: unit.id,
        widgetId: widget.id,
      );
    }
    // Only the list itself is reactive from the outside; anything the template
    // reads has already been wrapped in its own boundary.
    deps.addAll(items.signalDeps);

    final template =
        _lowerWidget(widget.children.first, insideBoundary: insideBoundary);
    var body = renderExpression(template.inContext(parentIsConst: false));

    final keyField = _itemKeyField(widget);
    if (keyField != null) {
      body = 'KeyedSubtree(key: ValueKey(${vars.item}.$keyField), '
          'child: $body)';
    }

    final source = renderExpression(items.bare());
    return _usesIndex(widget.id)
        ? 'for (final (${vars.index}, ${vars.item}) in $source.indexed) $body'
        : 'for (final ${vars.item} in $source) $body';
  }

  /// The field naming an item's identity, or null when items carry none.
  String? _itemKeyField(WidgetNode widget) {
    if (ctx.forEachElementType(widget.id) is! ModelType) return null;
    final prop = widget.props['itemKey'];
    if (prop is! LiteralProp) return null;
    final value = prop.value;
    return value is String && value.isNotEmpty ? value : null;
  }

  /// Whether anything reads this ForEach's `index` pin. Emitting the indexed
  /// form unconditionally would leave an unused variable in most loops.
  bool _usesIndex(String forEachWidgetId) => graph.edges.any((edge) {
        if (edge.from.pin != 'index') return false;
        final node = graph.node(edge.from.nodeId);
        return node?.type == 'ForEachItem' &&
            node?.get<String>('forEach') == forEachWidgetId;
      });

  /// `if (cond) A else B`, for use inside a children list.
  String _ifElement(
    WidgetNode widget,
    Set<String> deps, {
    required bool insideBoundary,
  }) {
    final (condition, whenTrue, whenFalse) =
        _ifParts(widget, insideBoundary: insideBoundary);
    deps.addAll(condition.signalDeps);
    deps.addAll(whenTrue.signalDeps);

    final buffer = StringBuffer(
      'if (${renderExpression(condition.bare())}) '
      '${renderExpression(whenTrue.inContext(parentIsConst: false))}',
    );
    if (whenFalse != null) {
      deps.addAll(whenFalse.signalDeps);
      buffer.write(
        ' else ${renderExpression(whenFalse.inContext(parentIsConst: false))}',
      );
    }
    return buffer.toString();
  }

  /// `cond ? A : B`, for a single-widget slot. The missing branch becomes an
  /// empty box, because a slot has to hold something.
  Emitted _lowerIfExpression(
    WidgetNode widget, {
    required bool insideBoundary,
  }) {
    final (condition, whenTrue, whenFalse) =
        _ifParts(widget, insideBoundary: insideBoundary);
    final parts = [condition, whenTrue, if (whenFalse != null) whenFalse];
    final merged = Emitted.merge(parts);

    final otherwise = whenFalse == null
        ? 'const SizedBox.shrink()'
        : renderExpression(whenFalse.inContext(parentIsConst: false));

    // A comparison binds tighter than `?:`, so it needs no parentheses here.
    // Only a nested conditional would be ambiguous.
    final conditionSource = renderExpression(condition.bare());
    final guarded = conditionSource.contains(' ? ')
        ? '($conditionSource)'
        : conditionSource;

    return Emitted.plain(
      CodeExpression(Code(
        '$guarded '
        '? ${renderExpression(whenTrue.inContext(parentIsConst: false))} '
        ': $otherwise',
      )),
      isCompound: true,
      signalDeps: merged.deps,
    );
  }

  (Emitted, Emitted, Emitted?) _ifParts(
    WidgetNode widget, {
    required bool insideBoundary,
  }) {
    final condition =
        _lowerNamedProp(widget, 'condition', insideBoundary: insideBoundary);
    if (condition == null || widget.children.isEmpty) {
      throw CodegenException(
        'If "${widget.id}" needs a condition and one child.',
        pageId: unit.id,
        widgetId: widget.id,
      );
    }
    final orElse = widget.props['orElse'];
    return (
      condition,
      _lowerSingleChild(widget.children.first, insideBoundary: insideBoundary),
      orElse is WidgetProp
          ? _lowerSingleChild(orElse.widget, insideBoundary: insideBoundary)
          : null,
    );
  }

  /// Lowers one named prop of [widget] outside the usual argument loop, for
  /// the structural directives whose parameters are consumed rather than
  /// emitted.
  Emitted? _lowerNamedProp(
    WidgetNode widget,
    String name, {
    required bool insideBoundary,
  }) {
    final schema = widgets.lookup(widget.type);
    final param = schema?.param(name);
    final prop = widget.props[name];
    if (schema == null || param == null || prop == null) return null;
    return _lowerProp(
      widget,
      schema,
      param,
      prop,
      insideBoundary: insideBoundary,
    );
  }

  /// Returns null when the prop is exactly the schema default and can be left
  /// out of the generated call.
  Emitted? _lowerProp(
    WidgetNode widget,
    WidgetSchema schema,
    ParamSchema param,
    PropValue prop, {
    required bool insideBoundary,
  }) {
    switch (prop) {
      case LiteralProp(:final value):
        if (value == null && !param.required) return null;
        if (param.defaultValue != null && value == param.defaultValue) {
          return null;
        }
        _noteModelUse(param.type);
        return literals.emit(param.type, value,
            where: '${widget.type}.${param.name}',
            pageId: unit.id,
            widgetId: widget.id);

      case ExprProp(:final code):
        return Emitted.plain(
          CodeExpression(Code(code)),
          isCompound: true,
          signalDeps: _signalsMentionedIn(code),
        );

      case BindProp(:final source):
        return _lowerPin(source);

      case EventProp(:final eventNodeId):
        final name = handlerNames[eventNodeId];
        if (name == null) {
          throw CodegenException(
            '${widget.type}.${param.name} refers to unknown event node '
            '"$eventNodeId".',
            pageId: unit.id,
            widgetId: widget.id,
          );
        }
        final scopeArguments = handlerScopeArgs[eventNodeId] ?? const [];
        if (scopeArguments.isEmpty) {
          // Nothing to capture, so a tear-off reads better than a closure.
          return Emitted.plain(refer(name));
        }
        final hasPayload = param.type != PrimitiveType.void_;
        final parameters = hasPayload ? '(value)' : '()';
        final arguments = [
          if (hasPayload) 'value',
          for (final argument in scopeArguments) argument.variable,
        ].join(', ');
        return Emitted.plain(
          CodeExpression(Code('$parameters => $name($arguments)')),
        );

      case WidgetProp(widget: final child):
        return _lowerWidget(child, insideBoundary: insideBoundary);

      case WidgetListProp(:final widgets):
        final children = [
          for (final w in widgets)
            _lowerWidget(w, insideBoundary: insideBoundary),
        ];
        final merged = Emitted.merge(children);
        return Emitted(
          (asConst) {
            final items = [
              for (final c in children) c.inContext(parentIsConst: asConst),
            ];
            return asConst ? literalConstList(items) : literalList(items);
          },
          isConst: merged.isConst,
          signalDeps: merged.deps,
        );
    }
  }

  /// An inline `$expr` is opaque Dart, so its dependencies are found by
  /// looking for signal field names in the text. A false positive costs one
  /// extra `Watch`; a false negative is impossible for anything spelled the
  /// normal way (`count.value`).
  Set<String> _signalsMentionedIn(String code) {
    final found = <String>{};
    for (final entry in signalNames.entries) {
      if (RegExp('(?<![A-Za-z0-9_\$])${entry.value}(?![A-Za-z0-9_\$])')
          .hasMatch(code)) {
        found.add(entry.key);
      }
    }
    return found;
  }
}

/// The loop variables one `ForEach` template runs under.
final class _ScopeVars {
  const _ScopeVars({
    required this.item,
    required this.index,
    required this.element,
  });

  final String item;
  final String index;
  final LatticeType element;
}

/// One loop variable an event handler has to be handed, because the handler is
/// a method on the State class and cannot see the loop (ADR-009).
final class _ScopeArgument {
  const _ScopeArgument(this.variable, this.type);

  final String variable;
  final LatticeType type;
}
