import 'package:lattice_core/lattice_core.dart';

import 'base.dart';

/// `lattice analyze` — runs the validator and nothing else (§7.5 step 1).
class AnalyzeCommand extends LatticeCommand {
  AnalyzeCommand(super.console);

  @override
  String get name => 'analyze';

  @override
  String get description =>
      'Validate a project: types, cycles, unconnected pins, layout rules.';

  @override
  String get invocation => 'lattice analyze [project-directory]';

  @override
  Future<int> run() async {
    final root = resolveProjectRoot();
    final project = await loadProject(root);
    final result = const Validator().validate(project);

    console.diagnostics(result.diagnostics);

    if (result.isValid) {
      final warnings = result.warnings.length;
      console.success(
        '${project.pages.length} page(s) valid'
        '${warnings == 0 ? '' : ', $warnings warning(s)'}.',
      );
      return 0;
    }
    console.error('${result.errors.length} error(s).');
    return 1;
  }
}
