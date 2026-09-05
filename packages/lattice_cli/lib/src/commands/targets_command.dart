import 'package:lattice_build/lattice_build.dart';
import 'package:lattice_core/lattice_core.dart';

import 'base.dart';

/// `lattice targets` — what this machine can and cannot build, and why.
///
/// Answers the question ADR-006 exists for, before the user spends twenty
/// minutes finding out the hard way.
class TargetsCommand extends LatticeCommand {
  TargetsCommand(super.console);

  @override
  String get name => 'targets';

  @override
  String get description =>
      'List build targets and whether this machine can produce them.';

  @override
  String get invocation => 'lattice targets [project-directory]';

  @override
  Future<int> run() async {
    final root = resolveProjectRoot();
    final project = await loadProject(root);
    final selected = project.config.targets.map((t) => t.id).toSet();

    console.info('Host: ${Host.os}');
    console.info('');
    for (final target in BuildTarget.values) {
      final marker = selected.contains(target.id) ? '*' : ' ';
      final label = Host.canBuild(target)
          ? console.green('local')
          : console.yellow('ci   ');
      console.info(
        ' $marker $label  ${target.id.padRight(8)} ${console.dim(Host.explain(target))}',
      );
    }
    console.info('');
    console.info(console.dim('  * = enabled in this project'));
    return 0;
  }
}
