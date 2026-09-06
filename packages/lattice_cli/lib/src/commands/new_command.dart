import 'dart:io';

import 'package:lattice_codegen/lattice_codegen.dart';
import 'package:lattice_core/io.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:path/path.dart' as p;

import 'base.dart';

/// `lattice new` — writes a minimal but complete project.
///
/// The starter is the counter from §8: small enough to read in one screen, and
/// it exercises every part of the pipeline (a signal, a computed binding, an
/// event chain, a reactive boundary).
class NewCommand extends LatticeCommand {
  NewCommand(super.console) {
    argParser
      ..addOption('name', help: 'Application display name.', valueHelp: 'name')
      ..addOption(
        'package',
        help: 'Dart package name for the generated project.',
        valueHelp: 'snake_case',
      )
      ..addOption(
        'runtime',
        help: 'Reactive backend for generated code.',
        allowed: ['signals', 'value_notifier'],
        defaultsTo: 'signals',
      );
  }

  @override
  String get name => 'new';

  @override
  String get description => 'Create a new Lattice project.';

  @override
  String get invocation => 'lattice new <directory> [--name "My App"]';

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? const [];
    if (rest.isEmpty) {
      console.error('Give a directory: lattice new my_app');
      return 1;
    }
    final root = p.absolute(rest.first);
    final directory = Directory(root);
    if (directory.existsSync() && directory.listSync().isNotEmpty) {
      console.error('"$root" already exists and is not empty.');
      return 1;
    }

    final folder = p.basename(root);
    final appName = argResults?['name'] as String?;
    final packageName = argResults?['package'] as String?;

    final project = Starter.project(
      folder,
      appName: appName,
      package: packageName,
      runtime: RuntimeBackend.fromId(argResults?['runtime'] as String?),
    );

    await ProjectIo.save(project, root);
    await File(p.join(root, 'custom', 'README.md'))
        .create(recursive: true)
        .then(
          (file) => file.writeAsString(const SupportFiles().customReadme()),
        );
    console.success('Created ${p.relative(root)}');
    console.info('');
    console.info('  lattice run ${p.relative(root)}');
    return 0;
  }

  /// The §8 counter, expressed in the project model rather than in JSON, so
  /// this doubles as a worked example of the data structures.
}
