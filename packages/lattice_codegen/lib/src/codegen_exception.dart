import 'package:lattice_core/lattice_core.dart';

/// Raised when lowering hits something the validator should have caught.
///
/// Every throw site is a place where a project could only be malformed if it
/// bypassed [Validator], so the message doubles as an assertion about the
/// validator's coverage.
class CodegenException implements Exception {
  CodegenException(this.message, {this.pageId, this.nodeId, this.widgetId});

  final String message;
  final String? pageId;
  final String? nodeId;
  final String? widgetId;

  Diagnostic toDiagnostic() => Diagnostic.error(
        code: 'codegen_failed',
        message: message,
        pageId: pageId,
        nodeId: nodeId,
        widgetId: widgetId,
      );

  @override
  String toString() {
    final at = [
      if (pageId != null) pageId!,
      if (widgetId != null) '#$widgetId',
      if (nodeId != null) nodeId!,
    ].join(' ');
    return 'CodegenException${at.isEmpty ? '' : ' at $at'}: $message';
  }
}
