import 'package:args/command_runner.dart';

import 'commands/analyze_command.dart';
import 'commands/build_command.dart';
import 'commands/export_command.dart';
import 'commands/new_command.dart';
import 'commands/package_command.dart';
import 'commands/run_command.dart';
import 'commands/targets_command.dart';
import 'console.dart';

/// The `lattice` command line.
///
/// The editor's Build panel is a GUI over these same commands, and both go
/// through `lattice_codegen` — there is one pipeline, not two (§7.9).
class LatticeCommandRunner extends CommandRunner<int> {
  LatticeCommandRunner({Console? console})
      : super('lattice',
            'Build Flutter applications from a hierarchy and a node graph.') {
    final output = console ?? Console();
    addCommand(NewCommand(output));
    addCommand(BuildCommand(output));
    addCommand(RunCommand(output));
    addCommand(PackageCommand(output));
    addCommand(ExportCommand(output));
    addCommand(AnalyzeCommand(output));
    addCommand(TargetsCommand(output));
  }
}
