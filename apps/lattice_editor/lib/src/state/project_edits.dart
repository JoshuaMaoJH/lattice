import 'package:lattice_core/lattice_core.dart';

import 'ids.dart';
import 'tree_edits.dart';

/// Pure edits over a whole project, addressed by unit id.
///
/// Everything the editor does to a project goes through here, so the rules
/// that keep a project coherent — deleting a widget also deletes the events
/// that referred to it, disconnecting a pin also clears the bindings — live in
/// one place rather than being re-implemented per panel.
class ProjectEdits {
  const ProjectEdits._();

  static Project replaceUnit(Project project, WidgetUnit unit) =>
      switch (unit) {
        final Page page => project.copyWith(
            pages: [
              for (final p in project.pages)
                if (p.id == page.id) page else p,
            ],
          ),
        final Prefab prefab => project.copyWith(
            prefabs: [
              for (final p in project.prefabs)
                if (p.id == prefab.id) prefab else p,
            ],
          ),
        _ => project,
      };

  static WidgetUnit? unit(Project project, String unitId) {
    for (final unit in project.units) {
      if (unit.id == unitId) return unit;
    }
    return null;
  }

  static WidgetUnit _withHierarchy(WidgetUnit unit, WidgetNode hierarchy) =>
      switch (unit) {
        final Page page => page.copyWith(hierarchy: hierarchy),
        final Prefab prefab => prefab.copyWith(hierarchy: hierarchy),
        _ => unit,
      };

  static WidgetUnit _withGraph(WidgetUnit unit, Graph graph) => switch (unit) {
        final Page page => page.copyWith(graph: graph),
        final Prefab prefab => prefab.copyWith(graph: graph),
        _ => unit,
      };

  static WidgetUnit _withLayout(
          WidgetUnit unit, Map<String, CanvasPos> layout) =>
      switch (unit) {
        final Page page => page.copyWith(layout: layout),
        final Prefab prefab => prefab.copyWith(layout: layout),
        _ => unit,
      };

  // ---------------------------------------------------------------------------
  // Hierarchy
  // ---------------------------------------------------------------------------

  /// Adds a widget of [type] under [parentId], seeded with the defaults its
  /// schema declares required — a `Text` with no `data` would be invalid the
  /// instant it appeared, which is a poor way to greet someone.
  static (Project, String) addWidget(
    Project project,
    String unitId,
    String parentId,
    String type, {
    int? index,
  }) {
    final unit = ProjectEdits.unit(project, unitId);
    if (unit == null) return (project, '');

    final id = Ids.forWidget(unit, type);
    final schema = WidgetLookup(project).lookup(type);
    final widget = WidgetNode(
      id: id,
      type: type,
      props: {
        for (final param in schema?.params ?? const <ParamSchema>[])
          if (param.required && param.kind == ParamKind.value)
            param.name: LiteralProp(_placeholderFor(param, type)),
      },
    );

    return (
      replaceUnit(
        project,
        _withHierarchy(
          unit,
          TreeEdits.insert(unit.hierarchy, parentId, widget, index: index),
        ),
      ),
      id,
    );
  }

  static Object? _placeholderFor(ParamSchema param, String widgetType) {
    if (param.defaultValue != null) return param.defaultValue;
    return switch (param.type) {
      PrimitiveType(kind: PrimitiveKind.string$) => widgetType,
      PrimitiveType(kind: PrimitiveKind.bool$) => false,
      PrimitiveType(kind: PrimitiveKind.int$) => 0,
      PrimitiveType(kind: PrimitiveKind.double$) => 0,
      PrimitiveType(kind: PrimitiveKind.edgeInsets$) => 8,
      PrimitiveType(kind: PrimitiveKind.iconData$) => 'star',
      EnumType(:final values) => values.first,
      _ => null,
    };
  }

  /// Deletes a widget, along with the graph nodes and bindings that only made
  /// sense while it existed.
  static Project removeWidget(Project project, String unitId, String widgetId) {
    final unit = ProjectEdits.unit(project, unitId);
    if (unit == null || unit.hierarchy.id == widgetId) return project;

    final subtree = TreeEdits.find(unit.hierarchy, widgetId);
    if (subtree == null) return project;
    final removedIds = TreeEdits.idsIn(subtree);

    final hierarchy = TreeEdits.remove(unit.hierarchy, widgetId);
    if (hierarchy == null) return project;

    // Event nodes name a widget; without it they cannot compile.
    final orphanedEvents = {
      for (final node in unit.graph.ofType('Event'))
        if (removedIds.contains(node.get<String>('widget'))) node.id,
    };

    return replaceUnit(
      project,
      _withGraph(
        _withHierarchy(unit, hierarchy),
        _removeNodes(unit.graph, orphanedEvents),
      ),
    );
  }

  static Project moveWidget(
    Project project,
    String unitId,
    String widgetId,
    String parentId, {
    int? index,
  }) {
    final unit = ProjectEdits.unit(project, unitId);
    if (unit == null) return project;
    final moved =
        TreeEdits.move(unit.hierarchy, widgetId, parentId, index: index);
    if (moved == null) return project;
    return replaceUnit(project, _withHierarchy(unit, moved));
  }

  static Project setProp(
    Project project,
    String unitId,
    String widgetId,
    String name,
    PropValue? value,
  ) {
    final unit = ProjectEdits.unit(project, unitId);
    if (unit == null) return project;
    return replaceUnit(
      project,
      _withHierarchy(
        unit,
        TreeEdits.setProp(unit.hierarchy, widgetId, name, value),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Graph
  // ---------------------------------------------------------------------------

  static (Project, String) addNode(
    Project project,
    String unitId,
    String type,
    CanvasPos position, {
    Map<String, Object?> config = const {},
  }) {
    final unit = ProjectEdits.unit(project, unitId);
    if (unit == null) return (project, '');

    final id = Ids.forNode(unit, type);
    final node = GraphNode(
        id: id, type: type, config: {..._defaultConfigFor(type), ...config});

    final graph =
        Graph(nodes: [...unit.graph.nodes, node], edges: unit.graph.edges);
    return (
      replaceUnit(
        project,
        _withLayout(_withGraph(unit, graph), {...unit.layout, id: position}),
      ),
      id,
    );
  }

  /// Config a new node needs to be well-formed the moment it is dropped.
  static Map<String, Object?> _defaultConfigFor(String type) => switch (type) {
        'Signal' => {'dartType': 'int', 'init': 0},
        'Const' => {'dartType': 'String', 'value': ''},
        'Format' => {'template': '{0}'},
        'UpdateSignal' => {'fn': '(x) => x'},
        'Computed' => {
            'dartType': 'String',
            'expr': "''",
            'inputs': <String, Object?>{}
          },
        'DartCode' => {
            'dartType': 'String',
            'body': "return '';",
            'inputs': <String, Object?>{},
          },
        _ => const {},
      };

  static Project removeNode(Project project, String unitId, String nodeId) {
    final unit = ProjectEdits.unit(project, unitId);
    if (unit == null) return project;

    final layout = {...unit.layout}..remove(nodeId);
    final withoutNode = replaceUnit(
      project,
      _withLayout(_withGraph(unit, _removeNodes(unit.graph, {nodeId})), layout),
    );
    // A binding to a pin that no longer exists would be an error the user did
    // not make, so it goes with the node.
    return _clearBindingsTo(withoutNode, unitId, {nodeId});
  }

  static Graph _removeNodes(Graph graph, Set<String> nodeIds) {
    if (nodeIds.isEmpty) return graph;
    return Graph(
      nodes: [
        for (final node in graph.nodes)
          if (!nodeIds.contains(node.id)) node,
      ],
      edges: [
        for (final edge in graph.edges)
          if (!nodeIds.contains(edge.from.nodeId) &&
              !nodeIds.contains(edge.to.nodeId))
            edge,
      ],
    );
  }

  static Project _clearBindingsTo(
    Project project,
    String unitId,
    Set<String> nodeIds,
  ) {
    final unit = ProjectEdits.unit(project, unitId);
    if (unit == null) return project;

    WidgetNode strip(WidgetNode widget) => widget.copyWith(
          props: {
            for (final entry in widget.props.entries)
              if (!(entry.value is BindProp &&
                      nodeIds.contains(
                        (entry.value as BindProp).source.nodeId,
                      )) &&
                  !(entry.value is EventProp &&
                      nodeIds.contains((entry.value as EventProp).eventNodeId)))
                entry.key: switch (entry.value) {
                  WidgetProp(:final widget) => WidgetProp(strip(widget)),
                  WidgetListProp(:final widgets) =>
                    WidgetListProp([for (final w in widgets) strip(w)]),
                  final other => other,
                },
          },
          children: [for (final child in widget.children) strip(child)],
        );

    return replaceUnit(project, _withHierarchy(unit, strip(unit.hierarchy)));
  }

  static Project moveNode(
    Project project,
    String unitId,
    String nodeId,
    CanvasPos position,
  ) {
    final unit = ProjectEdits.unit(project, unitId);
    if (unit == null) return project;
    return replaceUnit(
      project,
      _withLayout(unit, {...unit.layout, nodeId: position}),
    );
  }

  static Project setNodeConfig(
    Project project,
    String unitId,
    String nodeId,
    String key,
    Object? value,
  ) {
    final unit = ProjectEdits.unit(project, unitId);
    final node = unit?.graph.node(nodeId);
    if (unit == null || node == null) return project;

    final config = {...node.config};
    if (value == null) {
      config.remove(key);
    } else {
      config[key] = value;
    }

    return replaceUnit(
      project,
      _withGraph(
        unit,
        Graph(
          nodes: [
            for (final n in unit.graph.nodes)
              if (n.id == nodeId)
                GraphNode(id: n.id, type: n.type, config: config)
              else
                n,
          ],
          edges: unit.graph.edges,
        ),
      ),
    );
  }

  /// Connects two pins. An input takes one edge, so any existing one is
  /// replaced rather than added to (§7.2).
  static Project connect(
    Project project,
    String unitId,
    PinRef from,
    PinRef to,
  ) {
    final unit = ProjectEdits.unit(project, unitId);
    if (unit == null) return project;
    return replaceUnit(
      project,
      _withGraph(
        unit,
        Graph(
          nodes: unit.graph.nodes,
          edges: [
            for (final edge in unit.graph.edges)
              if (edge.to != to) edge,
            Edge(from, to),
          ],
        ),
      ),
    );
  }

  static Project disconnect(Project project, String unitId, PinRef to) {
    final unit = ProjectEdits.unit(project, unitId);
    if (unit == null) return project;
    return replaceUnit(
      project,
      _withGraph(
        unit,
        Graph(
          nodes: unit.graph.nodes,
          edges: [
            for (final edge in unit.graph.edges)
              if (edge.to != to) edge,
          ],
        ),
      ),
    );
  }

  /// Wires a widget parameter to a graph output (§5, "Binding").
  static Project bindProp(
    Project project,
    String unitId,
    String widgetId,
    String param,
    PinRef source,
  ) =>
      setProp(project, unitId, widgetId, param, BindProp(source));

  /// Creates the `Event` node for a widget callback and wires the prop to it.
  static (Project, String) bindEvent(
    Project project,
    String unitId,
    String widgetId,
    String callback,
  ) {
    final unit = ProjectEdits.unit(project, unitId);
    if (unit == null) return (project, '');

    final existing = unit.graph.ofType('Event').where(
          (n) =>
              n.get<String>('widget') == widgetId &&
              n.get<String>('event') == callback,
        );
    if (existing.isNotEmpty) {
      return (
        setProp(
            project, unitId, widgetId, callback, EventProp(existing.first.id)),
        existing.first.id,
      );
    }

    final position = _freePosition(unit);
    final (withNode, id) = addNode(
      project,
      unitId,
      'Event',
      position,
      config: {'widget': widgetId, 'event': callback},
    );
    return (
      setProp(withNode, unitId, widgetId, callback, EventProp(id)),
      id,
    );
  }

  /// A spot on the canvas that is not already occupied, so a new node never
  /// lands invisibly on top of an old one.
  static CanvasPos _freePosition(WidgetUnit unit) {
    if (unit.layout.isEmpty) return const CanvasPos(120, 120);
    var maxY = 0.0;
    for (final position in unit.layout.values) {
      if (position.y > maxY) maxY = position.y;
    }
    return CanvasPos(120, maxY + 140);
  }
}
