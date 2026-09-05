import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:lattice_cli/lattice_cli.dart';
import 'package:lattice_core/lattice_core.dart';

Future<void> main(List<String> arguments) async {
  final console = Console();
  try {
    final code = await LatticeCommandRunner(console: console).run(arguments);
    exit(code ?? 0);
  } on UsageException catch (e) {
    console.error(e.message);
    console.info('');
    console.info(e.usage);
    exit(64);
  } on ProjectFormatException {
    // Already reported with its path by the command.
    exit(65);
  }
}
