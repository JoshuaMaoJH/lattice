import 'package:flutter/material.dart';
import 'package:lattice_core/lattice_core.dart';

import '../state/editor_controller.dart';
import '../state/project_edits.dart';
import '../state/tree_edits.dart';
import '../theme.dart';
import '../widgets/chrome.dart';

/// The widget tree (§7.1, R1).
///
/// Rows are flat and dense on purpose: this is a structural view, and a tree
/// reads fastest when the only ornament is the indent. Anything wrong with a
/// row — an `Expanded` outside a `Flex`, a missing required parameter — shows
/// as a red underline on the row itself rather than only in the problems
/// strip, because that is where the user is looking.
class HierarchyPanel extends StatefulWidget {
  const HierarchyPanel({super.key, required this.controller});

  final EditorController controller;

  @override
  State<HierarchyPanel> createState() => _HierarchyPanelState();
}

class _HierarchyPanelState extends State<HierarchyPanel> {
  final Set<String> _collapsed = {};
  String? _dragging;
  _DropTarget? _dropTarget;

  EditorController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final unit = controller.activeUnit;
    final rows = <_Row>[];
    _flatten(unit.hierarchy, 0, null, rows);

    return Panel(
      title: 'Hierarchy',
      actions: [
        ToolButton(
          icon: Icons.add,
          tooltip: 'Add a widget inside the selection',
          onPressed: _selectedWidgetId == null ? null : _showAddMenu,
        ),
        ToolButton(
          icon: Icons.delete_outline,
          tooltip: 'Delete the selected widget',
          onPressed: _canDelete ? _deleteSelected : null,
        ),
      ],
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: rows.length,
        itemBuilder: (context, index) => _buildRow(rows[index]),
      ),
    );
  }

  String? get _selectedWidgetId => switch (controller.selection) {
        WidgetSelection(:final widgetId) => widgetId,
        _ => null,
      };

  bool get _canDelete {
    final id = _selectedWidgetId;
    return id != null && id != controller.activeUnit.hierarchy.id;
  }

  void _flatten(
      WidgetNode widget, int depth, String? propName, List<_Row> out) {
    final schema = WidgetLookup(controller.project).lookup(widget.type);
    final nested = <(String?, WidgetNode)>[
      for (final entry in widget.props.entries)
        ...switch (entry.value) {
          WidgetProp(:final widget) => [(entry.key, widget)],
          WidgetListProp(:final widgets) => [
              for (final w in widgets) (entry.key, w),
            ],
          _ => const <(String?, WidgetNode)>[],
        },
      for (final child in widget.children) (null, child),
    ];

    out.add(
      _Row(
        widget: widget,
        depth: depth,
        propName: propName,
        schema: schema,
        hasChildren: nested.isNotEmpty,
      ),
    );

    if (_collapsed.contains(widget.id)) return;
    for (final (name, child) in nested) {
      _flatten(child, depth + 1, name, out);
    }
  }

  Widget _buildRow(_Row row) {
    final isSelected = _selectedWidgetId == row.widget.id;
    final problems =
        controller.diagnosticsFor(widgetId: row.widget.id).toList();
    final hasError = problems.any((d) => d.isError);
    final isDropTarget = _dropTarget?.widgetId == row.widget.id;

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        final canAccept = _canDrop(details.data, row);
        if (canAccept) {
          setState(() => _dropTarget = _DropTarget(row.widget.id));
        }
        return canAccept;
      },
      onLeave: (_) => setState(() => _dropTarget = null),
      onAcceptWithDetails: (details) {
        setState(() => _dropTarget = null);
        controller.apply(
          'Move ${details.data}',
          (project) => ProjectEdits.moveWidget(
            project,
            controller.activeUnitId,
            details.data,
            row.widget.id,
          ),
        );
      },
      builder: (context, candidate, rejected) {
        final content = _rowContent(row, isSelected, hasError, problems);
        return Draggable<String>(
          data: row.widget.id,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: _dragFeedback(row),
          onDragStarted: () => setState(() => _dragging = row.widget.id),
          onDragEnd: (_) => setState(() {
            _dragging = null;
            _dropTarget = null;
          }),
          childWhenDragging: Opacity(opacity: 0.35, child: content),
          child: Container(
            decoration: isDropTarget
                ? const BoxDecoration(
                    color: LatticeTheme.selectionFill,
                    border: Border(
                      left: BorderSide(
                          color: LatticeTheme.selectionEdge, width: 2),
                    ),
                  )
                : null,
            child: content,
          ),
        );
      },
    );
  }

  bool _canDrop(String draggedId, _Row row) {
    if (draggedId == row.widget.id) return false;
    if (!(row.schema?.acceptsChildren ?? false)) return false;
    final dragged = TreeEdits.find(controller.activeUnit.hierarchy, draggedId);
    // A node cannot become a descendant of itself.
    return dragged == null || !TreeEdits.contains(dragged, row.widget.id);
  }

  Widget _dragFeedback(_Row row) => Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: LatticeTheme.raised,
            border: Border.all(color: LatticeTheme.selectionEdge),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(row.widget.type, style: LatticeTheme.mono),
        ),
      );

  Widget _rowContent(
    _Row row,
    bool isSelected,
    bool hasError,
    List<Diagnostic> problems,
  ) {
    final collapsed = _collapsed.contains(row.widget.id);
    return InkWell(
      onTap: () => controller.select(WidgetSelection(row.widget.id)),
      child: Container(
        height: LatticeTheme.rowHeight,
        padding: EdgeInsets.only(left: 4 + row.depth * 12.0, right: 8),
        color:
            isSelected && _dragging == null ? LatticeTheme.selectionFill : null,
        child: Row(
          children: [
            SizedBox(
              width: 14,
              child: row.hasChildren
                  ? InkWell(
                      onTap: () => setState(() {
                        collapsed
                            ? _collapsed.remove(row.widget.id)
                            : _collapsed.add(row.widget.id);
                      }),
                      child: Icon(
                        collapsed
                            ? Icons.chevron_right
                            : Icons.keyboard_arrow_down,
                        size: 14,
                        color: LatticeTheme.textFaint,
                      ),
                    )
                  : null,
            ),
            // The prop a nested widget fills, e.g. AppBar.title — otherwise a
            // reader cannot tell it from a child.
            if (row.propName != null) ...[
              Text('${row.propName}:', style: LatticeTheme.monoSmall),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                row.widget.type,
                overflow: TextOverflow.ellipsis,
                style: LatticeTheme.mono.copyWith(
                  color: row.schema == null
                      ? LatticeTheme.error
                      : LatticeTheme.textPrimary,
                  decoration: hasError ? TextDecoration.underline : null,
                  decorationColor: LatticeTheme.error,
                  decorationStyle: TextDecorationStyle.wavy,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              row.widget.id,
              style: LatticeTheme.monoSmall.copyWith(
                color: LatticeTheme.textFaint,
                fontSize: 10,
              ),
            ),
            if (problems.isNotEmpty) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: problems.map((d) => d.message).join('\n'),
                child: Icon(
                  hasError ? Icons.error_outline : Icons.warning_amber_outlined,
                  size: 13,
                  color: hasError ? LatticeTheme.error : LatticeTheme.warning,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _deleteSelected() {
    final id = _selectedWidgetId;
    if (id == null) return;
    controller
      ..apply(
        'Delete $id',
        (project) =>
            ProjectEdits.removeWidget(project, controller.activeUnitId, id),
      )
      ..select(const NoSelection());
  }

  Future<void> _showAddMenu() async {
    final parentId = _selectedWidgetId;
    if (parentId == null) return;

    final schema =
        WidgetLookup(controller.project).lookup(_selectedWidget!.type);
    if (schema == null) return;

    if (!schema.acceptsChildren) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${schema.type} takes no children.'),
          behavior: SnackBarBehavior.floating,
          width: 320,
        ),
      );
      return;
    }

    final type = await showDialog<String>(
      context: context,
      builder: (context) => _WidgetPicker(project: controller.project),
    );
    if (type == null || !mounted) return;

    late String newId;
    controller.apply('Add $type', (project) {
      final (next, id) = ProjectEdits.addWidget(
        project,
        controller.activeUnitId,
        parentId,
        type,
      );
      newId = id;
      return next;
    });
    controller.select(WidgetSelection(newId));
  }

  WidgetNode? get _selectedWidget {
    final id = _selectedWidgetId;
    if (id == null) return null;
    return TreeEdits.find(controller.activeUnit.hierarchy, id);
  }
}

final class _Row {
  const _Row({
    required this.widget,
    required this.depth,
    required this.propName,
    required this.schema,
    required this.hasChildren,
  });

  final WidgetNode widget;
  final int depth;
  final String? propName;
  final WidgetSchema? schema;
  final bool hasChildren;
}

final class _DropTarget {
  const _DropTarget(this.widgetId);

  final String widgetId;
}

/// The whitelist, grouped the way §7.1 groups it, with prefabs alongside —
/// a prefab should not feel like a second-class widget (R9).
class _WidgetPicker extends StatefulWidget {
  const _WidgetPicker({required this.project});

  final Project project;

  @override
  State<_WidgetPicker> createState() => _WidgetPickerState();
}

class _WidgetPickerState extends State<_WidgetPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final lookup = WidgetLookup(widget.project);
    final all = <WidgetSchema>[
      ...WidgetRegistry.all,
      for (final prefab in widget.project.prefabs)
        WidgetLookup.schemaFor(prefab),
    ];
    final matches = all
        .where((s) => s.type.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Dialog(
      backgroundColor: LatticeTheme.panel,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: LatticeTheme.hairlineBright),
        borderRadius: BorderRadius.circular(4),
      ),
      child: SizedBox(
        width: 420,
        height: 460,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                autofocus: true,
                style: LatticeTheme.mono,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Filter widgets',
                  hintStyle: LatticeTheme.secondary,
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const Hairline(),
            Expanded(
              child: ListView.builder(
                itemCount: matches.length,
                itemBuilder: (context, index) {
                  final schema = matches[index];
                  final isPrefab = lookup.isPrefab(schema.type);
                  return InkWell(
                    onTap: () => Navigator.of(context).pop(schema.type),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 150,
                            child: Text(schema.type, style: LatticeTheme.mono),
                          ),
                          if (isPrefab)
                            Text('prefab', style: LatticeTheme.monoSmall)
                          else
                            Text(
                              schema.category.name,
                              style: LatticeTheme.monoSmall,
                            ),
                          const SizedBox(width: 10),
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
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
