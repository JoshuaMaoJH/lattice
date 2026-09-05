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
          for (final page in project.pages) _PageLowering(project, page).run(),
        ],
      );
}

class _PageLowering {
  _PageLowering(this.project, this.page)
      : graph = page.graph,
        literals = LiteralEmitter(models: project.models) {
    ctx = NodeContext(graph: graph, page: page, project: project);
  }

  final Project project;
  final Page page;
  final Graph graph;
  final LiteralEmitter literals;
  late final NodeContext ctx;

  final Namer namer = Namer(const ['context', 'widget', 'key', 'build']);
  final Map<String, String> signalNames = {};
  final List<SignalIr> signals = [];
  final Map<PinRef, HoistedIr> hoists = {};
  final Map<String, HelperIr> helpers = {};
  final List<HandlerIr> handlers = [];
  final Map<String, String> handlerNames = {};
  final Map<String, Set<String>> _signalCache = {};

  /// The parameter name for the payload of the handler currently being
  /// lowered; `Event.payload` resolves to it.
  String? _payloadName;

  bool _usesModels = false;

  PageIr run() {
    _collectSignals();
    _collectHelpers();
    _planHoists();
    _lowerHandlers();

    final body = _lowerWidget(page.hierarchy);

    return PageIr(
      page: page,
      className: page.className,
      fileName: page.fileName,
      signals: signals,
      hoisted: hoists.values.toList(),
      helpers: helpers.values.toList(),
      handlers: handlers,
      body: body,
      usesModels: _usesModels,
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
              pageId: page.id,
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
            pageId: page.id,
            nodeId: node.id,
          ),
      };

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
          pageId: page.id,
          nodeId: node.id,
        );
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
    for (final widget in page.hierarchy.descendantsAndSelf) {
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
          pageId: page.id);
    }

    switch (node.type) {
      case 'Signal':
        final name = signalNames[node.id]!;
        return Emitted.reactive(refer(name).property('value'), {node.id});

      case 'Const':
        final type = ctx.resolve(node.get<String>('dartType'));
        _noteModelUse(type);
        return literals.emit(type, node.config['value'],
            where: 'Const ${node.id}', pageId: page.id, nodeId: node.id);

      case 'Reroute':
        return _input(node, 'in');

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
            pageId: page.id,
            nodeId: node.id,
          );
        }
        final payload = _payloadName;
        if (payload == null) {
          throw CodegenException(
            'Event payload of "${node.id}" is only readable inside its own '
            'handler chain.',
            pageId: page.id,
            nodeId: node.id,
          );
        }
        return Emitted.plain(refer(payload));

      default:
        throw CodegenException(
          'No lowering for node type "${node.type}".',
          pageId: page.id,
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
        pageId: page.id,
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
          pageId: page.id,
          nodeId: node.id,
        );
      }
      final name = namer.take(Naming.handler(widgetId, eventName));
      handlerNames[node.id] = name;

      final payloadType = ctx.eventPayload(widgetId, eventName);
      final hasPayload = payloadType != PrimitiveType.void_;
      _payloadName = hasPayload ? 'value' : null;

      final statements = <Code>[];
      final trace = <String>[node.id];

      var edge = graph.outgoing(PinRef(node.id, 'fire')).firstOrNull;
      final visited = <String>{};
      while (edge != null) {
        final action = graph.node(edge.to.nodeId);
        if (action == null) break;
        if (!visited.add(action.id)) {
          throw CodegenException(
            'Action chain from "${node.id}" loops at "${action.id}".',
            pageId: page.id,
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
          statements: statements,
          trace: trace,
        ),
      );
    }
  }

  List<Code> _lowerAction(GraphNode action) {
    String signalName() {
      final id = action.get<String>('signal');
      final name = id == null ? null : signalNames[id];
      if (name == null) {
        throw CodegenException(
          '${action.type} "${action.id}" targets an unknown signal.',
          pageId: page.id,
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
            pageId: page.id,
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
            pageId: page.id,
            nodeId: action.id,
          );
        }
        final method = (action.get<bool>('replace') ?? false)
            ? 'pushReplacementNamed'
            : 'pushNamed';
        return [
          Code("Navigator.of(context).$method('${_escape(route)}');"),
        ];

      case 'ShowSnackBar':
        final message = _input(action, 'message');
        return [
          Code(
            'ScaffoldMessenger.of(context).showSnackBar('
            'SnackBar(content: Text(${renderExpression(message.bare())})));',
          ),
        ];

      case 'Print':
        final message = _input(action, 'message');
        return [
          Code('debugPrint(\'\${${renderExpression(message.bare())}}\');')
        ];

      default:
        throw CodegenException(
          'No lowering for action "${action.type}".',
          pageId: page.id,
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

  Emitted _lowerWidget(WidgetNode widget) {
    final schema = WidgetRegistry.lookup(widget.type);
    if (schema == null) {
      throw CodegenException(
        '"${widget.type}" is not a known widget.',
        pageId: page.id,
        widgetId: widget.id,
      );
    }

    final positional = <Emitted>[];
    final named = <String, Emitted>{};
    final composites = <String, Map<String, Emitted>>{};

    for (final param in schema.params) {
      final prop = widget.props[param.name];
      if (prop == null) continue;
      final value = _lowerProp(widget, schema, param, prop);
      if (value == null) continue;

      if (param.emitInto != null) {
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
      final children = [for (final c in widget.children) _lowerWidget(c)];
      if (schema.childArity == ChildArity.one) {
        named[childrenParam] = children.first;
      } else {
        final merged = Emitted.merge(children);
        named[childrenParam] = Emitted(
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

    if (!call.isReactive) return call;

    // The reactive boundary lands here, at the innermost widget whose own
    // arguments read a signal — everything above it stays static (§7.5).
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

  /// Returns null when the prop is exactly the schema default and can be left
  /// out of the generated call.
  Emitted? _lowerProp(
    WidgetNode widget,
    WidgetSchema schema,
    ParamSchema param,
    PropValue prop,
  ) {
    switch (prop) {
      case LiteralProp(:final value):
        if (value == null && !param.required) return null;
        if (param.defaultValue != null && value == param.defaultValue) {
          return null;
        }
        _noteModelUse(param.type);
        return literals.emit(param.type, value,
            where: '${widget.type}.${param.name}',
            pageId: page.id,
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
            pageId: page.id,
            widgetId: widget.id,
          );
        }
        return Emitted.plain(refer(name));

      case WidgetProp(widget: final child):
        return _lowerWidget(child);

      case WidgetListProp(:final widgets):
        final children = [for (final w in widgets) _lowerWidget(w)];
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
