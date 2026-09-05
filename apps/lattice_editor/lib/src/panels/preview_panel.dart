import 'package:flutter/material.dart';
import 'package:lattice_codegen/lattice_codegen.dart';
import 'package:lattice_core/lattice_core.dart';

import '../host/editor_host.dart';
import '../state/editor_controller.dart';
import '../theme.dart';
import '../widgets/chrome.dart';

/// What the graph is about to become (R5, R6).
///
/// Two views of the same thing. **Code** is the generated Dart, refreshed on
/// every edit — it works everywhere and is the fastest way to see what a
/// binding actually compiled to. **App** is the real thing: a `flutter run`
/// the editor hot-reloads, so the preview is the product rather than a
/// simulation of it (ADR-002).
class PreviewPanel extends StatefulWidget {
  const PreviewPanel({
    super.key,
    required this.controller,
    required this.host,
  });

  final EditorController controller;
  final EditorHost host;

  @override
  State<PreviewPanel> createState() => _PreviewPanelState();
}

class _PreviewPanelState extends State<PreviewPanel> {
  bool _showApp = false;
  String? _openFile;

  EditorController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final generated = controller.generated;

    return Panel(
      title: 'Preview',
      actions: [
        ToolButton(
          icon: Icons.code,
          tooltip: 'Generated Dart',
          isActive: !_showApp,
          onPressed: () => setState(() => _showApp = false),
        ),
        ToolButton(
          icon: Icons.play_circle_outline,
          tooltip: widget.host.canRunPreview
              ? 'Run the app'
              : 'Running the app needs the desktop editor',
          isActive: _showApp,
          onPressed: () => setState(() => _showApp = true),
        ),
      ],
      child: _showApp ? _appView() : _codeView(generated),
    );
  }

  // ---------------------------------------------------------------------------

  Widget _codeView(GenerationResult generated) {
    if (!generated.isSuccess) {
      return _Blocked(errors: generated.errors.toList());
    }

    final dartFiles = generated.files.keys
        .where((String path) => path.endsWith('.dart'))
        .toList()
      ..sort();
    if (dartFiles.isEmpty) return const _Message('Nothing to generate yet.');

    final active =
        dartFiles.contains(_openFile) ? _openFile! : _defaultFile(dartFiles);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 26,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final path in dartFiles)
                _FileTab(
                  path: path,
                  isActive: path == active,
                  onTap: () => setState(() => _openFile = path),
                ),
            ],
          ),
        ),
        const Hairline(),
        Expanded(
          child: Container(
            color: LatticeTheme.canvas,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  generated.files[active]!,
                  style: LatticeTheme.code,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Opens on the file for the unit being edited — that is the one the user
  /// just changed, and the reason they looked over here.
  String _defaultFile(List<String> candidates) {
    final unit = controller.activeUnit;
    final expected = 'lib/${unit.directory}/${unit.fileName}';
    return candidates.contains(expected) ? expected : candidates.first;
  }

  Widget _appView() {
    if (!widget.host.canRunPreview) {
      return _Message(
        'The live preview runs a real `flutter run` and hot-reloads it, so it '
        'needs a filesystem and a subprocess. You are in '
        '${widget.host.description}.\n\n'
        'The Code view beside this one works everywhere, and shows exactly '
        'what would be compiled.',
      );
    }
    if (controller.projectRoot == null) {
      return const _Message('Save the project somewhere first.');
    }

    return StreamBuilder<void>(
      stream: widget.host.previewChanges,
      builder: (context, _) {
        final status = widget.host.previewStatus;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              color: LatticeTheme.surface,
              child: Row(
                children: [
                  _StatusDot(status),
                  const SizedBox(width: 8),
                  Text(status.name, style: LatticeTheme.monoSmall),
                  const Spacer(),
                  ToolButton(
                    icon: Icons.play_arrow,
                    tooltip: 'Start',
                    onPressed: status == PreviewStatus.running
                        ? null
                        : () => widget.host.startPreview(
                              controller.project,
                              controller.projectRoot!,
                            ),
                  ),
                  ToolButton(
                    icon: Icons.refresh,
                    tooltip: 'Hot reload',
                    onPressed: status == PreviewStatus.running
                        ? () => widget.host.reloadPreview(
                              controller.project,
                              controller.projectRoot!,
                            )
                        : null,
                  ),
                  ToolButton(
                    icon: Icons.stop,
                    tooltip: 'Stop',
                    onPressed: status == PreviewStatus.stopped
                        ? null
                        : widget.host.stopPreview,
                  ),
                ],
              ),
            ),
            const Hairline(),
            Expanded(
              child: Container(
                color: LatticeTheme.canvas,
                padding: const EdgeInsets.all(10),
                child: ListView(
                  children: [
                    for (final line in widget.host.previewLog)
                      Text(line, style: LatticeTheme.code),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FileTab extends StatelessWidget {
  const _FileTab({
    required this.path,
    required this.isActive,
    required this.onTap,
  });

  final String path;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? LatticeTheme.canvas : null,
            border: Border(
              bottom: BorderSide(
                color:
                    isActive ? LatticeTheme.selectionEdge : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            path.split('/').last,
            style: LatticeTheme.monoSmall.copyWith(
              color: isActive
                  ? LatticeTheme.textPrimary
                  : LatticeTheme.textSecondary,
            ),
          ),
        ),
      );
}

class _StatusDot extends StatelessWidget {
  const _StatusDot(this.status);

  final PreviewStatus status;

  @override
  Widget build(BuildContext context) {
    final colour = switch (status) {
      PreviewStatus.running => LatticeTheme.forFamily(TypeFamily.list),
      PreviewStatus.starting => LatticeTheme.warning,
      PreviewStatus.failed => LatticeTheme.error,
      PreviewStatus.stopped => LatticeTheme.textFaint,
    };
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(text, style: LatticeTheme.secondary),
          ),
        ),
      );
}

/// Codegen refuses to emit anything for an invalid project, so the preview
/// says why rather than going blank.
class _Blocked extends StatelessWidget {
  const _Blocked({required this.errors});

  final List<Diagnostic> errors;

  @override
  Widget build(BuildContext context) => Container(
        color: LatticeTheme.canvas,
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text(
              'Nothing is generated while the project has errors.',
              style: LatticeTheme.body,
            ),
            const SizedBox(height: 12),
            for (final error in errors)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      error.location,
                      style: LatticeTheme.monoSmall.copyWith(
                        color: LatticeTheme.error,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(error.message, style: LatticeTheme.secondary),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}
