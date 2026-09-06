import 'package:flutter/material.dart';
import 'package:lattice_build/lattice_build.dart';
import 'package:lattice_core/lattice_core.dart';

import '../host/editor_host.dart';
import '../theme.dart';

/// What signing each target needs, and what is missing here (R22).
///
/// A checklist, not a form. §7.9 keeps credentials out of project files, so
/// there is nowhere in this editor for them to be typed — the wizard's job is
/// to say which environment variables to set and which are still empty. It
/// reads presence, never values, so this screen is safe to screenshot.
class SigningWizard extends StatelessWidget {
  const SigningWizard({
    super.key,
    required this.host,
    required this.targets,
  });

  final EditorHost host;
  final List<BuildTarget> targets;

  static Future<void> show(
    BuildContext context,
    EditorHost host,
    List<BuildTarget> targets,
  ) =>
      showDialog<void>(
        context: context,
        builder: (_) => SigningWizard(host: host, targets: targets),
      );

  /// Recomputed from the host rather than from `Platform.environment`, so the
  /// web build reports "nothing is set here" instead of crashing.
  List<CredentialStatus> _statusFor(BuildTarget target) {
    final required = Signing.requirementsFor(target);
    final present = host.presentEnvironment(required.map((c) => c.variable));
    return [
      for (final credential in required)
        CredentialStatus(
          credential,
          !present.contains(credential.variable)
              ? CredentialState.missing
              : credential.isFile &&
                      !host.environmentPathExists(credential.variable)
                  ? CredentialState.danglingPath
                  : CredentialState.ready,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final signable = [
      for (final target in targets)
        if (Signing.requirementsFor(target).isNotEmpty) target,
    ];

    return Dialog(
      backgroundColor: LatticeTheme.panel,
      child: SizedBox(
        width: 640,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text('Signing', style: LatticeTheme.title),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Credentials are read from the environment and never written '
                'into the project. Nothing here shows a value.',
                style: LatticeTheme.secondary,
              ),
            ),
            const Divider(height: 1, color: LatticeTheme.hairline),
            Expanded(
              child: signable.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: Text(
                          'None of this project’s targets are code-signed. '
                          'Linux packages and web bundles are trusted by '
                          'where they came from, not by the file.',
                          style: LatticeTheme.secondary,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        for (final target in signable) ..._section(target),
                      ],
                    ),
            ),
            const Divider(height: 1, color: LatticeTheme.hairline),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'On CI these come from repository secrets; the generated '
                      'release workflow already wires them up.',
                      style: LatticeTheme.secondary,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _section(BuildTarget target) {
    final status = _statusFor(target);
    final ready = status.every((s) => s.isReady);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
        child: Row(
          children: [
            Text(target.id.toUpperCase(), style: LatticeTheme.eyebrow),
            const SizedBox(width: 10),
            Text(
              ready ? 'ready' : 'not ready',
              style: LatticeTheme.secondary.copyWith(
                color:
                    ready ? LatticeTheme.selectionEdge : LatticeTheme.warning,
              ),
            ),
          ],
        ),
      ),
      for (final entry in status) _row(entry),
    ];
  }

  Widget _row(CredentialStatus status) {
    final (icon, colour, note) = switch (status.state) {
      CredentialState.ready => (
          Icons.check_circle_outline,
          LatticeTheme.selectionEdge,
          'set',
        ),
      CredentialState.missing => (
          Icons.radio_button_unchecked,
          LatticeTheme.textFaint,
          'not set',
        ),
      CredentialState.danglingPath => (
          Icons.error_outline,
          LatticeTheme.error,
          'set, but that file is not there',
        ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 15, color: colour),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        status.credential.variable,
                        style: LatticeTheme.monoSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(note,
                        style: LatticeTheme.secondary.copyWith(color: colour)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(status.credential.what, style: LatticeTheme.secondary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
