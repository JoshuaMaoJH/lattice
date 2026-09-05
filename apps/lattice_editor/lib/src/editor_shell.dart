import 'package:flutter/material.dart' hide Page;
import 'package:flutter/services.dart';
import 'package:lattice_core/lattice_core.dart';

import 'host/editor_host.dart';
import 'panels/diagnostics_panel.dart';
import 'panels/graph_panel.dart';
import 'panels/hierarchy_panel.dart';
import 'panels/inspector_panel.dart';
import 'panels/preview_panel.dart';
import 'state/editor_controller.dart';
import 'theme.dart';
import 'widgets/chrome.dart';

/// The four panels, plus the strip that ties them together (§6).
///
/// The arrangement is a selection chain read left to right: pick a widget in
/// the Hierarchy, edit it in the Inspector beneath, see what drives it in the
/// Graph, and see what it compiles to on the right. Hierarchy and Inspector
/// are stacked rather than placed opposite each other because one always
/// follows from the other.
class EditorShell extends StatefulWidget {
  const EditorShell({
    super.key,
    required this.controller,
    required this.host,
  });

  final EditorController controller;
  final EditorHost host;

  @override
  State<EditorShell> createState() => _EditorShellState();
}

class _EditorShellState extends State<EditorShell> {
  double _railWidth = 300;
  double _previewWidth = 440;
  double _problemsHeight = 150;
  double _hierarchyFraction = 0.45;

  String? _toast;

  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            controller.undo,
        const SingleActivator(LogicalKeyboardKey.keyZ,
            control: true, shift: true): controller.redo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true):
            controller.redo,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: LatticeTheme.canvas,
          body: Column(
            children: [
              _Toolbar(
                controller: controller,
                host: widget.host,
                onSave: _save,
                onBuild: _build,
                onExport: _export,
              ),
              const Hairline(),
              Expanded(child: _body()),
              if (_toast != null) _toastBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() => Row(
        children: [
          SizedBox(width: _railWidth, child: _leftRail()),
          SplitHandle(
            axis: Axis.horizontal,
            onDrag: (delta) => setState(
              () => _railWidth = (_railWidth + delta).clamp(220.0, 520.0),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: GraphPanel(controller: controller)),
                      SplitHandle(
                        axis: Axis.horizontal,
                        onDrag: (delta) => setState(
                          () => _previewWidth =
                              (_previewWidth - delta).clamp(280.0, 900.0),
                        ),
                      ),
                      SizedBox(
                        width: _previewWidth,
                        child: PreviewPanel(
                          controller: controller,
                          host: widget.host,
                        ),
                      ),
                    ],
                  ),
                ),
                SplitHandle(
                  axis: Axis.vertical,
                  onDrag: (delta) => setState(
                    () => _problemsHeight =
                        (_problemsHeight - delta).clamp(60.0, 400.0),
                  ),
                ),
                SizedBox(
                  height: _problemsHeight,
                  child: DiagnosticsPanel(controller: controller),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _leftRail() => LayoutBuilder(
        builder: (context, constraints) {
          final hierarchyHeight = constraints.maxHeight * _hierarchyFraction;
          return Column(
            children: [
              SizedBox(
                height: hierarchyHeight,
                child: HierarchyPanel(controller: controller),
              ),
              SplitHandle(
                axis: Axis.vertical,
                onDrag: (delta) => setState(() {
                  _hierarchyFraction =
                      ((hierarchyHeight + delta) / constraints.maxHeight)
                          .clamp(0.2, 0.8);
                }),
              ),
              Expanded(child: InspectorPanel(controller: controller)),
            ],
          );
        },
      );

  Widget _toastBar() => Container(
        width: double.infinity,
        color: LatticeTheme.raised,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            Expanded(child: Text(_toast!, style: LatticeTheme.secondary)),
            ToolButton(
              icon: Icons.close,
              tooltip: 'Dismiss',
              onPressed: () => setState(() => _toast = null),
            ),
          ],
        ),
      );

  void _say(String message) {
    setState(() => _toast = message);
    Future<void>.delayed(const Duration(seconds: 6), () {
      if (mounted && _toast == message) setState(() => _toast = null);
    });
  }

  Future<void> _save() async {
    final root = controller.projectRoot;
    if (root == null || !widget.host.canOpenProjects) {
      _say(
          'Saving needs a project on disk. You are in ${widget.host.description}.');
      return;
    }
    try {
      await widget.host.save(controller.project, root);
      controller.markSaved();
      _say('Saved to $root');
    } on Object catch (error) {
      _say('Could not save: $error');
    }
  }

  Future<void> _build() async {
    final root = controller.projectRoot;
    if (root == null || !widget.host.canOpenProjects) {
      _say('Building writes files, which needs the desktop editor.');
      return;
    }
    if (!controller.generated.isSuccess) {
      _say(
          'Fix the errors in Problems first — nothing is generated until then.');
      return;
    }
    try {
      final output = await widget.host.build(controller.project, root);
      _say(
          'Generated ${controller.generated.files.length} file(s) into $output');
    } on Object catch (error) {
      _say('Build failed: $error');
    }
  }

  Future<void> _export() async {
    final root = controller.projectRoot;
    if (root == null || !widget.host.canOpenProjects) {
      _say(
          'Exporting writes a standalone project, which needs the desktop editor.');
      return;
    }
    try {
      final destination = '$root/export';
      await widget.host.export(controller.project, root, destination);
      _say('Exported to $destination — it builds without Lattice.');
    } on Object catch (error) {
      _say('Export failed: $error');
    }
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.host,
    required this.onSave,
    required this.onBuild,
    required this.onExport,
  });

  final EditorController controller;
  final EditorHost host;
  final VoidCallback onSave;
  final VoidCallback onBuild;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      color: LatticeTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Text('LATTICE', style: LatticeTheme.eyebrow),
          const SizedBox(width: 12),
          Text(
            controller.project.config.appName,
            style: LatticeTheme.title,
          ),
          if (controller.isDirty)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                '•',
                style: LatticeTheme.body.copyWith(color: LatticeTheme.warning),
              ),
            ),
          const SizedBox(width: 20),
          Expanded(child: _UnitTabs(controller: controller)),
          ToolButton(
            icon: Icons.undo,
            tooltip: controller.undoLabel == null
                ? 'Nothing to undo'
                : 'Undo ${controller.undoLabel}',
            onPressed: controller.canUndo ? controller.undo : null,
          ),
          ToolButton(
            icon: Icons.redo,
            tooltip: 'Redo',
            onPressed: controller.canRedo ? controller.redo : null,
          ),
          const SizedBox(width: 8),
          ToolButton(
            icon: Icons.save_outlined,
            tooltip: 'Save the project',
            onPressed: onSave,
          ),
          ToolButton(
            icon: Icons.construction_outlined,
            tooltip: 'Generate the Flutter project',
            onPressed: onBuild,
          ),
          ToolButton(
            icon: Icons.ios_share,
            tooltip: 'Export a standalone project',
            onPressed: onExport,
          ),
        ],
      ),
    );
  }
}

/// One tab per page and prefab. Prefabs are marked but not separated — they
/// are edited exactly like a page (R9).
class _UnitTabs extends StatelessWidget {
  const _UnitTabs({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) => ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final unit in controller.project.units)
            _Tab(
              label: unit.name,
              detail: unit is Prefab ? 'prefab' : (unit as Page).route,
              isActive: unit.id == controller.activeUnitId,
              onTap: () => controller.openUnit(unit.id),
            ),
        ],
      );
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.detail,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final String detail;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color:
                    isActive ? LatticeTheme.selectionEdge : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Text(
                label,
                style: LatticeTheme.body.copyWith(
                  color: isActive
                      ? LatticeTheme.textPrimary
                      : LatticeTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              Text(detail,
                  style: LatticeTheme.monoSmall.copyWith(fontSize: 10)),
            ],
          ),
        ),
      );
}
