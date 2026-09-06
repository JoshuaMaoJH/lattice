import 'package:dart_style/dart_style.dart';
import 'package:lattice_core/lattice_core.dart';

import 'codegen_exception.dart';
import 'emit/app_emitter.dart';
import 'emit/model_emitter.dart';
import 'emit/page_emitter.dart';
import 'emit/rpc_client_emitter.dart';
import 'emit/support_files.dart';
import 'ir/lowering.dart';

/// The result of running the pipeline: either a set of files ready to write,
/// or the diagnostics that stopped it.
final class GenerationResult {
  GenerationResult({
    required this.files,
    required this.validation,
    List<Diagnostic> extra = const [],
  }) : diagnostics = [...validation.diagnostics, ...extra];

  /// Project-relative path -> file contents.
  final Map<String, String> files;

  final ValidationResult validation;
  final List<Diagnostic> diagnostics;

  Iterable<Diagnostic> get errors => diagnostics.where((d) => d.isError);

  bool get isSuccess => errors.isEmpty && files.isNotEmpty;
}

/// Runs the whole pipeline: validate, lower, emit, format (§7.5).
class LatticeGenerator {
  const LatticeGenerator();

  /// [runtimePath] is the relative path from the generated project back to
  /// `packages/lattice_runtime`, needed only by the zero-dependency backend.
  GenerationResult generate(Project project, {String? runtimePath}) {
    final validation = const Validator().validate(project);
    if (!validation.isValid) {
      return GenerationResult(files: const {}, validation: validation);
    }

    final formatter = DartFormatter(
      languageVersion: DartFormatter.latestLanguageVersion,
    );
    final files = <String, String>{};
    final extra = <Diagnostic>[];

    void addDart(String path, String source) {
      try {
        files[path] = formatter.format(source);
      } on FormatterException catch (e) {
        // Unformattable output means the emitter produced invalid Dart. The
        // raw text is kept so the failure can be read rather than guessed at.
        files[path] = source;
        extra.add(
          Diagnostic.error(
            code: 'emitted_invalid_dart',
            message: 'Generated $path does not parse: ${e.message}',
          ),
        );
      }
    }

    try {
      final ir = const Lowering().lower(project);

      for (final page in ir.pages) {
        addDart(
          'lib/${page.unit.directory}/${page.fileName}',
          const PageEmitter().emit(ir, page),
        );
      }
      addDart('lib/main.dart', const AppEmitter().emit(project));
      if (project.hasServer) {
        // The other half of every `Call Server` node (§7.7).
        addDart('lib/rpc.dart', const RpcClientEmitter().emit(ir));
      }
      if (project.models.isNotEmpty) {
        addDart('lib/models.dart', const ModelEmitter().emit(project.models));
      }

      const support = SupportFiles();
      files['pubspec.yaml'] = support.pubspec(
        project,
        runtimePath: runtimePath,
        usesHttp: ir.usesHttp,
      );
      files['analysis_options.yaml'] = support.analysisOptions(project);
      files['README.md'] = support.readme(project);
      files['.gitignore'] = support.gitignore();
      files['lib/debug.dart'] = support.debugChannel();
      files['distribute_options.yaml'] = support.distributeOptions(project);
      files['.github/workflows/build.yml'] = support.ciWorkflow(project);
      files['.github/workflows/release.yml'] = support.releaseWorkflow(project);
    } on CodegenException catch (e) {
      return GenerationResult(
        files: const {},
        validation: validation,
        extra: [e.toDiagnostic()],
      );
    }

    return GenerationResult(
      files: files,
      validation: validation,
      extra: extra,
    );
  }

  /// Writes [result] into [outputDir].
  ///
  /// `lib/custom/` is created if missing and never touched afterwards — that
  /// is the promise the Dart Code escape hatch rests on (§7.8).
}
