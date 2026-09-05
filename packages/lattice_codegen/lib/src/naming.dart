/// Identifier hygiene for generated code.
///
/// Node ids (`n_count`, `w_btn`) are stable and opaque; the names a reader
/// sees (`count`, `_onBtnPressed`) are derived here so generated source reads
/// like something a person wrote (§8).
class Naming {
  const Naming._();

  static const Set<String> _reserved = {
    'abstract', 'as', 'assert', 'async', 'await', 'base', 'break', 'case',
    'catch', 'class', 'const', 'continue', 'covariant', 'default', 'deferred',
    'do', 'dynamic', 'else', 'enum', 'export', 'extends', 'extension',
    'external', 'factory', 'false', 'final', 'finally', 'for', 'function',
    'get', 'hide', 'if', 'implements', 'import', 'in', 'interface', 'is',
    'late', 'library', 'mixin', 'new', 'null', 'on', 'operator', 'part',
    'required', 'rethrow', 'return', 'sealed', 'set', 'show', 'static',
    'super', 'switch', 'sync', 'this', 'throw', 'true', 'try', 'typedef',
    'var', 'void', 'when', 'while', 'with', 'yield',
    // Names already in scope inside a generated State class.
    'build', 'context', 'widget', 'setState', 'dispose', 'initState', 'mounted',
  };

  static final RegExp _separators = RegExp(r'[^A-Za-z0-9]+');
  static final RegExp _idPrefix = RegExp(r'^(n|w|ev|a|p|page|node)_');

  /// `n_count` -> `count`, `todo list` -> `todoList`.
  static String camel(String raw) {
    final parts = _words(raw);
    if (parts.isEmpty) return 'value';
    final head = parts.first.toLowerCase();
    final tail = parts.skip(1).map(_capitalise).join();
    final name = '$head$tail';
    return _guard(_leadingDigitSafe(name));
  }

  /// `page_home` -> `Home`, `todo item` -> `TodoItem`.
  static String pascal(String raw) {
    final parts = _words(raw);
    if (parts.isEmpty) return 'Value';
    return _leadingDigitSafe(parts.map(_capitalise).join());
  }

  /// `HomePage` -> `home_page`.
  static String snake(String raw) => raw
      .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
      .replaceAll(_separators, '_')
      .toLowerCase();

  /// The handler method for a widget callback: `w_btn` + `onPressed` ->
  /// `_onBtnPressed`.
  static String handler(String widgetId, String eventName) {
    final widget = pascal(_stripPrefix(widgetId));
    final event = eventName.startsWith('on')
        ? pascal(eventName.substring(2))
        : pascal(eventName);
    return '_on$widget$event';
  }

  static List<String> _words(String raw) => _stripPrefix(raw)
      .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .split(_separators)
      .where((p) => p.isNotEmpty)
      .toList();

  static String _stripPrefix(String raw) {
    final stripped = raw.replaceFirst(_idPrefix, '');
    return stripped.isEmpty ? raw : stripped;
  }

  static String _capitalise(String word) => word.isEmpty
      ? word
      : word[0].toUpperCase() + word.substring(1).toLowerCase();

  static String _leadingDigitSafe(String name) =>
      RegExp(r'^[0-9]').hasMatch(name) ? 'v$name' : name;

  static String _guard(String name) =>
      _reserved.contains(name) ? '${name}_' : name;
}

/// Hands out unique identifiers, appending `2`, `3`, ... on collision.
class Namer {
  Namer([Iterable<String> reserved = const []]) {
    _taken.addAll(reserved);
  }

  final Set<String> _taken = {};

  String take(String preferred) {
    var candidate = preferred;
    var counter = 2;
    while (!_taken.add(candidate)) {
      candidate = '$preferred$counter';
      counter++;
    }
    return candidate;
  }

  bool isTaken(String name) => _taken.contains(name);
}
