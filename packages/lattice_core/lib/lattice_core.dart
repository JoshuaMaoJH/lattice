/// Project model, type system, schema registries and validation for Lattice.
///
/// Pure Dart with no Flutter dependency, so the editor, the code generator,
/// the CLI and the tests all share one definition of what a project *is*
/// (§6, "分层").
library;

export 'src/io/project_io.dart';
export 'src/model/data_model.dart';
export 'src/model/errors.dart';
export 'src/model/graph.dart';
export 'src/model/hierarchy.dart';
export 'src/model/json_utils.dart' show asObj, pruneEmpty, sortedKeys;
export 'src/model/page.dart';
export 'src/model/pin_ref.dart';
export 'src/model/project.dart';
export 'src/schema/node_registry.dart';
export 'src/schema/node_schema.dart';
export 'src/schema/pin_schema.dart';
export 'src/schema/widget_registry.dart';
export 'src/schema/widget_schema.dart';
export 'src/types/lattice_type.dart';
export 'src/types/type_parser.dart';
export 'src/validation/diagnostic.dart';
export 'src/validation/scope.dart';
export 'src/validation/validator.dart';
