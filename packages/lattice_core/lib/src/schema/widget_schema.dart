import '../types/lattice_type.dart';

enum WidgetCategory {
  layout,
  content,
  input,
  structure,

  /// Repetition and conditionals. These are not Flutter widgets — the compiler
  /// expands them into collection-`for` / collection-`if` in the surrounding
  /// children list, which is what a person writes by hand.
  control,
}

/// How a widget accepts entries from the Hierarchy's `children` array.
enum ChildArity {
  /// Leaf widget.
  none,

  /// Exactly one child, emitted through [WidgetSchema.childrenParam].
  one,

  /// Any number of children.
  many,
}

/// What kind of slot a parameter is.
enum ParamKind {
  /// A plain value: literal, `$expr`, or bound to a graph output.
  value,

  /// A nested widget, e.g. `AppBar.title`.
  widget,

  /// A list of nested widgets, e.g. `AppBar.actions`.
  widgetList,

  /// A callback, wired to an `Event` node.
  callback,
}

/// A parameter Flutter exposes through a controller object rather than as a
/// plain value.
///
/// `TextField` is the canonical case: you cannot hand it a string and expect
/// the field to follow, because the widget owns its own editing state. Codegen
/// therefore allocates the controller, seeds it, keeps it in step with the
/// signal, and disposes it — which is exactly the boilerplate a user came here
/// to avoid writing.
final class ControllerBinding {
  const ControllerBinding({
    required this.type,
    required this.argument,
    required this.property,
  });

  /// The controller class, e.g. `TextEditingController`.
  final String type;

  /// The constructor argument it is passed as, e.g. `controller`.
  final String argument;

  /// The controller property holding the value, e.g. `text`.
  final String property;
}

/// One entry of a widget's parameter schema (§7.1). Drives the Inspector form,
/// the widget's pins in the Graph, and the emitted constructor call.
final class ParamSchema {
  const ParamSchema({
    required this.name,
    required this.type,
    this.kind = ParamKind.value,
    this.required = false,
    this.defaultValue,
    this.bindable = true,
    this.positional = false,
    this.emitInto,
    this.controller,
  });

  final String name;

  /// For [ParamKind.callback] this is the payload the callback delivers
  /// (`void` when it has none).
  final LatticeType type;

  final ParamKind kind;
  final bool required;

  /// JSON-shaped default. When a prop equals it, codegen omits the argument
  /// so generated calls stay as short as hand-written ones.
  final Object? defaultValue;

  /// Whether the Inspector offers the "⚡ bind" button for this parameter.
  final bool bindable;

  /// Emitted as a positional argument, e.g. `Text('hi')`.
  final bool positional;

  /// Folds this parameter into a composite argument instead of emitting it
  /// directly — `TextField.hintText` becomes
  /// `decoration: InputDecoration(hintText: ...)`. The composite's constructor
  /// is named in [WidgetSchema.composites].
  ///
  /// This keeps the Inspector flat (one field per thing the user cares about)
  /// without the emitter growing per-widget special cases.
  final String? emitInto;

  /// Set when the value reaches the widget through a controller rather than
  /// directly. A parameter bound this way does not make its widget reactive:
  /// the controller pushes updates in, so rebuilding on every keystroke would
  /// be both wasteful and cursor-destroying.
  final ControllerBinding? controller;

  @override
  String toString() => '$name: ${type.dartName}';
}

/// A whitelisted Flutter widget (§3.2 — the whitelist is deliberate; anything
/// outside it goes through a `Dart Code` node).
final class WidgetSchema {
  const WidgetSchema({
    required this.type,
    required this.category,
    this.params = const [],
    this.childArity = ChildArity.none,
    this.childrenParam,
    this.mustBeInside,
    this.constructor,
    this.composites = const {},
    this.constCtor = true,
    this.isPseudo = false,
    this.summary = '',
  });

  final String type;
  final WidgetCategory category;
  final List<ParamSchema> params;
  final ChildArity childArity;

  /// The named constructor argument the Hierarchy's `children` map onto —
  /// `child` for `Padding`, `children` for `Column`, `body` for `Scaffold`.
  final String? childrenParam;

  /// Parent widget types this may appear under. `Expanded` outside a `Flex`
  /// is a compile error in Flutter, so the validator rejects it in the tree
  /// instead (§7.1).
  final List<String>? mustBeInside;

  /// Named constructor to emit, e.g. `network` for `Image.network`.
  final String? constructor;

  /// Composite argument name -> the constructor that builds it, for parameters
  /// carrying [ParamSchema.emitInto].
  final Map<String, String> composites;

  /// Whether this entry names a real Flutter constructor at all.
  ///
  /// `ForEach` and `If` do not: they are structural directives that codegen
  /// expands, so nothing here is emitted as `ForEach(...)`.
  final bool isPseudo;

  /// Whether Flutter's constructor for this widget is `const`. Emitting `const`
  /// on one that is not is an analyzer error, so the few exceptions
  /// (`Image.network`, `ListView`) are marked here rather than guessed at.
  final bool constCtor;

  final String summary;

  ParamSchema? param(String name) {
    for (final p in params) {
      if (p.name == name) return p;
    }
    return null;
  }

  Iterable<ParamSchema> get bindableParams =>
      params.where((p) => p.bindable && p.kind == ParamKind.value);

  Iterable<ParamSchema> get callbacks =>
      params.where((p) => p.kind == ParamKind.callback);

  bool get acceptsChildren => childArity != ChildArity.none;

  @override
  String toString() => type;
}
