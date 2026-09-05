/// Lowers a Lattice project to an intermediate representation and emits
/// formatted, analyzer-clean Dart (§6, §7.5).
///
/// No `dart:io` here: generation is a pure function from a project to a map of
/// files, which is what lets the editor run it on the web. Writing those files
/// out lives in `package:lattice_codegen/io.dart`.
library;

export 'src/codegen_exception.dart';
export 'src/emit/app_emitter.dart';
export 'src/emit/emitted.dart';
export 'src/emit/literals.dart';
export 'src/emit/model_emitter.dart';
export 'src/emit/page_emitter.dart';
export 'src/emit/render.dart';
export 'src/emit/support_files.dart';
export 'src/generator.dart';
export 'src/ir/lowering.dart';
export 'src/ir/page_ir.dart';
export 'src/naming.dart';
