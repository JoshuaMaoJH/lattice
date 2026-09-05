import 'dart:io';

import 'package:lattice_core/lattice_core.dart';

/// Terminal output for the CLI. ANSI colour is used only when stdout is a
/// terminal, so piping into a file or a CI log stays readable.
class Console {
  Console({bool? colour}) : _colour = colour ?? stdout.supportsAnsiEscapes;

  final bool _colour;

  String _wrap(String code, String text) =>
      _colour ? '\x1B[${code}m$text\x1B[0m' : text;

  String bold(String text) => _wrap('1', text);
  String dim(String text) => _wrap('2', text);
  String red(String text) => _wrap('31', text);
  String yellow(String text) => _wrap('33', text);
  String green(String text) => _wrap('32', text);
  String cyan(String text) => _wrap('36', text);

  void info(String message) => stdout.writeln(message);

  void step(String message) => stdout.writeln('${cyan('•')} $message');

  void success(String message) => stdout.writeln('${green('✓')} $message');

  void warn(String message) => stderr.writeln('${yellow('!')} $message');

  void error(String message) => stderr.writeln('${red('✗')} $message');

  /// Prints diagnostics grouped by severity, each with the node or widget id
  /// that produced it so it can be found in the editor (R15).
  void diagnostics(Iterable<Diagnostic> items) {
    final list = items.toList();
    if (list.isEmpty) return;

    for (final diagnostic in list) {
      final marker = switch (diagnostic.severity) {
        DiagnosticSeverity.error => red('error'),
        DiagnosticSeverity.warning => yellow('warning'),
        DiagnosticSeverity.info => cyan('info'),
      };
      stderr.writeln(
        '  $marker ${bold(diagnostic.location)}  ${diagnostic.message} '
        '${dim('(${diagnostic.code})')}',
      );
    }
  }
}
