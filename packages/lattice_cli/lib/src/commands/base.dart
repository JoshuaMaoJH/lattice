import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:lattice_core/io.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:path/path.dart' as p;

import '../console.dart';
import '../project_locator.dart';

/// Shared plumbing: locating the project, loading it, reporting diagnostics.
abstract class LatticeCommand extends Command<int> {
  LatticeCommand(this.console);

  final Console console;

  /// Resolves the project directory from the first rest argument, the
  /// `--project` option, or the current directory.
  String resolveProjectRoot() {
    final explicit = argResults?.rest.isNotEmpty ?? false
        ? argResults!.rest.first
        : Directory.current.path;
    final root = ProjectLocator.findProjectRoot(explicit);
    if (root == null) {
      throw UsageException(
        'No project.json found in "${p.absolute(explicit)}" or any parent.',
        'Run `lattice new <directory>` to create one.',
      );
    }
    return root;
  }

  Future<Project> loadProject(String root) async {
    try {
      return await ProjectIo.load(root);
    } on ProjectFormatException catch (e) {
      console.error('Could not read the project: ${e.message}');
      if (e.path != null) console.info('  at ${e.path}');
      rethrow;
    }
  }

  /// Runs a subprocess, streaming its output, and returns its exit code.
  Future<int> exec(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    console.step(
      '${console.dim(p.basename(executable))} ${arguments.join(' ')}',
    );
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      mode: ProcessStartMode.inheritStdio,
    );
    return process.exitCode;
  }

  /// Finds the `flutter` executable, preferring one already on PATH.
  String get flutterExecutable =>
      Platform.isWindows ? 'flutter.bat' : 'flutter';
}
