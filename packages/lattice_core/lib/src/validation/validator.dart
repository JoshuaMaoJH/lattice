import '../model/graph.dart';
import '../model/hierarchy.dart';
import '../model/page.dart';
import '../model/pin_ref.dart';
import '../model/project.dart';
import '../schema/node_registry.dart';
import '../schema/node_schema.dart';
import '../schema/pin_schema.dart';
import '../schema/widget_registry.dart';
import '../schema/widget_schema.dart';
import '../types/lattice_type.dart';
import '../types/type_parser.dart';
import 'diagnostic.dart';
import 'scope.dart';

/// Static checks that run before every codegen and on every editor edit
/// (§7.5 step 1).
///
/// The rule of thumb: anything that would become a `dart analyze` error should
/// be caught here first, with a node id attached, so the user never has to
/// read generated code to understand what they did wrong.
class Validator {
  const Validator();

  ValidationResult validate(Project project) {
    final out = <Diagnostic>[];

    if (project.pages.isEmpty) {
      out.add(const Diagnostic.error(
        code: 'no_pages',
        message: 'The project has no pages; there is nothing to build.',
      ));
    }
    if (project.pages.where((p) => p.isHome).length > 1) {
      out.add(const Diagnostic.error(
        code: 'multiple_home_pages',
        message: 'More than one page is marked as the home page.',
      ));
    }

    final routes = <String, String>{};
    for (final page in project.pages) {
      final clash = routes[page.route];
      if (clash != null) {
        out.add(Diagnostic.error(
          code: 'duplicate_route',
          message: 'Route "${page.route}" is already used by page "$clash".',
          pageId: page.id,
        ));
      }
      routes[page.route] = page.id;
    }

    _validateModels(project, out);
    for (final page in project.pages) {
      _validatePage(project, page, out);
    }
    return ValidationResult(out);
  }

  // --------------------------------------------------------------------------

  void _validateModels(Project project, List<Diagnostic> out) {
    final seen = <String>{};
    for (final model in project.models) {
      if (!seen.add(model.name)) {
        out.add(Diagnostic.error(
          code: 'duplicate_model',
          message: 'Model "${model.name}" is declared more than once.',
        ));
      }
      for (final field in model.fields) {
        _checkTypeResolves(project, field.type, out,
            where: 'model ${model.name}.${field.name}');
      }
    }
  }

  void _checkTypeResolves(
    Project project,
    LatticeType type,
    List<Diagnostic> out, {
    required String where,
    String? pageId,
    String? nodeId,
  }) {
    switch (type) {
      case ModelType(:final name):
        if (project.model(name) == null) {
          out.add(Diagnostic.error(
            code: 'unknown_model',
            message: 'Unknown type "$name" in $where. '
                'Declare it under models/ or fix the spelling.',
            pageId: pageId,
            nodeId: nodeId,
          ));
        }
      case ListType(:final element):
        _checkTypeResolves(project, element, out,
            where: where, pageId: pageId, nodeId: nodeId);
      case NullableType(:final inner):
        _checkTypeResolves(project, inner, out,
            where: where, pageId: pageId, nodeId: nodeId);
      case FutureType(:final inner):
        _checkTypeResolves(project, inner, out,
            where: where, pageId: pageId, nodeId: nodeId);
      case MapType(:final key, :final value):
        _checkTypeResolves(project, key, out,
            where: where, pageId: pageId, nodeId: nodeId);
        _checkTypeResolves(project, value, out,
            where: where, pageId: pageId, nodeId: nodeId);
      default:
        break;
    }
  }

  void _validatePage(Project project, Page page, List<Diagnostic> out) {
    final ctx = NodeContext(graph: page.graph, page: page, project: project);
    final scopes = ScopeMap.of(page);

    _validateIds(page, out);
    _validateHierarchy(page, page.hierarchy, null, out);
    _validateControlFlow(project, page, ctx, out);
    _validateBindingsAndEvents(project, page, ctx, out);
    _validateScopes(page, ctx, scopes, out);
    _validateNodes(project, page, ctx, out);
    _validateEdges(page, ctx, out);
    _detectCycles(page, out);
  }

  /// Rules specific to the structural directives (ADR-009).
  void _validateControlFlow(
    Project project,
    Page page,
    NodeContext ctx,
    List<Diagnostic> out,
  ) {
    final parents = <String, WidgetNode>{};
    void index(WidgetNode widget) {
      for (final child in widget.children) {
        parents[child.id] = widget;
        index(child);
      }
      for (final prop in widget.props.values) {
        switch (prop) {
          case WidgetProp(:final widget):
            index(widget);
          case WidgetListProp(:final widgets):
            for (final w in widgets) {
              index(w);
            }
          default:
            break;
        }
      }
    }

    index(page.hierarchy);

    for (final widget in page.hierarchy.descendantsAndSelf) {
      if (widget.type != 'ForEach' && widget.type != 'If') continue;

      if (widget.children.isEmpty) {
        out.add(Diagnostic.error(
          code: 'missing_template',
          message: widget.type == 'ForEach'
              ? 'ForEach needs one child to use as the item template.'
              : 'If needs one child to show when the condition holds.',
          pageId: page.id,
          widgetId: widget.id,
        ));
      }

      final parent = parents[widget.id];
      if (widget.type == 'ForEach') {
        // A repeat expands to a collection-`for`, which only exists inside a
        // list. Anywhere else there is no syntax for "zero or many widgets".
        final parentSchema =
            parent == null ? null : WidgetRegistry.lookup(parent.type);
        if (parentSchema == null ||
            parentSchema.childArity != ChildArity.many) {
          out.add(Diagnostic.error(
            code: 'foreach_needs_list_parent',
            message: 'ForEach produces any number of widgets, so it must sit '
                'directly inside something that takes a list of children '
                '(Column, Row, ListView, Stack, Wrap) — '
                'its parent here is ${parent?.type ?? 'the page root'}.',
            pageId: page.id,
            widgetId: widget.id,
          ));
        }
        _validateItemKey(project, page, ctx, widget, out);
      }
    }
  }

  /// `itemKey` is what gives a row a stable identity across rebuilds. Without
  /// it Flutter reuses elements by position, so deleting the first row hands
  /// its internal state to the second (ADR-009). Required whenever items are
  /// distinguishable — that is, whenever they are models.
  void _validateItemKey(
    Project project,
    Page page,
    NodeContext ctx,
    WidgetNode widget,
    List<Diagnostic> out,
  ) {
    final element = ctx.forEachElementType(widget.id);
    final keyProp = widget.props['itemKey'];
    final keyField = keyProp is LiteralProp && keyProp.value is String
        ? keyProp.value! as String
        : null;

    if (element is! ModelType) {
      if (keyField != null) {
        out.add(Diagnostic.warning(
          code: 'item_key_ignored',
          message: 'itemKey names a field, but items are '
              '${element.dartName}; the value itself is used as the key.',
          pageId: page.id,
          widgetId: widget.id,
          pin: 'itemKey',
        ));
      }
      return;
    }

    if (keyField == null) {
      out.add(Diagnostic.error(
        code: 'missing_item_key',
        message: 'ForEach over ${element.dartName} needs "itemKey": the name '
            'of the field that identifies an item (for example "id"). '
            'Without it, reordering or deleting a row moves widget state to '
            'the wrong row.',
        pageId: page.id,
        widgetId: widget.id,
        pin: 'itemKey',
      ));
      return;
    }

    final model = project.model(element.name);
    if (model != null && model.field(keyField) == null) {
      out.add(Diagnostic.error(
        code: 'unknown_item_key',
        message: '${element.name} has no field "$keyField". '
            'Available: ${model.fields.map((f) => f.name).join(', ')}.',
        pageId: page.id,
        widgetId: widget.id,
        pin: 'itemKey',
      ));
    }
  }

  /// Enforces that `item` is only readable inside its own template.
  void _validateScopes(
    Page page,
    NodeContext ctx,
    ScopeMap scopes,
    List<Diagnostic> out,
  ) {
    String describe(Set<String> missing) => missing.length == 1
        ? 'the ForEach "${missing.single}"'
        : 'the ForEach templates ${missing.join(', ')}';

    for (final widget in page.hierarchy.descendantsAndSelf) {
      for (final entry in widget.props.entries) {
        final prop = entry.value;
        if (prop is! BindProp) continue;
        final missing = scopes.missingFor(widget.id, prop.source.nodeId);
        if (missing.isEmpty) continue;
        out.add(Diagnostic.error(
          code: 'item_out_of_scope',
          message: '${widget.type}.${entry.key} reads a value that only '
              'exists inside ${describe(missing)}. Move the widget into that '
              'template, or lift the value out of the loop.',
          pageId: page.id,
          widgetId: widget.id,
          nodeId: prop.source.nodeId,
          pin: entry.key,
        ));
      }
    }

    // An action chain may read `item` only if the widget that fires it is
    // itself inside the template — the generated handler captures the loop
    // variable through its parameters.
    for (final event in page.graph.ofType('Event')) {
      final widgetId = event.get<String>('widget');
      if (widgetId == null) continue;
      final available = scopes.enclosing(widgetId).toSet();

      for (final action in _actionChain(page.graph, event.id)) {
        for (final edge in page.graph.edges) {
          if (edge.to.nodeId != action) continue;
          final missing =
              scopes.scopesOf(edge.from.nodeId).difference(available);
          if (missing.isEmpty) continue;
          out.add(Diagnostic.error(
            code: 'item_out_of_scope',
            message: 'This action reads a value from ${describe(missing)}, '
                'but it is triggered by a widget outside that template.',
            pageId: page.id,
            widgetId: widgetId,
            nodeId: action,
          ));
        }
      }
    }
  }

  /// Action node ids reachable from an Event through `fire` / `next`.
  List<String> _actionChain(Graph graph, String eventNodeId) {
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

  void _validateIds(Page page, List<Diagnostic> out) {
    final widgetIds = <String>{};
    for (final widget in page.hierarchy.descendantsAndSelf) {
      if (!widgetIds.add(widget.id)) {
        out.add(Diagnostic.error(
          code: 'duplicate_widget_id',
          message: 'Widget id "${widget.id}" is used more than once.',
          pageId: page.id,
          widgetId: widget.id,
        ));
      }
    }
    final nodeIds = <String>{};
    for (final node in page.graph.nodes) {
      if (!nodeIds.add(node.id)) {
        out.add(Diagnostic.error(
          code: 'duplicate_node_id',
          message: 'Node id "${node.id}" is used more than once.',
          pageId: page.id,
          nodeId: node.id,
        ));
      }
    }
  }

  void _validateHierarchy(
    Page page,
    WidgetNode widget,
    String? parentType,
    List<Diagnostic> out,
  ) {
    final schema = WidgetRegistry.lookup(widget.type);
    if (schema == null) {
      out.add(Diagnostic.error(
        code: 'unknown_widget',
        message: '"${widget.type}" is not in the widget whitelist. '
            'Use a Dart Code node, or add it to the registry.',
        pageId: page.id,
        widgetId: widget.id,
      ));
      return;
    }

    if (schema.mustBeInside != null &&
        (parentType == null || !schema.mustBeInside!.contains(parentType))) {
      out.add(Diagnostic.error(
        code: 'illegal_parent',
        message: '${widget.type} must be a direct child of '
            '${schema.mustBeInside!.join(" / ")}, '
            'but its parent is ${parentType ?? "the page root"}.',
        pageId: page.id,
        widgetId: widget.id,
      ));
    }

    switch (schema.childArity) {
      case ChildArity.none:
        if (widget.children.isNotEmpty) {
          out.add(Diagnostic.error(
            code: 'children_not_allowed',
            message: '${widget.type} takes no children.',
            pageId: page.id,
            widgetId: widget.id,
          ));
        }
      case ChildArity.one:
        if (widget.children.length > 1) {
          out.add(Diagnostic.error(
            code: 'too_many_children',
            message: '${widget.type} takes at most one child, '
                'got ${widget.children.length}. Wrap them in a Column or Row.',
            pageId: page.id,
            widgetId: widget.id,
          ));
        }
      case ChildArity.many:
        break;
    }

    for (final entry in widget.props.entries) {
      final param = schema.param(entry.key);
      if (param == null) {
        out.add(Diagnostic.error(
          code: 'unknown_param',
          message: '${widget.type} has no parameter "${entry.key}".',
          pageId: page.id,
          widgetId: widget.id,
          pin: entry.key,
        ));
        continue;
      }
      _checkPropShape(page, widget, param, entry.value, out);
    }

    for (final param in schema.params) {
      final hasValue = widget.props.containsKey(param.name);
      final satisfiedByChild =
          param.name == schema.childrenParam && widget.children.isNotEmpty;
      if (param.required && !hasValue && !satisfiedByChild) {
        out.add(Diagnostic.error(
          code: 'missing_required_param',
          message: '${widget.type} requires "${param.name}".',
          pageId: page.id,
          widgetId: widget.id,
          pin: param.name,
        ));
      }
    }

    for (final prop in widget.props.values) {
      switch (prop) {
        case WidgetProp(:final widget):
          _validateHierarchy(page, widget, null, out);
        case WidgetListProp(:final widgets):
          for (final w in widgets) {
            _validateHierarchy(page, w, null, out);
          }
        default:
          break;
      }
    }
    for (final child in widget.children) {
      _validateHierarchy(page, child, widget.type, out);
    }
  }

  void _checkPropShape(
    Page page,
    WidgetNode widget,
    ParamSchema param,
    PropValue prop,
    List<Diagnostic> out,
  ) {
    String? problem;
    switch ((param.kind, prop)) {
      case (ParamKind.callback, EventProp()):
      case (ParamKind.callback, LiteralProp(value: null)):
      case (ParamKind.callback, ExprProp()):
        break;
      case (ParamKind.callback, _):
        problem = '"${param.name}" is a callback; wire it to an Event node.';
      case (ParamKind.widget, WidgetProp()):
      case (ParamKind.widget, LiteralProp(value: null)):
        break;
      case (ParamKind.widget, _):
        problem = '"${param.name}" expects a widget.';
      case (ParamKind.widgetList, WidgetListProp()):
      case (ParamKind.widgetList, LiteralProp(value: null)):
        break;
      case (ParamKind.widgetList, _):
        problem = '"${param.name}" expects a list of widgets.';
      case (ParamKind.value, WidgetProp()):
      case (ParamKind.value, WidgetListProp()):
        problem = '"${param.name}" expects a value, not a widget.';
      case (ParamKind.value, EventProp()):
        problem = '"${param.name}" is not a callback.';
      case (ParamKind.value, _):
        break;
    }
    if (problem != null) {
      out.add(Diagnostic.error(
        code: 'param_kind_mismatch',
        message: problem,
        pageId: page.id,
        widgetId: widget.id,
        pin: param.name,
      ));
    }
  }

  /// Checks `$bind` and `$event` props against the graph.
  void _validateBindingsAndEvents(
    Project project,
    Page page,
    NodeContext ctx,
    List<Diagnostic> out,
  ) {
    for (final widget in page.hierarchy.descendantsAndSelf) {
      final schema = WidgetRegistry.lookup(widget.type);
      if (schema == null) continue;
      for (final entry in widget.props.entries) {
        final param = schema.param(entry.key);
        if (param == null) continue;
        switch (entry.value) {
          case BindProp(:final source):
            final sourceType = _outputType(page.graph, ctx, source, out,
                pageId: page.id, widgetId: widget.id, pin: entry.key);
            if (sourceType == null) break;
            if (!sourceType.isAssignableTo(param.type)) {
              out.add(Diagnostic.error(
                code: 'type_mismatch',
                message: 'Cannot bind ${sourceType.dartName} from "$source" '
                    'to ${widget.type}.${param.name} '
                    '(${param.type.dartName}).',
                pageId: page.id,
                widgetId: widget.id,
                nodeId: source.nodeId,
                pin: param.name,
              ));
            }
          case EventProp(:final eventNodeId):
            final node = page.graph.node(eventNodeId);
            if (node == null) {
              out.add(Diagnostic.error(
                code: 'unknown_node',
                message: '${widget.type}.${param.name} refers to event node '
                    '"$eventNodeId", which does not exist.',
                pageId: page.id,
                widgetId: widget.id,
                pin: param.name,
              ));
              break;
            }
            if (node.type != 'Event') {
              out.add(Diagnostic.error(
                code: 'not_an_event_node',
                message: '"$eventNodeId" is a ${node.type}, not an Event.',
                pageId: page.id,
                widgetId: widget.id,
                nodeId: eventNodeId,
                pin: param.name,
              ));
              break;
            }
            final boundWidget = node.get<String>('widget');
            final boundEvent = node.get<String>('event');
            if (boundWidget != widget.id || boundEvent != param.name) {
              out.add(Diagnostic.error(
                code: 'event_binding_mismatch',
                message: 'Event node "$eventNodeId" is declared for '
                    '${boundWidget ?? "?"}.${boundEvent ?? "?"} but is wired to '
                    '${widget.id}.${param.name}.',
                pageId: page.id,
                widgetId: widget.id,
                nodeId: eventNodeId,
                pin: param.name,
              ));
            }
          default:
            break;
        }
      }
    }
  }

  void _validateNodes(
    Project project,
    Page page,
    NodeContext ctx,
    List<Diagnostic> out,
  ) {
    for (final node in page.graph.nodes) {
      final schema = NodeRegistry.forNode(node);
      if (schema == null) {
        out.add(Diagnostic.error(
          code: 'unknown_node_type',
          message: 'Unknown node type "${node.type}".',
          pageId: page.id,
          nodeId: node.id,
        ));
        continue;
      }

      if (node.type == 'Signal' || node.type == 'Const') {
        final spec = node.get<String>('dartType');
        if (spec == null) {
          out.add(Diagnostic.error(
            code: 'missing_config',
            message: '${node.type} node needs a "dartType".',
            pageId: page.id,
            nodeId: node.id,
          ));
        } else {
          final parsed = TypeParser.tryParse(spec);
          if (parsed == null) {
            out.add(Diagnostic.error(
              code: 'bad_type',
              message: '"$spec" is not a valid type.',
              pageId: page.id,
              nodeId: node.id,
            ));
          } else {
            _checkTypeResolves(project, parsed, out,
                where: 'node ${node.id}', pageId: page.id, nodeId: node.id);
          }
        }
      }

      if (schema.isAction) {
        final signalId = node.get<String>('signal');
        if (schema.configKeys.contains('signal')) {
          final target = signalId == null ? null : page.graph.node(signalId);
          if (target == null) {
            out.add(Diagnostic.error(
              code: 'unknown_signal',
              message: '${node.type} targets signal '
                  '"${signalId ?? "<unset>"}", which does not exist.',
              pageId: page.id,
              nodeId: node.id,
            ));
          } else if (target.type != 'Signal') {
            out.add(Diagnostic.error(
              code: 'not_a_signal',
              message: '"$signalId" is a ${target.type}, not a Signal.',
              pageId: page.id,
              nodeId: node.id,
            ));
          }
        }
      }

      if (node.type == 'Event') {
        final widgetId = node.get<String>('widget');
        final eventName = node.get<String>('event');
        final widgetSchema = ctx.widgetSchema(widgetId);
        if (widgetSchema == null) {
          out.add(Diagnostic.error(
            code: 'unknown_widget_ref',
            message: 'Event node refers to widget '
                '"${widgetId ?? "<unset>"}", which is not in this page.',
            pageId: page.id,
            nodeId: node.id,
          ));
        } else {
          final param =
              eventName == null ? null : widgetSchema.param(eventName);
          if (param == null || param.kind != ParamKind.callback) {
            out.add(Diagnostic.error(
              code: 'unknown_event',
              message: '${widgetSchema.type} has no callback '
                  '"${eventName ?? "<unset>"}".',
              pageId: page.id,
              nodeId: node.id,
            ));
          }
        }
      }

      // Required inputs must be fed.
      for (final pin in schema.inputs(node, ctx)) {
        if (!pin.required || pin.variadic) continue;
        final ref = PinRef(node.id, pin.name);
        if (page.graph.incoming(ref).isEmpty) {
          out.add(Diagnostic.error(
            code: 'unconnected_input',
            message: '${node.type}.${pin.name} is required but nothing is '
                'connected to it.',
            pageId: page.id,
            nodeId: node.id,
            pin: pin.name,
          ));
        }
      }
    }
  }

  void _validateEdges(Page page, NodeContext ctx, List<Diagnostic> out) {
    final seenTargets = <PinRef, PinRef>{};

    for (final edge in page.graph.edges) {
      final sourceType = _outputType(page.graph, ctx, edge.from, out,
          pageId: page.id, nodeId: edge.from.nodeId, pin: edge.from.pin);
      final targetInfo = _inputPin(page.graph, ctx, edge.to, out, page.id);
      if (sourceType == null || targetInfo == null) continue;

      final (targetPin, _) = targetInfo;

      final sourceKind = _outputKind(page.graph, ctx, edge.from);
      if (sourceKind != null && sourceKind != targetPin.kind) {
        out.add(Diagnostic.error(
          code: 'pin_kind_mismatch',
          message: 'Cannot connect a ${sourceKind.name} pin to an '
              '${targetPin.kind.name} pin ($edge).',
          pageId: page.id,
          nodeId: edge.to.nodeId,
          pin: edge.to.pin,
        ));
        continue;
      }

      if (targetPin.kind == PinKind.data &&
          !sourceType.isAssignableTo(targetPin.type)) {
        out.add(Diagnostic.error(
          code: 'type_mismatch',
          message: '${sourceType.dartName} from "${edge.from}" does not fit '
              '${targetPin.type.dartName} at "${edge.to}".',
          pageId: page.id,
          nodeId: edge.to.nodeId,
          pin: edge.to.pin,
        ));
      }

      // Data inputs take one edge; event outputs may fan out but an action's
      // exec pin still takes one (§7.2).
      final previous = seenTargets[edge.to];
      if (previous != null) {
        out.add(Diagnostic.error(
          code: 'multiple_inputs',
          message: 'Pin "${edge.to}" already has an incoming edge from '
              '"$previous"; an input accepts at most one.',
          pageId: page.id,
          nodeId: edge.to.nodeId,
          pin: edge.to.pin,
        ));
      } else {
        seenTargets[edge.to] = edge.from;
      }
    }
  }

  /// Depth-first cycle detection over data edges only. Event edges are
  /// imperative and may legitimately loop back to the signal they read.
  void _detectCycles(Page page, List<Diagnostic> out) {
    final dependencies = <String, Set<String>>{};
    for (final edge in page.graph.edges) {
      final from = page.graph.node(edge.from.nodeId);
      final to = page.graph.node(edge.to.nodeId);
      if (from == null || to == null) continue;
      final toSchema = NodeRegistry.forNode(to);
      if (toSchema == null) continue;
      final ctx = NodeContext(graph: page.graph, page: page);
      final pin = toSchema.input(to, ctx, edge.to.pin);
      if (pin == null || pin.kind != PinKind.data) continue;
      dependencies.putIfAbsent(to.id, () => {}).add(from.id);
    }

    const white = 0, grey = 1, black = 2;
    final colour = <String, int>{};
    final stack = <String>[];

    bool visit(String id) {
      colour[id] = grey;
      stack.add(id);
      for (final dep in dependencies[id] ?? const <String>{}) {
        final state = colour[dep] ?? white;
        if (state == grey) {
          final start = stack.indexOf(dep);
          final cycle = [...stack.sublist(start), dep].join(' -> ');
          out.add(Diagnostic.error(
            code: 'cycle',
            message: 'Data flow must be acyclic, but found: $cycle',
            pageId: page.id,
            nodeId: dep,
          ));
          return true;
        }
        if (state == white && visit(dep)) return true;
      }
      stack.removeLast();
      colour[id] = black;
      return false;
    }

    for (final node in page.graph.nodes) {
      if ((colour[node.id] ?? white) == white) {
        if (visit(node.id)) return; // one cycle report is enough to act on
      }
    }
  }

  // --------------------------------------------------------------------------

  LatticeType? _outputType(
    Graph graph,
    NodeContext ctx,
    PinRef ref,
    List<Diagnostic> out, {
    required String pageId,
    String? nodeId,
    String? widgetId,
    String? pin,
  }) {
    final node = graph.node(ref.nodeId);
    if (node == null) {
      out.add(Diagnostic.error(
        code: 'unknown_node',
        message: 'No node with id "${ref.nodeId}".',
        pageId: pageId,
        nodeId: nodeId,
        widgetId: widgetId,
        pin: pin,
      ));
      return null;
    }
    final schema = NodeRegistry.forNode(node);
    if (schema == null) return null;
    final outPin = schema.output(node, ctx, ref.pin);
    if (outPin == null) {
      out.add(Diagnostic.error(
        code: 'unknown_pin',
        message: '${node.type} has no output pin "${ref.pin}".',
        pageId: pageId,
        nodeId: ref.nodeId,
        widgetId: widgetId,
        pin: ref.pin,
      ));
      return null;
    }
    return outPin.type;
  }

  PinKind? _outputKind(Graph graph, NodeContext ctx, PinRef ref) {
    final node = graph.node(ref.nodeId);
    if (node == null) return null;
    return NodeRegistry.forNode(node)?.output(node, ctx, ref.pin)?.kind;
  }

  (PinSchema, GraphNode)? _inputPin(
    Graph graph,
    NodeContext ctx,
    PinRef ref,
    List<Diagnostic> out,
    String pageId,
  ) {
    final node = graph.node(ref.nodeId);
    if (node == null) {
      out.add(Diagnostic.error(
        code: 'unknown_node',
        message: 'No node with id "${ref.nodeId}".',
        pageId: pageId,
        nodeId: ref.nodeId,
      ));
      return null;
    }
    final schema = NodeRegistry.forNode(node);
    if (schema == null) return null;
    final pin = schema.input(node, ctx, ref.pin);
    if (pin == null) {
      out.add(Diagnostic.error(
        code: 'unknown_pin',
        message: '${node.type} has no input pin "${ref.pin}".',
        pageId: pageId,
        nodeId: ref.nodeId,
        pin: ref.pin,
      ));
      return null;
    }
    if (ref.index != null && !pin.variadic) {
      out.add(Diagnostic.error(
        code: 'not_variadic',
        message: '${node.type}.${pin.name} is not a variadic pin, '
            'so "$ref" is not addressable.',
        pageId: pageId,
        nodeId: ref.nodeId,
        pin: ref.pin,
      ));
      return null;
    }
    return (pin, node);
  }
}
