import 'package:dart_style/dart_style.dart';
import 'package:code_builder/code_builder.dart';

import '../ir/page_ir.dart';

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

/// A `Computed` or `Dart Code` node, as a top-level private function.
///
/// The same shape on both sides of the wire: a pure function of its inputs,
/// sitting outside whatever class uses it, so a reader can see at a glance
/// that it touches no state.
Method helperMethod(HelperIr helper) => Method(
      (m) => m
        ..name = helper.name
        // The leading blank keeps consecutive helpers from running their
        // comment onto the previous function's last line.
        ..docs.addAll(['', '// ${helper.nodeId}'])
        ..returns = refer(helper.returnType.dartName)
        ..requiredParameters.addAll([
          for (final parameter in helper.parameters)
            Parameter(
              (p) => p
                ..name = parameter.name
                ..type = refer(parameter.type.dartName),
            ),
        ])
        ..lambda = helper.isExpressionBody
        ..body = Code(helper.body),
    );

/// Renders and formats a whole library.
String formatLibrary(Library library) => DartFormatter(
      languageVersion: DartFormatter.latestLanguageVersion,
    ).format('${library.accept(newEmitter())}');
