/// Project model, type system, schema registries and validation for Lattice.
///
/// Pure Dart with no Flutter dependency — and no `dart:io` either, so the
/// editor can also be compiled for the web. Reading and writing project
/// directories lives in `package:lattice_core/io.dart`.
///
/// The editor, the code generator, the CLI and the tests all share one
/// definition of what a project *is* (§6, "分层").
library;

export 'src/model/data_model.dart';
export 'src/model/errors.dart';
export 'src/model/graph.dart';
export 'src/model/graph_unit.dart';
export 'src/model/hierarchy.dart';
export 'src/model/json_utils.dart' show asObj, pruneEmpty, sortedKeys;
export 'src/model/page.dart';
export 'src/model/pin_ref.dart';
export 'src/model/prefab.dart';
export 'src/model/project.dart';
export 'src/model/server_function.dart';
export 'src/model/widget_unit.dart';
export 'src/model/custom_node.dart';
export 'src/model/starter.dart';
export 'src/text/lat_reader.dart';
export 'src/text/lat_writer.dart';
export 'src/schema/node_lookup.dart';
export 'src/schema/node_registry.dart';
export 'src/schema/node_schema.dart';
export 'src/schema/pin_schema.dart';
export 'src/schema/widget_lookup.dart';
export 'src/schema/widget_registry.dart';
export 'src/schema/widget_schema.dart';
export 'src/types/lattice_type.dart';
export 'src/types/type_parser.dart';
export 'src/validation/diagnostic.dart';
export 'src/validation/scope.dart';
export 'src/validation/validator.dart';
