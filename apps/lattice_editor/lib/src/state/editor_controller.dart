import 'package:flutter/foundation.dart';
import 'package:lattice_codegen/lattice_codegen.dart';
import 'package:lattice_core/lattice_core.dart';

import 'project_edits.dart';

/// What the user currently has selected. The Inspector renders off this, and
/// so does the Graph's highlight, so a widget and its pins stay in step.
sealed class Selection {
  const Selection();
}

final class NoSelection extends Selection {
  const NoSelection();
}

final class WidgetSelection extends Selection {
  const WidgetSelection(this.widgetId);

  final String widgetId;

  @override
  bool operator ==(Object other) =>
      other is WidgetSelection && other.widgetId == widgetId;

  @override
  int get hashCode => widgetId.hashCode;
}

final class NodeSelection extends Selection {
  const NodeSelection(this.nodeId);

  final String nodeId;

  @override
  bool operator ==(Object other) =>
      other is NodeSelection && other.nodeId == nodeId;

  @override
  int get hashCode => nodeId.hashCode;
}

/// A binding the user has started but not finished: they pressed "⚡" on a
/// parameter and the Graph is now waiting for them to pick an output pin.
final class PendingBinding {
  const PendingBinding(this.widgetId, this.param, this.type);

  final String widgetId;
  final String param;
  final LatticeType type;
}

/// The editor's single source of truth.
///
/// Undo is snapshot-based: an edit pushes the previous project onto a stack.
/// A project is a few hundred kilobytes of immutable objects that share most
/// of their structure, so copying is cheap — and it means no operation needs a
/// hand-written inverse, which is where editors usually grow their subtlest
/// bugs.
class EditorController extends ChangeNotifier {
  EditorController({required Project project, String? projectRoot})
      : _project = project,
        _projectRoot = projectRoot,
        _activeUnitId = project.units.isEmpty ? '' : project.units.first.id;

  Project _project;
  String? _projectRoot;
  String _activeUnitId;
  Selection _selection = const NoSelection();
  PendingBinding? _pendingBinding;
  bool _isDirty = false;

  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];

  static const _historyLimit = 100;

  ValidationResult? _diagnosticsCache;
  GenerationResult? _generatedCache;

  Project get project => _project;

  /// Node kinds available here: the built-in library plus whatever this
  /// project defines for itself (R20). Rebuilt on every read because a
  /// project edit can add a definition.
  NodeLookup get nodes => NodeLookup(_project);
  String? get projectRoot => _projectRoot;
  Selection get selection => _selection;
  PendingBinding? get pendingBinding => _pendingBinding;
  bool get isDirty => _isDirty;

  String get activeUnitId => _activeUnitId;

  WidgetUnit get activeUnit =>
      ProjectEdits.unit(_project, _activeUnitId) ?? _project.units.first;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  String? get undoLabel => _undo.isEmpty ? null : _undo.last.label;

  /// Validation of the whole project, recomputed once per change.
  ValidationResult get diagnostics =>
      _diagnosticsCache ??= const Validator().validate(_project);

  /// Generated sources, recomputed once per change. The Preview panel reads
  /// this; so does the Build action.
  GenerationResult get generated =>
      _generatedCache ??= const LatticeGenerator().generate(_project);

  /// Diagnostics attached to one widget or node, for inline highlighting.
  Iterable<Diagnostic> diagnosticsFor({String? widgetId, String? nodeId}) =>
      diagnostics.diagnostics.where(
        (d) =>
            (widgetId != null && d.widgetId == widgetId) ||
            (nodeId != null && d.nodeId == nodeId),
      );

  // ---------------------------------------------------------------------------

  /// Applies an edit and makes it undoable.
  ///
  /// [label] is what the undo menu says, so it is phrased as the thing that
  /// happened: "Add Text", not "setState".
  void apply(String label, Project Function(Project project) edit) {
    final next = edit(_project);
    if (identical(next, _project) || next == _project) return;

    _undo.add(_Snapshot(label, _project, _selection));
    if (_undo.length > _historyLimit) _undo.removeAt(0);
    _redo.clear();

    _project = next;
    _isDirty = true;
    _invalidate();
  }

  void undo() {
    if (_undo.isEmpty) return;
    final snapshot = _undo.removeLast();
    _redo.add(_Snapshot(snapshot.label, _project, _selection));
    _project = snapshot.project;
    _selection = snapshot.selection;
    _isDirty = true;
    _invalidate();
  }

  void redo() {
    if (_redo.isEmpty) return;
    final snapshot = _redo.removeLast();
    _undo.add(_Snapshot(snapshot.label, _project, _selection));
    _project = snapshot.project;
    _selection = snapshot.selection;
    _isDirty = true;
    _invalidate();
  }

  void select(Selection selection) {
    if (_selection == selection) return;
    _selection = selection;
    notifyListeners();
  }

  void openUnit(String unitId) {
    if (_activeUnitId == unitId) return;
    _activeUnitId = unitId;
    _selection = const NoSelection();
    notifyListeners();
  }

  /// Starts a binding gesture: the Graph now offers its output pins.
  void beginBinding(String widgetId, String param, LatticeType type) {
    _pendingBinding = PendingBinding(widgetId, param, type);
    notifyListeners();
  }

  void cancelBinding() {
    if (_pendingBinding == null) return;
    _pendingBinding = null;
    notifyListeners();
  }

  /// Completes a pending binding against [source], if the types allow it.
  ///
  /// Returns the reason it was refused, or null on success — the Graph shows
  /// that reason rather than silently doing nothing.
  String? completeBinding(PinRef source) {
    final pending = _pendingBinding;
    if (pending == null) return 'Nothing is waiting to be bound.';

    final context = NodeContext(
      graph: activeUnit.graph,
      unit: activeUnit,
      project: _project,
    );
    final sourceType = context.outputType(source);
    if (!sourceType.isAssignableTo(pending.type)) {
      return '${sourceType.dartName} does not fit '
          '${pending.param} (${pending.type.dartName}).';
    }

    apply(
      'Bind ${pending.param}',
      (project) => ProjectEdits.bindProp(
        project,
        _activeUnitId,
        pending.widgetId,
        pending.param,
        source,
      ),
    );
    _pendingBinding = null;
    notifyListeners();
    return null;
  }

  /// Marks the project saved. The host does the writing; this just records it.
  void markSaved({String? projectRoot}) {
    _projectRoot = projectRoot ?? _projectRoot;
    _isDirty = false;
    notifyListeners();
  }

  /// Replaces the whole project — used when a different one is opened.
  void load(Project project, {String? projectRoot}) {
    _project = project;
    _projectRoot = projectRoot;
    _activeUnitId = project.units.isEmpty ? '' : project.units.first.id;
    _selection = const NoSelection();
    _pendingBinding = null;
    _isDirty = false;
    _undo.clear();
    _redo.clear();
    _invalidate();
  }

  void _invalidate() {
    _diagnosticsCache = null;
    _generatedCache = null;
    notifyListeners();
  }
}

final class _Snapshot {
  const _Snapshot(this.label, this.project, this.selection);

  final String label;
  final Project project;
  final Selection selection;
}
