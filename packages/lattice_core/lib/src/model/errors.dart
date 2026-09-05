/// Thrown when a project file is structurally malformed — a missing key, a
/// wrong JSON shape. Semantic problems (bad types, cycles) are *not* errors:
/// they come back as [Diagnostic]s so the editor can keep the project open
/// and highlight them.
class ProjectFormatException implements Exception {
  ProjectFormatException(this.message, {this.path});

  final String message;

  /// JSON pointer-ish location, e.g. `pages[0].graph.nodes[2].type`.
  final String? path;

  @override
  String toString() =>
      'ProjectFormatException${path == null ? '' : ' at $path'}: $message';
}
