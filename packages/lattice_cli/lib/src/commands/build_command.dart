import 'dart:io';

import 'package:lattice_build/lattice_build.dart';
import 'package:lattice_codegen/io.dart';
import 'package:lattice_codegen/lattice_codegen.dart';
import 'package:lattice_server_gen/io.dart';
import 'package:lattice_server_gen/lattice_server_gen.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:path/path.dart' as p;

import '../project_locator.dart';
import 'base.dart';

/// `lattice build` — the whole pipeline in one command (§7.5, §7.9).
///
/// Generate Dart, scaffold whatever platform directories the targets need,
/// write the app metadata into them, and optionally invoke `flutter build`.
/// The editor's Build panel drives exactly this sequence.
class BuildCommand extends LatticeCommand {
  BuildCommand(super.console) {
    argParser
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Where to write the generated Flutter project.',
        valueHelp: 'directory',
      )
      ..addMultiOption(
        'target',
        abbr: 't',
        help: 'Platforms to configure. Defaults to the project settings.',
        allowed: [for (final t in BuildTarget.values) t.id],
      )
      ..addOption(
        'mode',
        help: 'Build mode used with --compile.',
        allowed: [for (final m in BuildMode.values) m.flag],
        defaultsTo: BuildMode.release.flag,
      )
      ..addFlag(
        'compile',
        help: 'Run `flutter build` for each target this host can build.',
      )
      ..addFlag(
        'pub-get',
        defaultsTo: true,
        help: 'Run `flutter pub get` in the generated project.',
      )
      ..addFlag(
        'analyze',
        help: 'Gate on `flutter analyze` of the generated project '
            '(§7.5 step 5).',
      );
  }

  @override
  String get name => 'build';

  @override
  String get description =>
      'Generate a runnable Flutter project from a Lattice project.';

  @override
  String get invocation => 'lattice build [project-directory] [-t linux,web]';

  /// Writes a file map, skipping files whose contents already match.
  Future<int> _writeFiles(Map<String, String> files, String outputDir) async {
    var changed = 0;
    for (final entry in files.entries) {
      final file = File(p.join(outputDir, entry.key));
      await file.parent.create(recursive: true);
      if (file.existsSync() && await file.readAsString() == entry.value) {
        continue;
      }
      await file.writeAsString(entry.value);
      changed++;
    }
    return changed;
  }

  @override
  Future<int> run() async {
    final root = resolveProjectRoot();
    final project = await loadProject(root);
    final output = argResults?['output'] as String? ??
        ProjectLocator.defaultBuildDir(root);
    final targets = _targets(project);

    // 1. Validate, lower, emit, format.
    Directory(output).createSync(recursive: true);
    final result = const LatticeGenerator().generate(
      project,
      runtimePath: _runtimePath(project, root, output),
    );
    if (!result.isSuccess) {
      console.diagnostics(result.errors);
      console.error('Nothing was written.');
      return 1;
    }
    console.diagnostics(result.validation.warnings);
    final written = await const LatticeGenerator().write(
      result,
      output,
      customSource: p.join(root, 'custom'),
    );
    console.success(
      '${result.files.length} file(s) generated, ${written.length} changed '
      '-> ${p.relative(output)}',
    );

    // 1b. The server half, when the graph has one (§7.7). No flag: a project
    //     with server functions is not fully generated without them.
    if (project.hasServer) {
      final serverOutput = p.join(root, '.lattice', 'build_server');
      final server = const ServerGenerator().generate(project);
      if (!server.isSuccess) {
        for (final error in server.errors) {
          console.error('  $error');
        }
        return 1;
      }
      final serverWritten = await _writeFiles(server.files, serverOutput);

      // Only the hand-written files the server actually reaches for (§7.8).
      final mirrored = await const ServerCustomMirror().mirror(
        root,
        serverOutput,
        server.customImports,
      );
      if (mirrored.any((d) => d.isError)) {
        for (final problem in mirrored) {
          console.error('  $problem');
        }
        return 1;
      }

      console.success(
        '${server.files.length} server file(s), $serverWritten changed '
        '-> ${p.relative(serverOutput)}',
      );
      console.step(
        'Run it with: cd ${p.relative(serverOutput)} && '
        'dart pub get && dart run bin/server.dart',
      );
    }

    // 2. Platform directories, created once and then left alone.
    final scaffold = await const PlatformScaffolder().ensure(
      output,
      project.config,
      targets,
      onLog: console.step,
    );
    if (!scaffold.isSuccess) {
      console.error('flutter create failed.');
      return scaffold.exitCode;
    }
    if (scaffold.created.isNotEmpty) {
      console.success(
        'Configured ${scaffold.created.map((t) => t.id).join(', ')}.',
      );
    }

    // 3. Application metadata into each platform's own config format.
    final touched = await const AppMetadata().apply(output, project.config);
    if (touched.isNotEmpty) {
      console.step('Updated ${touched.length} platform config file(s).');
    }

    if (argResults?['pub-get'] as bool? ?? true) {
      final code = await exec(flutterExecutable, ['pub', 'get'],
          workingDirectory: output);
      if (code != 0) {
        console.error('flutter pub get failed.');
        return code;
      }
    }

    if (argResults?['analyze'] as bool? ?? false) {
      final code =
          await exec(flutterExecutable, ['analyze'], workingDirectory: output);
      if (code != 0) {
        console.error('The generated project did not analyze cleanly.');
        return code;
      }
      console.success('Generated project analyzes clean.');
    }

    if (argResults?['compile'] as bool? ?? false) {
      return _compile(output, targets);
    }
    return 0;
  }

  List<BuildTarget> _targets(Project project) {
    final requested = argResults?['target'] as List<String>? ?? const [];
    if (requested.isEmpty) return project.config.targets;
    return [
      for (final id in requested)
        if (BuildTarget.fromId(id) case final target?) target,
    ];
  }

  String? _runtimePath(Project project, String root, String output) {
    if (project.config.runtime != RuntimeBackend.valueNotifier) return null;
    final package = ProjectLocator.findRuntimePackage(root);
    return package == null
        ? null
        : p.relative(package, from: p.absolute(output));
  }

  Future<int> _compile(String output, List<BuildTarget> targets) async {
    final mode = BuildMode.values.firstWhere(
        (m) => m.flag == (argResults?['mode'] as String? ?? 'release'));

    // Rather than let a build fail deep inside a toolchain, say up front which
    // targets this machine cannot produce and where they come from instead
    // (ADR-006).
    for (final target in Host.notBuildable(targets)) {
      console.warn('${target.id}: ${Host.explain(target)}');
    }

    var failures = 0;
    for (final target in Host.buildable(targets)) {
      console.step('Building ${target.id} (${mode.flag})…');
      final outcome = await const FlutterBuild().build(
        output,
        target,
        mode: mode,
        onLog: (line) {
          if (line.trim().isNotEmpty) console.info('    $line');
        },
      );
      if (outcome.isSuccess) {
        console.success(
          '${target.id} -> ${p.relative(outcome.artifact ?? output)}',
        );
      } else {
        console.error('${target.id} build failed (exit ${outcome.exitCode}).');
        failures++;
      }
    }
    return failures == 0 ? 0 : 1;
  }
}
