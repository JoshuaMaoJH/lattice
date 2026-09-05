import 'package:code_builder/code_builder.dart';

/// Builds an expression, told whether to emit it as a `const` invocation.
typedef ExpressionBuilder = Expression Function(bool asConst);

/// An expression plus the two facts its parent needs in order to place it:
/// whether it can live in a `const` context, and which signals it reads.
///
/// Const-ness is tracked rather than sprinkled, so `const` lands on the
/// outermost eligible expression exactly where a person would put it (§8) —
/// no redundant inner `const`, no missed opportunities.
final class Emitted {
  Emitted(
    this._build, {
    this.isConst = false,
    this.isCompound = false,
    Set<String>? signalDeps,
  }) : signalDeps = signalDeps ?? const {};

  /// An expression whose source text is the same const or not — a literal, an
  /// identifier, a property access.
  Emitted.plain(
    Expression expression, {
    bool isConst = false,
    bool isCompound = false,
    Set<String>? signalDeps,
  }) : this(
          (_) => expression,
          isConst: isConst,
          isCompound: isCompound,
          signalDeps: signalDeps,
        );

  /// A compile-time constant literal.
  Emitted.constant(Expression expression)
      : this.plain(expression, isConst: true);

  /// A reactive read, e.g. `count.value`.
  Emitted.reactive(Expression expression, Set<String> signals)
      : this.plain(expression, signalDeps: signals);

  final ExpressionBuilder _build;

  /// Whether this is a valid constant expression.
  final bool isConst;

  /// Whether this is an operator expression (`a + b`, `c ? t : f`) and so
  /// needs parentheses when it becomes an operand of another one.
  final bool isCompound;

  /// Graph node ids of the `Signal`s read directly or through inlined
  /// computations. Non-empty means the owning widget needs a rebuild boundary.
  final Set<String> signalDeps;

  bool get isReactive => signalDeps.isNotEmpty;

  /// As an argument of a parent that is itself `const`: the keyword is implied
  /// by the context, so it is left off.
  Expression inContext({required bool parentIsConst}) =>
      _build(isConst && !parentIsConst);

  /// Standing alone — as a statement, a return value, or a non-const argument.
  Expression standalone() => _build(isConst);

  /// Never const, whatever this expression could have been. Used inside a
  /// `Watch` closure, where nothing is constant anyway.
  Expression bare() => _build(false);

  /// Combines the const-ness and dependencies of sub-expressions.
  static ({bool isConst, Set<String> deps}) merge(Iterable<Emitted> parts) {
    var isConst = true;
    final deps = <String>{};
    for (final part in parts) {
      isConst = isConst && part.isConst;
      deps.addAll(part.signalDeps);
    }
    return (isConst: isConst && deps.isEmpty, deps: deps);
  }
}
