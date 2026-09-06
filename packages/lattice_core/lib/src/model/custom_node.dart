import '../schema/node_schema.dart';
import '../types/lattice_type.dart';
import '../types/type_parser.dart';
import 'json_utils.dart';

/// One socket on a project-defined node.
final class CustomPin {
  const CustomPin({required this.name, required this.type});

  final String name;
  final LatticeType type;

  factory CustomPin.fromJson(Map<String, Object?> json, String path) =>
      CustomPin(
        name: json.strOr('name', ''),
        type: TypeParser.tryParse(json.strOr('type', 'dynamic')) ??
            PrimitiveType.dynamic_,
      );

  Map<String, Object?> toJson() => {'name': name, 'type': type.dartName};
}

/// A node contributed by the project rather than built in (R20).
///
/// The point of R20 is that "built in" and "mine" should not be different
/// kinds of thing. A definition here becomes a [NodeSchema] like any other,
/// goes through the same validator, and lowers through the same path — the
/// only difference is that its body is a template instead of a `case` in the
/// compiler.
///
/// Two categories are allowed, because they are the two the reactive model
/// distinguishes (§5, rule 2):
///
/// * `compute` — pure, one output, [template] is an **expression**.
/// * `action`  — effectful, no outputs, `exec`/`next` pins, [template] is one
///   or more **statements**.
///
/// A project-defined `state` node would be a second source of truth for
/// mutable state, and a `control` node would need its own lowering; neither is
/// a template substitution, so neither is offered.
final class CustomNodeDef {
  const CustomNodeDef({
    required this.type,
    required this.category,
    required this.template,
    this.summary = '',
    this.inputs = const [],
    this.outputs = const [],
    this.imports = const [],
  });

  final String type;
  final NodeCategory category;

  /// Dart source with `{pin}` placeholders, one per input name.
  ///
  /// Substitution is textual and the substituted expression is parenthesised,
  /// so `{a} * {b}` cannot be re-associated by an input that is itself a sum.
  final String template;

  final String summary;
  final List<CustomPin> inputs;
  final List<CustomPin> outputs;

  /// Imports the template needs, e.g. `dart:math`. Emitted into the page.
  final List<String> imports;

  bool get isAction => category == NodeCategory.action;

  factory CustomNodeDef.fromJson(Map<String, Object?> json, String path) =>
      CustomNodeDef(
        type: json.strOr('type', ''),
        category: json.strOr('category', 'compute') == 'action'
            ? NodeCategory.action
            : NodeCategory.compute,
        template: json.strOr('template', ''),
        summary: json.strOr('summary', ''),
        inputs: _pins(json, 'inputs', path),
        outputs: _pins(json, 'outputs', path),
        imports: [
          for (final raw in json.arrOrEmpty('imports', path))
            if (raw is String) raw,
        ],
      );

  Map<String, Object?> toJson() => pruneEmpty({
        'type': type,
        'category': isAction ? 'action' : 'compute',
        'summary': summary,
        'inputs': [for (final p in inputs) p.toJson()],
        'outputs': [for (final p in outputs) p.toJson()],
        'imports': imports,
        'template': template,
      });

  /// The placeholders the template actually mentions.
  Set<String> get placeholders =>
      _placeholder.allMatches(template).map((m) => m.group(1)!).toSet();

  static final RegExp _placeholder = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}');

  static List<CustomPin> _pins(
    Map<String, Object?> json,
    String key,
    String path,
  ) =>
      [
        for (final (i, raw) in json.arrOrEmpty(key, path).indexed)
          if (raw is Map<String, Object?>)
            CustomPin.fromJson(raw, '$path.$key[$i]'),
      ];
}
