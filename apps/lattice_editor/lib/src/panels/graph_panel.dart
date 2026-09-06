import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lattice_core/lattice_core.dart';

import '../graph/folding.dart';
import '../graph/graph_painters.dart';
import '../graph/node_layout.dart';
import '../host/debug_channel.dart';
import '../state/editor_controller.dart';
import '../state/ids.dart';
import '../state/node_clipboard.dart';
import '../state/project_edits.dart';
import '../theme.dart';
import '../widgets/chrome.dart';

/// The node canvas (§7.2, R3, R4).
///
/// Self-drawn rather than borrowed, because this is the product (§9). Nodes
/// are real widgets so text, hover and hit testing come for free; the lattice
/// and the edges are painted underneath them.
class GraphPanel extends StatefulWidget {
  const GraphPanel({super.key, required this.controller, this.dataFlow});

  final EditorController controller;

  /// Live values from the preview, when one is running (R21). Null in tests
  /// and wherever no preview exists.
  final DebugChannel? dataFlow;

  @override
  State<GraphPanel> createState() => _GraphPanelState();
}

class _GraphPanelState extends State<GraphPanel> {
  static const Size _canvasSize = Size(4000, 3000);

  final TransformationController _view = TransformationController();
  final FocusNode _focus = FocusNode(debugLabel: 'graph');

  /// The pin an edge is currently being dragged from, and where the pointer is.
  FoldMap _folds = FoldMap.empty;
  PinSlot? _linkFrom;
  Offset? _linkPointer;
  String? _refusal;

  EditorController get controller => widget.controller;

  @override
  void dispose() {
    _view.dispose();
    _focus.dispose();
    super.dispose();
  }

  double get _scale => _view.value.getMaxScaleOnAxis();

  NodeContext get _context => NodeContext(
        graph: controller.activeUnit.graph,
        unit: controller.activeUnit,
        project: controller.project,
      );

  @override
  Widget build(BuildContext context) {
    final unit = controller.activeUnit;
    final pending = controller.pendingBinding;

    return Panel(
      title: 'Graph',
      // Refusals and the pending-binding hint share the header, because that
      // is where the eye already is during a binding gesture — the far corner
      // of a large canvas is not somewhere anyone looks.
      badge: _refusal != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.block,
                  size: 12,
                  color: LatticeTheme.error,
                ),
                const SizedBox(width: 5),
                Text(
                  _refusal!,
                  style: LatticeTheme.monoSmall.copyWith(
                    color: LatticeTheme.error,
                    fontSize: 10,
                  ),
                ),
              ],
            )
          : pending == null
              ? null
              : Text(
                  'binding ${pending.param}',
                  style: LatticeTheme.monoSmall.copyWith(
                    color: LatticeTheme.forType(pending.type),
                    fontSize: 10,
                  ),
                ),
      actions: [
        ToolButton(
          icon: Icons.add,
          tooltip: 'Add a node',
          onPressed: _showNodePicker,
        ),
        ToolButton(
          icon: Icons.delete_outline,
          tooltip: 'Delete the selection  (Del)',
          onPressed: controller.selectedNodes.isEmpty ? null : _deleteSelected,
        ),
        ToolButton(
          icon: Icons.folder_zip_outlined,
          tooltip: 'Fold the selection into a Subgraph',
          onPressed:
              controller.selectedNodes.length < 2 ? null : _foldSelection,
        ),
        ToolButton(
          icon: Icons.center_focus_weak,
          tooltip: 'Reset the view',
          onPressed: () => setState(() => _view.value = Matrix4.identity()),
        ),
      ],
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: LatticeTheme.canvas,
                child: InteractiveViewer(
                  transformationController: _view,
                  minScale: 0.35,
                  maxScale: 2.5,
                  boundaryMargin: const EdgeInsets.all(600),
                  // Panning is on the background only; dragging a node or a
                  // pin must not also drag the world.
                  panEnabled: _linkFrom == null,
                  scaleEnabled: _linkFrom == null,
                  onInteractionEnd: (_) => setState(() {}),
                  child: SizedBox(
                    width: _canvasSize.width,
                    height: _canvasSize.height,
                    child: _buildCanvas(unit),
                  ),
                ),
              ),
            ),
            if (unit.graph.nodes.isEmpty) _emptyHint(),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvas(WidgetUnit unit) {
    final context = _context;
    final folds = FoldMap.of(unit, context);
    _folds = folds;

    final rects = <String, Rect>{};
    final slots = <String, List<PinSlot>>{};

    for (final node in unit.graph.nodes) {
      final nodeSlots = NodeLayout.slotsFor(node, context, unit.graph);
      slots[node.id] = nodeSlots;
      final position = NodeLayout.positionOf(unit, node.id);
      final size =
          node.type == 'Subgraph' && node.get<bool>('collapsed') == true
              ? Size(NodeLayout.width,
                  NodeLayout.heightFor(folds.portsOf(node.id).length))
              : NodeLayout.sizeFor(node, nodeSlots.length);
      rects[node.id] =
          Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
    }

    return Stack(
      children: [
        // Sits inside the InteractiveViewer so a tap on empty canvas is not
        // eaten by its pan recogniser.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _clearSelection,
            // Drag on empty canvas is a marquee. It only starts here, so it
            // never competes with dragging a node.
            onPanStart: (details) => setState(() => _marquee = Rect.fromPoints(
                  details.localPosition,
                  details.localPosition,
                )),
            onPanUpdate: (details) {
              final start = _marquee;
              if (start == null) return;
              setState(() => _marquee =
                  Rect.fromPoints(start.topLeft, details.localPosition));
            },
            onPanEnd: (_) => _finishMarquee(rects),
            onPanCancel: () => setState(() => _marquee = null),
            child: CustomPaint(painter: LatticePainter(scale: _scale)),
          ),
        ),
        if (_marquee != null)
          Positioned.fromRect(
            rect: _marquee!,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: LatticeTheme.selectionFill.withValues(alpha: 0.25),
                  border: Border.all(color: LatticeTheme.selectionEdge),
                ),
              ),
            ),
          ),
        // Expanded folds and comments are regions: behind the edges, so a
        // group reads as a backdrop rather than as something in the way.
        for (final node in unit.graph.nodes)
          if (node.type == 'Subgraph' && node.get<bool>('collapsed') != true)
            Positioned(
              left: rects[node.id]!.left,
              top: rects[node.id]!.top,
              child: _FoldRegion(
                controller: controller,
                node: node,
                size: _expandedFoldSize(unit, node, rects),
                isSelected: controller.isNodeSelected(node.id),
                onDrag: (delta) => _moveFold(unit, node, delta),
                onToggle: () => _toggleFold(node),
              ),
            ),
        for (final node in unit.graph.nodes)
          if (NodeLayout.shapeOf(node.type) == NodeShape.comment)
            Positioned(
              left: rects[node.id]!.left,
              top: rects[node.id]!.top,
              child: _CommentRegion(
                controller: controller,
                node: node,
                size: rects[node.id]!.size,
                isSelected: controller.isNodeSelected(node.id),
                onDrag: (delta) => _moveNode(node.id, delta),
                onResize: (delta) => _resizeComment(node, delta),
              ),
            ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: EdgePainter(
                edges: _edgeGeometry(unit, rects, slots),
                pending: _pendingEdge(rects, slots),
              ),
            ),
          ),
        ),
        for (final node in unit.graph.nodes)
          if (NodeLayout.shapeOf(node.type) == NodeShape.reroute)
            Positioned(
              left: rects[node.id]!.left,
              top: rects[node.id]!.top,
              child: _RerouteDot(
                controller: controller,
                node: node,
                slots: slots[node.id]!,
                isSelected: controller.isNodeSelected(node.id),
                onDrag: (delta) => _moveNode(node.id, delta),
                onPinTap: _onPinTap,
              ),
            ),
        for (final node in unit.graph.nodes)
          if (node.type == 'Subgraph' && node.get<bool>('collapsed') == true)
            Positioned(
              left: rects[node.id]!.left,
              top: rects[node.id]!.top,
              child: _CollapsedFold(
                controller: controller,
                node: node,
                ports: folds.portsOf(node.id),
                isSelected: controller.isNodeSelected(node.id),
                onDrag: (delta) => _moveNode(node.id, delta),
                onToggle: () => _toggleFold(node),
              ),
            ),
        for (final node in unit.graph.nodes)
          if (NodeLayout.shapeOf(node.type) == NodeShape.card &&
              !folds.isHidden(node.id))
            Positioned(
              left: rects[node.id]!.left,
              top: rects[node.id]!.top,
              child: _NodeCard(
                observation: widget.dataFlow?.signals[node.id],
                isRecent: widget.dataFlow?.isRecent(node.id) ?? false,
                controller: controller,
                node: node,
                slots: slots[node.id]!,
                isSelected: controller.isNodeSelected(node.id),
                highlightedPins: _compatiblePins(slots[node.id]!),
                onDrag: (delta) => _moveNode(node.id, delta),
                onLinkStart: (slot, position) => setState(() {
                  _linkFrom = slot;
                  _linkPointer = position;
                }),
                onLinkUpdate: (position) =>
                    setState(() => _linkPointer = position),
                onLinkEnd: (position) => _completeLink(position, rects, slots),
                onPinTap: _onPinTap,
              ),
            ),
      ],
    );
  }

  /// The area an expanded fold covers: its members' bounds plus a margin, so
  /// the box follows the nodes rather than having to be dragged to fit them.
  Size _expandedFoldSize(
    WidgetUnit unit,
    GraphNode fold,
    Map<String, Rect> rects,
  ) {
    final origin = NodeLayout.positionOf(unit, fold.id);
    var right = origin.dx + NodeLayout.width;
    var bottom = origin.dy + NodeLayout.commentHeaderHeight + 40;

    for (final member in fold.get<List<Object?>>('members') ?? const []) {
      final rect = member is String ? rects[member] : null;
      if (rect == null) continue;
      if (rect.right + 16 > right) right = rect.right + 16;
      if (rect.bottom + 16 > bottom) bottom = rect.bottom + 16;
    }
    return Size(right - origin.dx, bottom - origin.dy);
  }

  /// Dragging an expanded fold carries its members with it — a group that
  /// leaves its contents behind is not a group.
  void _moveFold(WidgetUnit unit, GraphNode fold, Offset delta) {
    final shift = delta / _scale;
    controller.apply('Move ${fold.id}', (project) {
      var next = project;
      for (final id in [
        fold.id,
        ...(fold.get<List<Object?>>('members') ?? const []).whereType<String>(),
      ]) {
        final current = NodeLayout.positionOf(unit, id);
        final moved = NodeLayout.snap(current + shift);
        next = ProjectEdits.moveNode(
          next,
          controller.activeUnitId,
          id,
          CanvasPos(moved.dx, moved.dy),
        );
      }
      return next;
    });
  }

  void _toggleFold(GraphNode fold) {
    final collapsed = fold.get<bool>('collapsed') == true;
    controller.apply(
      collapsed ? 'Expand ${fold.id}' : 'Collapse ${fold.id}',
      (project) => ProjectEdits.setNodeConfig(
        project,
        controller.activeUnitId,
        fold.id,
        'collapsed',
        !collapsed,
      ),
    );
  }

  void _resizeComment(GraphNode node, Offset delta) {
    final width =
        (node.get<num>('width') ?? 320).toDouble() + delta.dx / _scale;
    final height =
        (node.get<num>('height') ?? 160).toDouble() + delta.dy / _scale;
    controller.apply(
      'Resize ${node.id}',
      (project) => ProjectEdits.setNodeConfig(
        ProjectEdits.setNodeConfig(
          project,
          controller.activeUnitId,
          node.id,
          'width',
          NodeLayout.snap(Offset(width, 0)).dx.clamp(
                NodeLayout.commentMinWidth,
                2000,
              ),
        ),
        controller.activeUnitId,
        node.id,
        'height',
        NodeLayout.snap(Offset(0, height)).dy.clamp(
              NodeLayout.commentMinHeight,
              2000,
            ),
      ),
    );
  }

  void _clearSelection() {
    _focus.requestFocus();
    if (controller.pendingBinding != null) controller.cancelBinding();
    controller.select(const NoSelection());
  }

  // ---------------------------------------------------------------------------
  // Edges
  // ---------------------------------------------------------------------------

  List<EdgeGeometry> _edgeGeometry(
    WidgetUnit unit,
    Map<String, Rect> rects,
    Map<String, List<PinSlot>> slots,
  ) {
    final geometry = <EdgeGeometry>[];
    for (final edge in unit.graph.edges) {
      // An edge wholly inside one closed fold is not drawn at all.
      final fromFold = _folds.foldFor(edge.from.nodeId);
      final toFold = _folds.foldFor(edge.to.nodeId);
      if (fromFold != null && fromFold == toFold) continue;

      final from = _endpoint(edge.from, rects, slots, isInput: false);
      final to = _endpoint(edge.to, rects, slots, isInput: true);
      if (from == null || to == null) continue;

      final slot = _slotFor(edge.from, slots, isInput: false);
      geometry.add(
        EdgeGeometry(
          from: from,
          to: to,
          color: LatticeTheme.forType(slot?.type ?? PrimitiveType.dynamic_),
          isEvent: slot?.kind == PinKind.event,
          isDimmed: controller.pendingBinding != null,
        ),
      );
    }
    return geometry;
  }

  EdgeGeometry? _pendingEdge(
    Map<String, Rect> rects,
    Map<String, List<PinSlot>> slots,
  ) {
    final from = _linkFrom;
    final pointer = _linkPointer;
    if (from == null || pointer == null) return null;
    final origin = _pinCentre(from.ref, rects, slots, isInput: from.isInput);
    if (origin == null) return null;
    return EdgeGeometry(
      from: from.isInput ? pointer : origin,
      to: from.isInput ? origin : pointer,
      color: LatticeTheme.forType(from.type),
      isEvent: from.kind == PinKind.event,
    );
  }

  PinSlot? _slotFor(
    PinRef ref,
    Map<String, List<PinSlot>> slots, {
    required bool isInput,
  }) {
    for (final slot in slots[ref.nodeId] ?? const <PinSlot>[]) {
      if (slot.isInput == isInput && slot.ref == ref) return slot;
    }
    return null;
  }

  Offset? _pinCentre(
    PinRef ref,
    Map<String, Rect> rects,
    Map<String, List<PinSlot>> slots, {
    required bool isInput,
  }) {
    final rect = rects[ref.nodeId];
    final nodeSlots = slots[ref.nodeId];
    if (rect == null || nodeSlots == null) return null;
    final index = nodeSlots.indexWhere(
      (s) => s.isInput == isInput && s.ref == ref,
    );
    if (index < 0) return null;
    final node = controller.activeUnit.graph.node(ref.nodeId);
    return NodeLayout.pinCenter(
      rect,
      index,
      isInput: isInput,
      shape: NodeLayout.shapeOf(node?.type ?? ''),
    );
  }

  /// Where an edge endpoint should attach, following it into a closed fold.
  Offset? _endpoint(
    PinRef ref,
    Map<String, Rect> rects,
    Map<String, List<PinSlot>> slots, {
    required bool isInput,
  }) {
    final foldId = _folds.foldFor(ref.nodeId);
    if (foldId == null) {
      return _pinCentre(ref, rects, slots, isInput: isInput);
    }
    final rect = rects[foldId];
    final index = _folds.portIndexFor(foldId, ref, isInput: isInput);
    if (rect == null || index < 0) return null;
    return NodeLayout.pinCenter(rect, index, isInput: isInput);
  }

  // ---------------------------------------------------------------------------
  // Interaction
  // ---------------------------------------------------------------------------

  /// Survives a paste so the same copy can be pasted repeatedly, and is not
  /// the system clipboard: copying a subgraph is not copying text.
  NodeClipboard? _clipboard;

  /// The rubber band, in canvas coordinates, while a drag is in progress.
  Rect? _marquee;

  /// Selects everything the band touched. Intersection rather than
  /// containment: having to fully enclose a wide node to catch it is the kind
  /// of precision nobody wants from a rubber band.
  void _finishMarquee(Map<String, Rect> rects) {
    final band = _marquee;
    setState(() => _marquee = null);
    if (band == null || band.width < 4 && band.height < 4) return;
    controller.selectNodes({
      for (final entry in rects.entries)
        if (entry.value.overlaps(band)) entry.key,
    });
  }

  void _moveNode(String nodeId, Offset delta) {
    final unit = controller.activeUnit;
    final current = NodeLayout.positionOf(unit, nodeId);
    final moved = NodeLayout.snap(current + delta / _scale);
    if (moved == current) return;
    controller.apply(
      'Move $nodeId',
      (project) => ProjectEdits.moveNode(
        project,
        controller.activeUnitId,
        nodeId,
        CanvasPos(moved.dx, moved.dy),
      ),
    );
  }

  void _completeLink(
    Offset pointer,
    Map<String, Rect> rects,
    Map<String, List<PinSlot>> slots,
  ) {
    final source = _linkFrom;
    setState(() {
      _linkFrom = null;
      _linkPointer = null;
    });
    if (source == null) return;

    final target = _pinAt(pointer, rects, slots, wantInput: !source.isInput);
    if (target == null) return;

    final from = source.isInput ? target : source;
    final to = source.isInput ? source : target;
    _connect(from, to);
  }

  /// The pin nearest [pointer], within a forgiving radius — sockets are small
  /// and a drag that lands a few pixels off still means what it looks like.
  PinSlot? _pinAt(
    Offset pointer,
    Map<String, Rect> rects,
    Map<String, List<PinSlot>> slots, {
    required bool wantInput,
  }) {
    const tolerance = 18.0;
    PinSlot? best;
    var bestDistance = tolerance;

    for (final entry in slots.entries) {
      final rect = rects[entry.key];
      if (rect == null) continue;
      for (var index = 0; index < entry.value.length; index++) {
        final slot = entry.value[index];
        if (slot.isInput != wantInput) continue;
        final centre = NodeLayout.pinCenter(rect, index, isInput: slot.isInput);
        final distance = (centre - pointer).distance;
        if (distance < bestDistance) {
          bestDistance = distance;
          best = slot;
        }
      }
    }
    return best;
  }

  void _connect(PinSlot from, PinSlot to) {
    if (from.ref.nodeId == to.ref.nodeId) {
      return _refuse('A node cannot feed itself.');
    }
    if (from.kind != to.kind) {
      return _refuse(
        'A ${from.kind.name} pin does not connect to an ${to.kind.name} pin.',
      );
    }
    if (to.kind == PinKind.data && !from.type.isAssignableTo(to.type)) {
      return _refuse(
        '${from.type.dartName} does not fit ${to.label} (${to.type.dartName}).',
      );
    }

    controller.apply(
      'Connect ${from.ref} to ${to.ref}',
      (project) => ProjectEdits.connect(
        project,
        controller.activeUnitId,
        from.ref,
        to.ref,
      ),
    );
  }

  void _onPinTap(PinSlot slot) {
    final pending = controller.pendingBinding;
    if (pending != null && !slot.isInput && slot.kind == PinKind.data) {
      final refusal = controller.completeBinding(slot.ref);
      if (refusal != null) _refuse(refusal);
      return;
    }
    if (slot.isInput) {
      // Tapping a connected input is how you take the wire off.
      final existing = controller.activeUnit.graph.incoming(slot.ref);
      if (existing.isNotEmpty) {
        controller.apply(
          'Disconnect ${slot.ref}',
          (project) => ProjectEdits.disconnect(
            project,
            controller.activeUnitId,
            slot.ref,
          ),
        );
      }
    }
    controller.select(NodeSelection(slot.ref.nodeId));
  }

  Set<PinRef> _compatiblePins(List<PinSlot> slots) {
    final pending = controller.pendingBinding;
    if (pending == null) return const {};
    return {
      for (final slot in slots)
        if (!slot.isInput &&
            slot.kind == PinKind.data &&
            slot.type.isAssignableTo(pending.type))
          slot.ref,
    };
  }

  void _refuse(String reason) {
    setState(() => _refusal = reason);
    Future<void>.delayed(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _refusal = null);
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      controller.cancelBinding();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      if (controller.selectedNodes.isNotEmpty) {
        _deleteSelected();
        return KeyEventResult.handled;
      }
    }
    final control = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (control) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.keyC:
          _copySelected();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyV:
          _paste();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyD:
          _copySelected();
          _paste();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyA:
          controller.selectNodes(
            {for (final node in controller.activeUnit.graph.nodes) node.id},
          );
          return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _deleteSelected() {
    final ids = controller.selectedNodes;
    if (ids.isEmpty) return;
    controller
      ..apply(
        ids.length == 1 ? 'Delete ${ids.first}' : 'Delete ${ids.length} nodes',
        (project) =>
            ProjectEdits.removeNodes(project, controller.activeUnitId, ids),
      )
      ..select(const NoSelection());
  }

  /// Wraps the selected nodes in a `Subgraph` (R14).
  ///
  /// The members used to be typed into the Inspector as a comma-separated list
  /// of ids — an interaction nobody wants twice. Selecting on the canvas is
  /// how a person says "these ones".
  void _foldSelection() {
    final ids = controller.selectedNodes;
    if (ids.length < 2) return;

    final unit = controller.activeUnit;
    final positions = [
      for (final id in ids)
        if (unit.layout[id] != null) unit.layout[id]!,
    ];
    // Placed above the group it folds, so expanding it does not jump.
    final left = positions
        .map((p) => p.x)
        .fold<double>(double.infinity, (a, b) => a < b ? a : b);
    final top = positions
        .map((p) => p.y)
        .fold<double>(double.infinity, (a, b) => a < b ? a : b);

    final foldId = Ids.forNode(unit, 'Subgraph');
    controller
      ..apply(
        'Fold ${ids.length} nodes',
        (project) => ProjectEdits.addNodes(
          project,
          controller.activeUnitId,
          [
            GraphNode(
              id: foldId,
              type: 'Subgraph',
              config: {
                'name': 'Group',
                'members': ids.toList(),
                'collapsed': true,
              },
            ),
          ],
          const [],
          {
            foldId: CanvasPos(
              positions.isEmpty ? 80 : left,
              positions.isEmpty ? 80 : top - 80,
            ),
          },
        ),
      )
      ..select(NodeSelection(foldId));
  }

  void _copySelected() {
    final ids = controller.selectedNodes;
    if (ids.isEmpty) return;
    setState(() {
      _clipboard = NodeClipboard.copyFrom(controller.activeUnit, ids);
    });
  }

  void _paste() {
    final clipboard = _clipboard;
    if (clipboard == null || clipboard.isEmpty) return;

    // Offset from the originals rather than dropped in the viewport centre:
    // a duplicate that lands exactly on top of its source looks like nothing
    // happened.
    final origin = controller.activeUnit.layout[clipboard.offsets.keys.first];
    final at = NodeLayout.snap(Offset(
      (origin?.x ?? 80) + NodeLayout.width * 0.4,
      (origin?.y ?? 80) + 40,
    ));

    final pasted = clipboard.paste(
      controller.activeUnit,
      CanvasPos(at.dx, at.dy),
    );
    controller
      ..apply(
        pasted.nodes.length == 1
            ? 'Paste ${pasted.nodes.first.type}'
            : 'Paste ${pasted.nodes.length} nodes',
        (project) => ProjectEdits.addNodes(
          project,
          controller.activeUnitId,
          pasted.nodes,
          pasted.edges,
          pasted.layout,
        ),
      )
      ..selectNodes({for (final node in pasted.nodes) node.id});
  }

  Future<void> _showNodePicker() async {
    final type = await showDialog<String>(
      context: context,
      builder: (context) => _NodePicker(nodes: controller.nodes),
    );
    if (type == null || !mounted) return;

    // Drop it where the user is looking, snapped to the lattice.
    final centre = NodeLayout.snap(
      _view.toScene(
        Offset(context.size!.width / 2 - 90, context.size!.height / 2 - 40),
      ),
    );

    late String id;
    controller.apply('Add $type', (project) {
      final (next, newId) = ProjectEdits.addNode(
        project,
        controller.activeUnitId,
        type,
        CanvasPos(centre.dx, centre.dy),
      );
      id = newId;
      return next;
    });
    controller.select(NodeSelection(id));
  }

  Widget _emptyHint() => Center(
        child: Text(
          'No nodes yet. Add a Signal to hold some state.',
          style: LatticeTheme.secondary,
        ),
      );
}

/// One node box.
class _NodeCard extends StatefulWidget {
  const _NodeCard({
    required this.controller,
    this.observation,
    this.isRecent = false,
    required this.node,
    required this.slots,
    required this.isSelected,
    required this.highlightedPins,
    required this.onDrag,
    required this.onLinkStart,
    required this.onLinkUpdate,
    required this.onLinkEnd,
    required this.onPinTap,
  });

  final EditorController controller;

  /// What the running app last reported for this node, if anything.
  final SignalObservation? observation;

  /// Whether it is among the last few writes, so the canvas can show *where*
  /// the data flow just went rather than only listing it.
  final bool isRecent;

  final GraphNode node;
  final List<PinSlot> slots;
  final bool isSelected;
  final Set<PinRef> highlightedPins;
  final void Function(Offset delta) onDrag;
  final void Function(PinSlot slot, Offset canvasPosition) onLinkStart;
  final void Function(Offset canvasPosition) onLinkUpdate;
  final void Function(Offset canvasPosition) onLinkEnd;
  final void Function(PinSlot slot) onPinTap;

  @override
  State<_NodeCard> createState() => _NodeCardState();
}

class _NodeCardState extends State<_NodeCard> {
  @override
  Widget build(BuildContext context) {
    final schema = widget.controller.nodes.lookup(widget.node.type);
    final problems =
        widget.controller.diagnosticsFor(nodeId: widget.node.id).toList();
    final hasError = problems.any((d) => d.isError);

    // Cards are never dimmed. An earlier version veiled the ones whose outputs
    // could not satisfy a pending binding, and anything laid over a card —
    // `Opacity` or an overlay — cost it its taps, so an incompatible pin
    // became unclickable instead of merely quiet. The highlight on compatible
    // pins already says which ones will work, and now a tap on a wrong one
    // gets an explanation instead of silence.
    return SizedBox(
      width: NodeLayout.width,
      height: NodeLayout.heightFor(widget.slots.length),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: LatticeTheme.surface,
              border: Border.all(
                color: hasError
                    ? LatticeTheme.error
                    : widget.isRecent
                        ? LatticeTheme.warning
                        : widget.isSelected
                            ? LatticeTheme.selectionEdge
                            : LatticeTheme.hairlineBright,
                width: widget.isSelected || widget.isRecent ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(4),
              boxShadow: widget.isSelected
                  ? const [
                      BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 10,
                          spreadRadius: 1),
                    ]
                  : const [BoxShadow(color: Color(0x33000000), blurRadius: 4)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(schema, problems),
                if (widget.observation != null) _liveValue(widget.observation!),
                const SizedBox(height: NodeLayout.padTop),
                for (final slot in widget.slots) _pinRow(slot),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The value the running app last reported. Monospace because it is data,
  /// not prose.
  Widget _liveValue(SignalObservation observation) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 0),
        child: Text(
          '${observation.value}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: LatticeTheme.monoSmall.copyWith(
            color: widget.isRecent
                ? LatticeTheme.warning
                : LatticeTheme.textSecondary,
          ),
        ),
      );

  Widget _header(NodeSchema? schema, List<Diagnostic> problems) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // Ctrl / Cmd adds to the set; a plain tap replaces it.
        if (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isShiftPressed) {
          widget.controller.toggleNode(widget.node.id);
        } else {
          widget.controller.select(NodeSelection(widget.node.id));
        }
      },
      onPanUpdate: (details) => widget.onDrag(details.delta),
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: Container(
          height: NodeLayout.headerHeight,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: const BoxDecoration(
            color: LatticeTheme.raised,
            borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
            border: Border(bottom: BorderSide(color: LatticeTheme.hairline)),
          ),
          child: Row(
            children: [
              Text(
                NodeLayout.glyphFor(schema?.category),
                style: LatticeTheme.monoSmall.copyWith(
                  color: LatticeTheme.textFaint,
                  fontSize: 10,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.node.type,
                  overflow: TextOverflow.ellipsis,
                  style: LatticeTheme.mono.copyWith(fontSize: 11.5),
                ),
              ),
              const Spacer(),
              if (problems.isNotEmpty)
                Tooltip(
                  message: problems.map((d) => d.message).join('\n'),
                  child: Icon(
                    problems.any((d) => d.isError)
                        ? Icons.error_outline
                        : Icons.warning_amber_outlined,
                    size: 12,
                    color: problems.any((d) => d.isError)
                        ? LatticeTheme.error
                        : LatticeTheme.warning,
                  ),
                )
              else
                Text(
                  widget.node.id,
                  style: LatticeTheme.monoSmall.copyWith(
                    fontSize: 9.5,
                    color: LatticeTheme.textFaint,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pinRow(PinSlot slot) {
    final colour = LatticeTheme.forType(slot.type);
    final isHighlighted = widget.highlightedPins.contains(slot.ref);
    final connected = slot.isInput
        ? widget.controller.activeUnit.graph.incoming(slot.ref).isNotEmpty
        : widget.controller.activeUnit.graph.outgoing(slot.ref).isNotEmpty;

    final socket = _Socket(
      key: ValueKey('pin:${slot.ref}:${slot.isInput ? 'in' : 'out'}'),
      colour: colour,
      hollow: slot.kind == PinKind.event,
      filled: connected || !slot.isPlaceholder,
      highlighted: isHighlighted,
      onTap: () => widget.onPinTap(slot),
      onDragStart: (global) => widget.onLinkStart(slot, _toCanvas(global)),
      onDragUpdate: (global) => widget.onLinkUpdate(_toCanvas(global)),
      onDragEnd: (global) => widget.onLinkEnd(_toCanvas(global)),
    );

    final label = Text(
      slot.label,
      overflow: TextOverflow.ellipsis,
      style: LatticeTheme.monoSmall.copyWith(
        fontSize: 10.5,
        color: slot.isPlaceholder
            ? LatticeTheme.textFaint
            : LatticeTheme.textSecondary,
      ),
    );

    // The socket is a 9px dot. Tapping *near* a pin unambiguously means that
    // pin, so the whole row takes the tap and only the dot starts a drag —
    // a miss used to be swallowed by the canvas and do nothing at all.
    return SizedBox(
      height: NodeLayout.rowHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onPinTap(slot),
        child: Row(
          mainAxisAlignment:
              slot.isInput ? MainAxisAlignment.start : MainAxisAlignment.end,
          children: slot.isInput
              ? [
                  Transform.translate(
                      offset: const Offset(-5, 0), child: socket),
                  Flexible(child: label),
                  if (slot.required && !connected)
                    Text(
                      ' *',
                      style: LatticeTheme.monoSmall.copyWith(
                        color: LatticeTheme.warning,
                        fontSize: 10,
                      ),
                    ),
                  const SizedBox(width: 6),
                ]
              : [
                  const SizedBox(width: 6),
                  Flexible(child: label),
                  Transform.translate(
                      offset: const Offset(5, 0), child: socket),
                ],
        ),
      ),
    );
  }

  /// Pointer position in canvas coordinates.
  ///
  /// The node card lives inside the transformed canvas, so its own local
  /// coordinates already are canvas coordinates — the enclosing
  /// `InteractiveViewer` has done the mapping.
  Offset _toCanvas(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return globalPosition;
    final local = box.globalToLocal(globalPosition);
    final origin = NodeLayout.positionOf(
      widget.controller.activeUnit,
      widget.node.id,
    );
    return origin + local;
  }
}

/// The socket itself: the smallest thing on screen that still has to be
/// grabbable, so its hit area is larger than its paint.
class _Socket extends StatefulWidget {
  const _Socket({
    super.key,
    required this.colour,
    required this.hollow,
    required this.filled,
    required this.highlighted,
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final Color colour;
  final bool hollow;
  final bool filled;
  final bool highlighted;
  final VoidCallback onTap;
  final void Function(Offset global) onDragStart;
  final void Function(Offset global) onDragUpdate;
  final void Function(Offset global) onDragEnd;

  @override
  State<_Socket> createState() => _SocketState();
}

class _SocketState extends State<_Socket> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final radius =
        NodeLayout.pinRadius * (_hovering || widget.highlighted ? 1.3 : 1);

    return MouseRegion(
      cursor: SystemMouseCursors.precise,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onPanStart: (d) => widget.onDragStart(d.globalPosition),
        onPanUpdate: (d) => widget.onDragUpdate(d.globalPosition),
        onPanEnd: (d) => widget.onDragEnd(d.globalPosition),
        child: SizedBox(
          width: 16,
          height: NodeLayout.rowHeight,
          child: Center(
            child: Container(
              width: radius * 2,
              height: radius * 2,
              decoration: BoxDecoration(
                color: widget.hollow || !widget.filled ? null : widget.colour,
                border: Border.all(color: widget.colour, width: 1.6),
                shape: widget.hollow ? BoxShape.rectangle : BoxShape.circle,
                boxShadow: widget.highlighted
                    ? [
                        BoxShadow(
                            color: widget.colour.withValues(alpha: 0.6),
                            blurRadius: 6)
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The node library, grouped the way §7.2 groups it.
class _NodePicker extends StatefulWidget {
  const _NodePicker({required this.nodes});

  /// Built-ins plus whatever the project defines (R20) — the palette should
  /// not be able to tell them apart.
  final NodeLookup nodes;

  @override
  State<_NodePicker> createState() => _NodePickerState();
}

class _NodePickerState extends State<_NodePicker> {
  String _query = '';

  static const _titles = {
    NodeCategory.state: 'State',
    NodeCategory.compute: 'Compute',
    NodeCategory.event: 'Events',
    NodeCategory.action: 'Actions',
    NodeCategory.control: 'Control',
    NodeCategory.escape: 'Escape hatch',
    NodeCategory.organize: 'Organise',
    NodeCategory.ui: 'Interface',
  };

  @override
  Widget build(BuildContext context) {
    final matches = widget.nodes.all
        .where((s) => s.type.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Dialog(
      backgroundColor: LatticeTheme.panel,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: LatticeTheme.hairlineBright),
        borderRadius: BorderRadius.circular(4),
      ),
      child: SizedBox(
        width: 460,
        height: 480,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                autofocus: true,
                style: LatticeTheme.mono,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Filter nodes',
                  hintStyle: LatticeTheme.secondary,
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const Hairline(),
            Expanded(
              child: ListView(
                children: [
                  for (final category in NodeCategory.values)
                    if (matches.any((s) => s.category == category)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                        child: Text(
                          (_titles[category] ?? category.name).toUpperCase(),
                          style: LatticeTheme.eyebrow,
                        ),
                      ),
                      for (final schema
                          in matches.where((s) => s.category == category))
                        InkWell(
                          onTap: () => Navigator.of(context).pop(schema.type),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 16,
                                  child: Text(
                                    NodeLayout.glyphFor(category),
                                    style: LatticeTheme.monoSmall,
                                  ),
                                ),
                                SizedBox(
                                  width: 130,
                                  child: Text(
                                    schema.type,
                                    style: LatticeTheme.mono,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    schema.summary,
                                    overflow: TextOverflow.ellipsis,
                                    style: LatticeTheme.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled region of the canvas (§7.2, R14).
///
/// Drawn behind the edges so it reads as a backdrop grouping what sits on it.
/// It carries no meaning to the compiler — its whole job is to let a reader of
/// a fifty-node graph see the shape of it before reading any of it.
class _CommentRegion extends StatelessWidget {
  const _CommentRegion({
    required this.controller,
    required this.node,
    required this.size,
    required this.isSelected,
    required this.onDrag,
    required this.onResize,
  });

  final EditorController controller;
  final GraphNode node;
  final Size size;
  final bool isSelected;
  final void Function(Offset delta) onDrag;
  final void Function(Offset delta) onResize;

  @override
  Widget build(BuildContext context) {
    final text = node.get<String>('text') ?? 'Comment';

    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: LatticeTheme.surface.withValues(alpha: 0.55),
                border: Border.all(
                  color: isSelected
                      ? LatticeTheme.selectionEdge
                      : LatticeTheme.hairline,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          // Only the title bar drags, so the region does not swallow clicks
          // on the nodes sitting inside it.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => controller.select(NodeSelection(node.id)),
              onPanUpdate: (details) => onDrag(details.delta),
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: Container(
                  height: NodeLayout.commentHeaderHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: LatticeTheme.raised.withValues(alpha: 0.8),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                  ),
                  child: Text(
                    text,
                    overflow: TextOverflow.ellipsis,
                    style: LatticeTheme.eyebrow.copyWith(
                      color: LatticeTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) => onResize(details.delta),
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeDownRight,
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CustomPaint(painter: const _ResizeGripPainter()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResizeGripPainter extends CustomPainter {
  const _ResizeGripPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = LatticeTheme.hairlineBright
      ..strokeWidth = 1;
    for (var offset = 4.0; offset <= 12; offset += 4) {
      canvas.drawLine(
        Offset(size.width - offset, size.height - 2),
        Offset(size.width - 2, size.height - offset),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ResizeGripPainter oldDelegate) => false;
}

/// A reroute: a dot that bends an edge and nothing more (§7.2, R14).
///
/// Both pins sit on its centre line, so a wire appears to pass through it
/// rather than to stop at it.
class _RerouteDot extends StatelessWidget {
  const _RerouteDot({
    required this.controller,
    required this.node,
    required this.slots,
    required this.isSelected,
    required this.onDrag,
    required this.onPinTap,
  });

  final EditorController controller;
  final GraphNode node;
  final List<PinSlot> slots;
  final bool isSelected;
  final void Function(Offset delta) onDrag;
  final void Function(PinSlot slot) onPinTap;

  @override
  Widget build(BuildContext context) {
    final type = slots.isEmpty ? PrimitiveType.dynamic_ : slots.first.type;
    final colour = LatticeTheme.forType(type);

    return Tooltip(
      message: '${node.id} · ${type.dartName}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => controller.select(NodeSelection(node.id)),
        onPanUpdate: (details) => onDrag(details.delta),
        child: MouseRegion(
          cursor: SystemMouseCursors.move,
          child: SizedBox(
            width: NodeLayout.rerouteSize,
            height: NodeLayout.rerouteSize,
            child: Center(
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: colour,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? LatticeTheme.selectionEdge
                        : LatticeTheme.canvas,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An expanded fold: a labelled region that its members sit on (§7.2, R14).
class _FoldRegion extends StatelessWidget {
  const _FoldRegion({
    required this.controller,
    required this.node,
    required this.size,
    required this.isSelected,
    required this.onDrag,
    required this.onToggle,
  });

  final EditorController controller;
  final GraphNode node;
  final Size size;
  final bool isSelected;
  final void Function(Offset delta) onDrag;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final name = node.get<String>('name') ?? node.id;
    final count = (node.get<List<Object?>>('members') ?? const []).length;

    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: LatticeTheme.surface.withValues(alpha: 0.4),
                border: Border.all(
                  color: isSelected
                      ? LatticeTheme.selectionEdge
                      : LatticeTheme.hairlineBright,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          // Only the title bar is interactive; the region itself must let
          // clicks through to the nodes sitting on it.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => controller.select(NodeSelection(node.id)),
              onPanUpdate: (details) => onDrag(details.delta),
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: Container(
                  height: NodeLayout.commentHeaderHeight,
                  padding: const EdgeInsets.only(left: 8, right: 2),
                  decoration: BoxDecoration(
                    color: LatticeTheme.raised.withValues(alpha: 0.9),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          style: LatticeTheme.eyebrow.copyWith(
                            color: LatticeTheme.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$count',
                        style: LatticeTheme.monoSmall.copyWith(fontSize: 9.5),
                      ),
                      const Spacer(),
                      ToolButton(
                        icon: Icons.unfold_less,
                        tooltip: 'Collapse this group',
                        onPressed: onToggle,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A collapsed fold: one box with a port per edge that crosses its boundary.
class _CollapsedFold extends StatelessWidget {
  const _CollapsedFold({
    required this.controller,
    required this.node,
    required this.ports,
    required this.isSelected,
    required this.onDrag,
    required this.onToggle,
  });

  final EditorController controller;
  final GraphNode node;
  final List<FoldPort> ports;
  final bool isSelected;
  final void Function(Offset delta) onDrag;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final name = node.get<String>('name') ?? node.id;
    final count = (node.get<List<Object?>>('members') ?? const []).length;

    return SizedBox(
      width: NodeLayout.width,
      height: NodeLayout.heightFor(ports.length),
      child: Container(
        decoration: BoxDecoration(
          color: LatticeTheme.surface,
          border: Border.all(
            color: isSelected
                ? LatticeTheme.selectionEdge
                : LatticeTheme.hairlineBright,
            width: isSelected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => controller.select(NodeSelection(node.id)),
              onPanUpdate: (details) => onDrag(details.delta),
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: Container(
                  height: NodeLayout.headerHeight,
                  padding: const EdgeInsets.only(left: 7, right: 2),
                  decoration: const BoxDecoration(
                    color: LatticeTheme.raised,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(3)),
                    border: Border(
                      bottom: BorderSide(color: LatticeTheme.hairline),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        NodeLayout.glyphFor(NodeCategory.organize),
                        style: LatticeTheme.monoSmall.copyWith(
                          color: LatticeTheme.textFaint,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          style: LatticeTheme.mono.copyWith(fontSize: 11.5),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$count',
                        style: LatticeTheme.monoSmall.copyWith(fontSize: 9.5),
                      ),
                      const Spacer(),
                      ToolButton(
                        icon: Icons.unfold_more,
                        tooltip: 'Expand this group',
                        onPressed: onToggle,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: NodeLayout.padTop),
            for (final port in ports) _portRow(port),
          ],
        ),
      ),
    );
  }

  Widget _portRow(FoldPort port) {
    final colour = LatticeTheme.forType(port.type);
    final dot = Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: port.kind == PinKind.event ? null : colour,
        border: Border.all(color: colour, width: 1.6),
        shape:
            port.kind == PinKind.event ? BoxShape.rectangle : BoxShape.circle,
      ),
    );
    final label = Text(
      port.label,
      overflow: TextOverflow.ellipsis,
      style: LatticeTheme.monoSmall.copyWith(
        fontSize: 10.5,
        color: LatticeTheme.textFaint,
      ),
    );

    return SizedBox(
      height: NodeLayout.rowHeight,
      child: Row(
        mainAxisAlignment:
            port.isInput ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: port.isInput
            ? [
                Transform.translate(offset: const Offset(-4, 0), child: dot),
                const SizedBox(width: 4),
                Flexible(child: label),
                const SizedBox(width: 6),
              ]
            : [
                const SizedBox(width: 6),
                Flexible(child: label),
                const SizedBox(width: 4),
                Transform.translate(offset: const Offset(4, 0), child: dot),
              ],
      ),
    );
  }
}
