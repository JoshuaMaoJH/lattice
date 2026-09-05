import 'package:lattice_codegen/lattice_codegen.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:path/path.dart' as p;

import '../project_locator.dart';
import 'base.dart';

/// `lattice run` — build, then hand off to `flutter run`.
///
/// This is the command line half of the preview window (§7.6). The editor will
/// drive the same subprocess, keeping its handle so it can signal a hot reload
/// instead of restarting.
class RunCommand extends LatticeCommand {
  RunCommand(super.console) {
    argParser.addOption(
      'device',
      abbr: 'd',
      help: 'Device id passed through to `flutter run`.',
      valueHelp: 'device',
    );
  }

  @override
  String get name => 'run';

  @override
  String get description => 'Generate the project and run it.';

  @override
  String get invocation => 'lattice run [project-directory] [-d device]';

  @override
  Future<int> run() async {
    final root = resolveProjectRoot();
    final project = await loadProject(root);
    final output = ProjectLocator.defaultBuildDir(root);

    String? runtimePath;
    if (project.config.runtime == RuntimeBackend.valueNotifier) {
      final package = ProjectLocator.findRuntimePackage(root);
      if (package != null) {
        runtimePath = p.relative(package, from: p.absolute(output));
      }
    }

    final result =
        const LatticeGenerator().generate(project, runtimePath: runtimePath);
    if (!result.isSuccess) {
      console.diagnostics(result.errors);
      return 1;
    }
    await const LatticeGenerator().write(result, output);
    console.success('Generated ${result.files.length} file(s).');

    final device = argResults?['device'] as String?;
    return exec(
      flutterExecutable,
      [
        'run',
        if (device != null) ...['-d', device]
      ],
      workingDirectory: output,
    );
  }
}
