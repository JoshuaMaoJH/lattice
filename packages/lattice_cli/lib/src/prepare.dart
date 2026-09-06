import 'dart:io';

import 'package:lattice_build/lattice_build.dart';
import 'package:lattice_codegen/io.dart';
import 'package:lattice_codegen/lattice_codegen.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:path/path.dart' as p;

/// What `_prepare` produced.
final class PreparedProject {
  const PreparedProject.ready(this.outputDir)
      : failure = null,
        exitCode = 0;

  const PreparedProject.failed(this.failure, this.exitCode) : outputDir = '';

  final String outputDir;
  final String? failure;
  final int exitCode;

  bool get isReady => failure == null;
}

/// Brings `.lattice/build` to the state a Flutter command can act on.
///
/// Writing Dart is not enough: `flutter build linux` needs a `linux/`
/// directory, and every platform needs its metadata written into its own
/// config format (§7.9 steps 1–2). Three separate callers learned this the
/// hard way — the CLI's build, the editor's preview, and packaging — so it
/// lives in one place now.
Future<PreparedProject> prepareProject(
  Project project,
  String root,
  List<BuildTarget> targets, {
  void Function(String message)? onLog,
}) async {
  final output = p.join(root, '.lattice', 'build');

  final result = const LatticeGenerator().generate(project);
  if (!result.isSuccess) {
    return PreparedProject.failed(
      result.errors.map((e) => e.toString()).join('\n'),
      1,
    );
  }
  await const LatticeGenerator()
      .write(result, output, customSource: p.join(root, 'custom'));

  final scaffold = await const PlatformScaffolder()
      .ensure(output, project.config, targets, onLog: onLog);
  if (!scaffold.isSuccess) {
    return PreparedProject.failed(
      'flutter create failed for '
      '${targets.map((t) => t.id).join(', ')}.',
      scaffold.exitCode,
    );
  }
  if (scaffold.created.isNotEmpty) {
    onLog?.call('Configured ${scaffold.created.map((t) => t.id).join(', ')}.');
  }

  await const AppMetadata().apply(output, project.config);

  // Packaging configuration and a placeholder icon, so `lattice package`
  // works on a project the moment it exists (§7.9 step 4).
  final packaging =
      await const PackagingConfig().write(output, project.config, targets);
  if (packaging.isNotEmpty) {
    onLog?.call('Wrote ${packaging.length} packaging config file(s).');
  }

  return PreparedProject.ready(output);
}

/// Whether [outputDir] already has the platform directory [target] needs.
bool hasPlatformDirectory(String outputDir, BuildTarget target) =>
    Directory(p.join(outputDir, PlatformScaffolder.directoryFor(target)))
        .existsSync();
