import 'package:lattice_build/lattice_build.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:path/path.dart' as p;

import '../project_locator.dart';
import 'base.dart';

/// `lattice package` — turn a build into something you can hand to someone
/// (§7.9, R16).
///
/// The distinction from `build --compile` is the last mile: a `bundle/`
/// directory is not a thing you send anyone, an AppImage or a zip is.
class PackageCommand extends LatticeCommand {
  PackageCommand(super.console) {
    argParser
      ..addMultiOption(
        'target',
        abbr: 't',
        help: 'Platforms to package. Defaults to the project settings.',
        allowed: [for (final t in BuildTarget.values) t.id],
      )
      ..addOption(
        'mode',
        help: 'Build mode.',
        allowed: [for (final m in BuildMode.values) m.flag],
        defaultsTo: BuildMode.release.flag,
      )
      ..addFlag(
        'build',
        defaultsTo: true,
        help: 'Run `flutter build` first. Turn off to package what is already '
            'there.',
      );
  }

  @override
  String get name => 'package';

  @override
  String get description =>
      'Produce distributable packages from a built project.';

  @override
  String get invocation => 'lattice package [project-directory] [-t web,linux]';

  @override
  Future<int> run() async {
    final root = resolveProjectRoot();
    final project = await loadProject(root);
    final buildDir = ProjectLocator.defaultBuildDir(root);
    final mode = BuildMode.values.firstWhere(
      (m) => m.flag == (argResults?['mode'] as String? ?? 'release'),
    );

    final requested = argResults?['target'] as List<String>? ?? const [];
    final targets = requested.isEmpty
        ? project.config.targets
        : [
            for (final id in requested)
              if (BuildTarget.fromId(id) case final target?) target,
          ];

    // Say up front what this machine cannot produce, and where it comes from
    // instead (ADR-006).
    for (final target in Host.notBuildable(targets)) {
      console.warn('${target.id}: ${Host.explain(target)}');
    }

    final buildable = Host.buildable(targets);
    if (buildable.isEmpty) {
      console.error('Nothing to package on this host.');
      return 1;
    }

    var failures = 0;
    for (final target in buildable) {
      if (argResults?['build'] as bool? ?? true) {
        console.step('Building ${target.id} (${mode.flag})…');
        final outcome = await const FlutterBuild().build(
          buildDir,
          target,
          mode: mode,
          onLog: (line) {
            if (line.trim().isNotEmpty) console.info('    $line');
          },
        );
        if (!outcome.isSuccess) {
          console.error('${target.id}: build failed.');
          failures++;
          continue;
        }
      }

      console.step('Packaging ${target.id}…');
      final packaged = await const Packager().package(
        buildDir,
        root,
        project.config,
        target,
        mode: mode,
        onLog: console.step,
      );

      if (packaged.isSuccess) {
        console.success('${target.id} -> ${p.relative(packaged.artifact!)}');
      } else {
        console.warn('${target.id}: ${packaged.skippedBecause}');
        failures++;
      }
    }

    return failures == 0 ? 0 : 1;
  }
}
