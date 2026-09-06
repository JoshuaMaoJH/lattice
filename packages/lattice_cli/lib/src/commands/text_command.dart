import 'dart:io';

import 'package:lattice_core/io.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:path/path.dart' as p;

import 'base.dart';

/// `lattice text` — the project as `.lat` files, and back (R18).
///
/// Two directions in one command because they are one feature: the text is
/// only trustworthy if reading it back gives the same project, and a command
/// that could only write would let the two drift.
class TextCommand extends LatticeCommand {
  TextCommand(super.console) {
    argParser
      ..addOption(
        'out',
        help: 'Directory to write .lat files into. Defaults to stdout.',
        valueHelp: 'dir',
      )
      ..addFlag(
        'read',
        help: 'Read .lat files back and rewrite the project JSON.',
        negatable: false,
      );
  }

  @override
  String get name => 'text';

  @override
  String get description =>
      'Write the project as readable .lat text, or read it back.';

  @override
  String get invocation =>
      'lattice text [project-directory] [--out dir] [--read]';

  @override
  Future<int> run() async {
    final root = resolveProjectRoot();
    final reading = argResults?['read'] as bool? ?? false;
    final out = argResults?['out'] as String? ?? p.join(root, 'text');

    return reading ? _read(root, out) : _write(root, out);
  }

  Future<int> _write(String root, String out) async {
    final project = await loadProject(root);
    final units = project.graphUnits;

    if (argResults?['out'] == null) {
      for (final unit in units) {
        console.info(const LatWriter().write(unit));
      }
      return 0;
    }

    await Directory(out).create(recursive: true);
    for (final unit in units) {
      await File(p.join(out, '${unit.id}.lat'))
          .writeAsString(const LatWriter().write(unit));
    }
    console.success('Wrote ${units.length} file(s) to ${p.relative(out)}.');
    return 0;
  }

  Future<int> _read(String root, String out) async {
    final directory = Directory(out);
    if (!directory.existsSync()) {
      console.error('No ${p.relative(out)} to read. Run `lattice text --out '
          '${p.relative(out)}` first.');
      return 1;
    }

    final project = await loadProject(root);
    final pages = <Page>[];
    final prefabs = <Prefab>[];
    final functions = <ServerFunction>[];

    final files = directory
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.lat'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      final GraphUnit unit;
      try {
        unit = const LatReader().read(await file.readAsString());
      } on ProjectFormatException catch (error) {
        // The path in the exception is a line number; the file name is what
        // turns it into something you can jump to.
        console.error('${p.relative(file.path)} ${error.path}: '
            '${error.message}');
        return 1;
      }
      switch (unit) {
        case final Page page:
          pages.add(page);
        case final Prefab prefab:
          prefabs.add(prefab);
        case final ServerFunction function:
          functions.add(function);
        default:
          console.error('${p.relative(file.path)}: unknown unit kind.');
          return 1;
      }
    }

    final updated = project.copyWith(
      pages: pages.isEmpty ? null : pages,
      prefabs: prefabs.isEmpty ? null : prefabs,
      serverFunctions: functions.isEmpty ? null : functions,
    );

    final result = const Validator().validate(updated);
    console.diagnostics(result.diagnostics);
    if (!result.isValid) {
      console.error('Not written: fix the errors above first.');
      return 1;
    }

    await ProjectIo.save(updated, root);
    console.success('Read ${files.length} file(s) into ${p.relative(root)}.');
    return 0;
  }
}
