enum DiagnosticSeverity { error, warning, info }

/// A validation finding, addressed at a specific place in the project so the
/// editor can highlight it in the tree or on the canvas (R15).
final class Diagnostic {
  const Diagnostic({
    required this.severity,
    required this.code,
    required this.message,
    this.pageId,
    this.nodeId,
    this.widgetId,
    this.pin,
  });

  const Diagnostic.error({
    required String code,
    required String message,
    String? pageId,
    String? nodeId,
    String? widgetId,
    String? pin,
  }) : this(
          severity: DiagnosticSeverity.error,
          code: code,
          message: message,
          pageId: pageId,
          nodeId: nodeId,
          widgetId: widgetId,
          pin: pin,
        );

  const Diagnostic.warning({
    required String code,
    required String message,
    String? pageId,
    String? nodeId,
    String? widgetId,
    String? pin,
  }) : this(
          severity: DiagnosticSeverity.warning,
          code: code,
          message: message,
          pageId: pageId,
          nodeId: nodeId,
          widgetId: widgetId,
          pin: pin,
        );

  final DiagnosticSeverity severity;

  /// Stable machine-readable id, e.g. `type_mismatch`. Tests assert on this
  /// rather than on message wording.
  final String code;

  final String message;
  final String? pageId;
  final String? nodeId;
  final String? widgetId;
  final String? pin;

  bool get isError => severity == DiagnosticSeverity.error;

  String get location {
    final parts = [
      if (pageId != null) pageId!,
      if (widgetId != null) '#$widgetId',
      if (nodeId != null) nodeId!,
      if (pin != null) '.$pin',
    ];
    return parts.isEmpty ? '<project>' : parts.join(' ');
  }

  @override
  String toString() => '[${severity.name}] $location: $message ($code)';
}

/// The outcome of validating a project.
final class ValidationResult {
  ValidationResult(List<Diagnostic> diagnostics)
      : diagnostics = List.unmodifiable(diagnostics);

  final List<Diagnostic> diagnostics;

  bool get isValid => errors.isEmpty;

  Iterable<Diagnostic> get errors => diagnostics.where((d) => d.isError);

  Iterable<Diagnostic> get warnings =>
      diagnostics.where((d) => d.severity == DiagnosticSeverity.warning);

  Iterable<Diagnostic> withCode(String code) =>
      diagnostics.where((d) => d.code == code);

  @override
  String toString() => diagnostics.isEmpty
      ? 'ValidationResult(clean)'
      : 'ValidationResult(\n  ${diagnostics.join('\n  ')}\n)';
}
