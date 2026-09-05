import 'dart:io';

import 'package:dart_style/dart_style.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:path/path.dart' as p;

import 'codegen_exception.dart';
import 'emit/app_emitter.dart';
import 'emit/model_emitter.dart';
import 'emit/page_emitter.dart';
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

  /// Directories whose contents are always the generator's to replace.
  static const _ownedDirectories = ['lib/pages'];

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
            'lib/pages/${page.fileName}', const PageEmitter().emit(ir, page));
      }
      addDart('lib/main.dart', const AppEmitter().emit(project));
      if (project.models.isNotEmpty) {
        addDart('lib/models.dart', const ModelEmitter().emit(project.models));
      }

      const support = SupportFiles();
      files['pubspec.yaml'] =
          support.pubspec(project, runtimePath: runtimePath);
      files['analysis_options.yaml'] = support.analysisOptions(project);
      files['README.md'] = support.readme(project);
      files['.gitignore'] = support.gitignore();
      files['.github/workflows/build.yml'] = support.ciWorkflow(project);
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
  Future<List<String>> write(GenerationResult result, String outputDir) async {
    final written = <String>[];

    for (final entry in result.files.entries) {
      final file = File(p.join(outputDir, entry.key));
      await file.parent.create(recursive: true);
      // Skipping an identical write keeps file mtimes stable, so the preview
      // process only hot-reloads pages that actually changed (§7.6).
      if (file.existsSync() && await file.readAsString() == entry.value) {
        continue;
      }
      await file.writeAsString(entry.value);
      written.add(entry.key);
    }

    final custom = Directory(p.join(outputDir, 'lib', 'custom'));
    if (!custom.existsSync()) {
      await custom.create(recursive: true);
      await File(p.join(custom.path, 'README.md'))
          .writeAsString(const SupportFiles().customReadme());
      written.add('lib/custom/README.md');
    }

    await _pruneStale(result, outputDir);
    return written;
  }

  /// Deletes files under generator-owned directories that this run did not
  /// produce, so a renamed or removed page does not leave a stale file behind.
  Future<void> _pruneStale(GenerationResult result, String outputDir) async {
    for (final owned in _ownedDirectories) {
      final directory = Directory(p.join(outputDir, owned));
      if (!directory.existsSync()) continue;
      for (final entity in directory.listSync()) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final relative =
            p.url.joinAll(p.split(p.relative(entity.path, from: outputDir)));
        if (!result.files.containsKey(relative)) {
          await entity.delete();
        }
      }
    }
  }
}
