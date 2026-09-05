/// Reading and writing Lattice projects on disk.
///
/// Split out from `lattice_core.dart` so that the model, the type system and
/// the validator stay platform-agnostic: the editor compiles for the web,
/// where `dart:io` does not exist.
library;

export 'src/io/project_io.dart';
