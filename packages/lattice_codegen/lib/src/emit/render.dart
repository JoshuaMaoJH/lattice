import 'package:code_builder/code_builder.dart';

/// Renders one expression to source text.
///
/// Generated files are emitted with [Allocator.none] and explicit imports, so
/// symbols appear unprefixed — `Scaffold`, not `_i1.Scaffold` (§8, "生成代码
/// 和手写一样好"). Rendering a sub-expression with the same settings therefore
/// produces text that is valid in the file it will be spliced into.
String renderExpression(Expression expression) =>
    expression.accept(newEmitter()).toString();

/// The single emitter configuration used everywhere in this package.
DartEmitter newEmitter() => DartEmitter(
      allocator: Allocator.none,
      orderDirectives: false,
      useNullSafetySyntax: true,
    );

/// Wraps [source] in parentheses when it will be used as an operand.
String asOperand(String source, {required bool isCompound}) =>
    isCompound ? '($source)' : source;
