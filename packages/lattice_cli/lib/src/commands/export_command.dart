import 'dart:io';

import 'package:lattice_build/lattice_build.dart';
import 'package:lattice_codegen/lattice_codegen.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:path/path.dart' as p;

import '../project_locator.dart';
import 'base.dart';

/// `lattice export` — hand the user a standalone Flutter project (R8, G5).
///
/// The difference from `build` is self-containment: the runtime package, if
/// the project uses it, is copied in so the result compiles with no reference
/// back to this checkout. That is the concrete meaning of "not locked in".
class ExportCommand extends LatticeCommand {
  ExportCommand(super.console) {
    argParser.addOption(
      'output',
      abbr: 'o',
      help: 'Directory to export into.',
      valueHelp: 'directory',
      mandatory: true,
    );
    argParser.addFlag(
      'force',
      help: 'Overwrite a non-empty output directory.',
    );
  }

  @override
  String get name => 'export';

  @override
  String get description =>
      'Export a standalone Flutter project that no longer needs Lattice.';

  @override
  String get invocation => 'lattice export [project-directory] -o <directory>';

  @override
  Future<int> run() async {
    final root = resolveProjectRoot();
    final project = await loadProject(root);
    final output = p.absolute(argResults!['output'] as String);
    final force = argResults?['force'] as bool? ?? false;

    final directory = Directory(output);
    if (directory.existsSync() && directory.listSync().isNotEmpty && !force) {
      console.error('"$output" is not empty. Pass --force to overwrite.');
      return 1;
    }
    await directory.create(recursive: true);

    final usesLocalRuntime =
        project.config.runtime == RuntimeBackend.valueNotifier;
    final result = const LatticeGenerator().generate(
      project,
      runtimePath: usesLocalRuntime ? 'packages/lattice_runtime' : null,
    );

    if (!result.isSuccess) {
      console.diagnostics(result.errors);
      console.error('Nothing was exported.');
      return 1;
    }

    await const LatticeGenerator().write(result, output);

    if (usesLocalRuntime) {
      final source = ProjectLocator.findRuntimePackage(root);
      if (source == null) {
        console.error(
          'This project uses the zero-dependency runtime, but '
          'packages/lattice_runtime could not be found to copy in.',
        );
        return 1;
      }
      final destination = p.join(output, 'packages', 'lattice_runtime');
      await _copyDirectory(source, destination);
      console.step('Vendored lattice_runtime into packages/');
    }

    // The README the export ships tells the user to run `flutter run`, so the
    // platform directories have to be there for that to be true.
    final scaffold = await const PlatformScaffolder().ensure(
      output,
      project.config,
      project.config.targets,
      onLog: console.step,
    );
    if (!scaffold.isSuccess) {
      console.error('flutter create failed while configuring platforms.');
      return scaffold.exitCode;
    }
    if (scaffold.created.isNotEmpty) {
      console.step(
        'Configured ${scaffold.created.map((t) => t.id).join(', ')}.',
      );
    }
    await const AppMetadata().apply(output, project.config);

    console.success('Exported to ${p.relative(output)}');
    console.info('');
    console.info('  cd ${p.relative(output)}');
    console.info('  flutter pub get');
    console.info('  flutter run');
    return 0;
  }

  Future<void> _copyDirectory(String from, String to) async {
    await Directory(to).create(recursive: true);
    for (final entity in Directory(from).listSync(recursive: true)) {
      final relative = p.relative(entity.path, from: from);
      // Build artefacts are not part of the source of a package.
      if (relative.split(p.separator).any(
            (part) => part == '.dart_tool' || part == 'build' || part == '.git',
          )) {
        continue;
      }
      final target = p.join(to, relative);
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        await Directory(p.dirname(target)).create(recursive: true);
        await entity.copy(target);
      }
    }
  }
}
