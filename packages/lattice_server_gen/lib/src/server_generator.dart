import 'package:dart_style/dart_style.dart';
import 'package:lattice_codegen/lattice_codegen.dart';
import 'package:lattice_core/lattice_core.dart';

import 'server_emitter.dart';

/// A generated server project, as a map of files.
final class ServerGenerationResult {
  const ServerGenerationResult({
    required this.files,
    required this.diagnostics,
  });

  /// Path relative to the server project root -> contents.
  final Map<String, String> files;

  final List<Diagnostic> diagnostics;

  bool get isSuccess => !diagnostics.any((d) => d.isError);

  Iterable<Diagnostic> get errors => diagnostics.where((d) => d.isError);
}

/// Turns a project's server functions into a runnable Dart program (§7.7).
///
/// Output goes to `.lattice/build_server/`, which is a sibling of the client's
/// `.lattice/build/` — the same graph, two artefacts.
class ServerGenerator {
  const ServerGenerator();

  ServerGenerationResult generate(Project project) {
    final diagnostics = <Diagnostic>[];
    final files = <String, String>{};

    final validation = const Validator().validate(project);
    diagnostics.addAll(validation.diagnostics);
    if (!validation.isValid) {
      return ServerGenerationResult(files: files, diagnostics: diagnostics);
    }
    if (!project.hasServer) {
      return ServerGenerationResult(files: files, diagnostics: diagnostics);
    }

    final formatter = DartFormatter(
      languageVersion: DartFormatter.latestLanguageVersion,
    );

    void addDart(String path, String source) {
      try {
        files[path] = formatter.format(source);
      } on FormatterException catch (e) {
        diagnostics.add(
          Diagnostic.error(
            code: 'emitted_invalid_dart',
            message: 'Generated $path does not parse: ${e.message}',
          ),
        );
      }
    }

    try {
      final ir = const Lowering().lower(project);
      const emitter = ServerEmitter();

      addDart('lib/handlers.dart', emitter.handlers(ir));
      addDart('bin/server.dart', emitter.server(ir));
      if (project.models.isNotEmpty) {
        // The same file the client uses, verbatim: one definition of what a
        // Todo is, on both sides of the wire.
        addDart('lib/models.dart', const ModelEmitter().emit(project.models));
      }
      files['pubspec.yaml'] = emitter.pubspec(project);
      files['analysis_options.yaml'] = emitter.analysisOptions();
      files['README.md'] = emitter.readme(project, ir);
    } on CodegenException catch (e) {
      diagnostics.add(e.toDiagnostic());
    }

    return ServerGenerationResult(files: files, diagnostics: diagnostics);
  }
}
