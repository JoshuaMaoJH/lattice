import 'package:flutter/material.dart';
import 'package:lattice_core/lattice_core.dart';

import '../state/editor_controller.dart';
import '../theme.dart';
import '../widgets/chrome.dart';

/// The problems strip (R15).
///
/// Every diagnostic carries the node or widget that produced it, which is the
/// whole reason it is worth having: clicking a row opens the right unit and
/// selects the right thing. A validator that could only say "something is
/// wrong somewhere" would not have earned this panel.
class DiagnosticsPanel extends StatelessWidget {
  const DiagnosticsPanel({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final result = controller.diagnostics;
    final errors = result.errors.length;
    final warnings = result.warnings.length;

    return Panel(
      title: 'Problems',
      badge: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (errors > 0) CountBadge(errors, color: LatticeTheme.error),
          if (errors > 0 && warnings > 0) const SizedBox(width: 4),
          if (warnings > 0) CountBadge(warnings, color: LatticeTheme.warning),
          if (errors == 0 && warnings == 0)
            Text('none', style: LatticeTheme.monoSmall.copyWith(fontSize: 10)),
        ],
      ),
      child: result.diagnostics.isEmpty
          ? Center(
              child: Text(
                'The project is valid.',
                style: LatticeTheme.secondary,
              ),
            )
          : ListView.builder(
              itemCount: result.diagnostics.length,
              itemBuilder: (context, index) => _Row(
                  controller: controller,
                  diagnostic: result.diagnostics[index]),
            ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.controller, required this.diagnostic});

  final EditorController controller;
  final Diagnostic diagnostic;

  @override
  Widget build(BuildContext context) {
    final colour =
        diagnostic.isError ? LatticeTheme.error : LatticeTheme.warning;

    return InkWell(
      onTap: _reveal,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: LatticeTheme.gutter, vertical: 5),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: LatticeTheme.hairline)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                diagnostic.isError
                    ? Icons.error_outline
                    : Icons.warning_amber_outlined,
                size: 13,
                color: colour,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 150,
              child: Text(
                diagnostic.location,
                overflow: TextOverflow.ellipsis,
                style: LatticeTheme.monoSmall.copyWith(color: colour),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(diagnostic.message, style: LatticeTheme.secondary)),
            const SizedBox(width: 10),
            Text(
              diagnostic.code,
              style: LatticeTheme.monoSmall.copyWith(
                fontSize: 10,
                color: LatticeTheme.textFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _reveal() {
    final pageId = diagnostic.pageId;
    if (pageId != null && pageId != controller.activeUnitId) {
      controller.openUnit(pageId);
    }
    if (diagnostic.widgetId case final id?) {
      controller.select(WidgetSelection(id));
    } else if (diagnostic.nodeId case final id?) {
      controller.select(NodeSelection(id));
    }
  }
}
