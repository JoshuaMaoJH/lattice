import 'dart:convert';

import '../model/data_model.dart';
import '../model/errors.dart';
import '../model/graph.dart';
import '../model/graph_unit.dart';
import '../model/hierarchy.dart';
import '../model/page.dart';
import '../model/pin_ref.dart';
import '../model/prefab.dart';
import '../model/server_function.dart';
import '../types/lattice_type.dart';
import '../types/type_parser.dart';

/// Reads the `.lat` form back into a unit (R18).
///
/// Hand-written rather than generated from a grammar, because the format is
/// deliberately small and the error messages matter more than the parser does:
/// this is a file people edit, so "line 12: expected `->`" has to be what they
/// get, not a stack trace.
class LatReader {
  const LatReader();

  GraphUnit read(String source) => _Parser(source).parseUnit();
}

/// A parse failure with the line it happened on.
class LatFormatException extends ProjectFormatException {
  LatFormatException(super.message, int line) : super(path: 'line ${line + 1}');
}

final class _Line {
  _Line(this.number, String raw)
      : indent = raw.length - raw.trimLeft().length,
        text = raw.trim();

  final int number;
  final int indent;
  final String text;
}

class _Parser {
  _Parser(String source)
      : _lines = [
          for (final (i, raw) in const LineSplitter().convert(source).indexed)
            if (raw.trim().isNotEmpty && !raw.trim().startsWith('//'))
              _Line(i, raw),
        ];

  final List<_Line> _lines;
  int _at = 0;

  _Line get _current => _lines[_at];
  bool get _done => _at >= _lines.length;

  Never _fail(String message, [int? line]) =>
      throw LatFormatException(message, line ?? (_done ? 0 : _current.number));

  GraphUnit parseUnit() {
    if (_done) _fail('empty file', 0);
    final header = _Tokens(_current.text, _current.number);
    final kind = header.word();
    final name = header.name();
    final id = header.hash();

    final parameters = <FieldDef>[];
    var route = '/';
    var isHome = false;
    LatticeType returns = PrimitiveType.void_;

    while (header.hasMore) {
      switch (header.word()) {
        case 'route':
          route = header.value() as String;
        case 'home':
          isHome = true;
        case 'returns':
          returns = header.type();
        case 'param':
          parameters.add(header.parameter());
        case final other:
          _fail('unexpected "$other" in a $kind header', header.line);
      }
    }
    _at++;

    WidgetNode? hierarchy;
    final nodes = <GraphNode>[];
    final edges = <Edge>[];
    final layout = <String, CanvasPos>{};

    while (!_done) {
      final section = _current.text;
      final indent = _current.indent;
      // Captured before advancing: the error belongs to the section line, not
      // to whatever happens to follow it.
      final at = _current.number;
      _at++;
      switch (section) {
        case 'hierarchy':
          hierarchy = _widget(indent + 2).node;
        case 'graph':
          while (!_done && _current.indent > indent) {
            nodes.add(_node());
          }
        case 'wires':
          while (!_done && _current.indent > indent) {
            edges.add(_edge());
          }
        case 'layout':
          while (!_done && _current.indent > indent) {
            final entry = _position();
            layout[entry.key] = entry.value;
          }
        default:
          _fail('unknown section "$section"', at);
      }
    }

    final graph = Graph(nodes: nodes, edges: edges);
    switch (kind) {
      case 'page':
        if (hierarchy == null) _fail('a page needs a hierarchy', 0);
        return Page(
          id: id,
          name: name,
          route: route,
          isHome: isHome,
          parameters: parameters,
          hierarchy: hierarchy,
          graph: graph,
          layout: layout,
        );
      case 'prefab':
        if (hierarchy == null) _fail('a prefab needs a hierarchy', 0);
        return Prefab(
          id: id,
          name: name,
          parameters: parameters,
          hierarchy: hierarchy,
          graph: graph,
          layout: layout,
        );
      case 'server':
        return ServerFunction(
          id: id,
          name: name,
          returns: returns,
          parameters: parameters,
          graph: graph,
          layout: layout,
        );
      default:
        _fail('"$kind" is not a unit kind — try page, prefab or server', 0);
    }
  }

  /// One widget and everything nested under it.
  ({String? slot, WidgetNode node}) _widget(int indent) {
    final line = _current;
    final tokens = _Tokens(line.text, line.number);
    final slot = tokens.slotName();
    final type = tokens.word();
    final id = tokens.hash();
    final props = <String, PropValue>{};
    while (tokens.hasMore) {
      final entry = tokens.propEntry();
      props[entry.key] = entry.value;
    }
    _at++;

    final children = <WidgetNode>[];
    while (!_done && _current.indent > line.indent) {
      // `name:` on its own line opens a list slot.
      final listSlot = _listSlot(_current.text);
      if (listSlot != null) {
        final slotIndent = _current.indent;
        _at++;
        final widgets = <WidgetNode>[];
        while (!_done && _current.indent > slotIndent) {
          widgets.add(_widget(_current.indent).node);
        }
        props[listSlot] = WidgetListProp(widgets);
        continue;
      }
      final child = _widget(_current.indent);
      if (child.slot != null) {
        props[child.slot!] = WidgetProp(child.node);
      } else {
        children.add(child.node);
      }
    }

    return (
      slot: slot,
      node: WidgetNode(id: id, type: type, props: props, children: children),
    );
  }

  static final _listSlotPattern = RegExp(r'^([A-Za-z_][A-Za-z0-9_]*):$');

  String? _listSlot(String text) => _listSlotPattern.firstMatch(text)?.group(1);

  GraphNode _node() {
    final tokens = _Tokens(_current.text, _current.number);
    final type = tokens.word();
    final id = tokens.hash();
    final config = <String, Object?>{};
    while (tokens.hasMore) {
      final entry = tokens.configEntry();
      config[entry.key] = entry.value;
    }
    _at++;
    return GraphNode(id: id, type: type, config: config);
  }

  Edge _edge() {
    final parts = _current.text.split('->');
    if (parts.length != 2) _fail('a wire reads "from.pin -> to.pin"');
    // PinRef.parse throws on a malformed reference, which is the message we
    // want anyway; the line number comes from the wrapper below.
    final Edge edge;
    try {
      edge = Edge(
        PinRef.parse(parts[0].trim()),
        PinRef.parse(parts[1].trim()),
      );
    } on Object {
      _fail('a wire endpoint reads "node.pin"');
    }
    _at++;
    return edge;
  }

  MapEntry<String, CanvasPos> _position() {
    final parts = _current.text.split('@');
    if (parts.length != 2) _fail('a position reads "node @ x,y"');
    final coordinates = parts[1].trim().split(',');
    if (coordinates.length != 2) _fail('a position reads "node @ x,y"');
    final x = double.tryParse(coordinates[0].trim());
    final y = double.tryParse(coordinates[1].trim());
    if (x == null || y == null) _fail('a position needs two numbers');
    final id = parts[0].trim();
    _at++;
    return MapEntry(id, CanvasPos(x, y));
  }
}

/// A cursor over one line's tokens.
class _Tokens {
  _Tokens(this._text, this.line);

  final String _text;
  final int line;
  int _at = 0;

  bool get hasMore {
    _skipSpace();
    return _at < _text.length;
  }

  Never _fail(String message) => throw LatFormatException(message, line);

  void _skipSpace() {
    while (_at < _text.length && _text[_at] == ' ') {
      _at++;
    }
  }

  /// `name:` before a widget type, when there is one.
  String? slotName() {
    final save = _at;
    _skipSpace();
    final start = _at;
    while (_at < _text.length && RegExp(r'[A-Za-z0-9_]').hasMatch(_text[_at])) {
      _at++;
    }
    if (_at < _text.length && _text[_at] == ':' && _at > start) {
      final name = _text.substring(start, _at);
      _at++;
      return name;
    }
    _at = save;
    return null;
  }

  /// A unit's name: a bare word where that is unambiguous, quoted otherwise.
  /// The writer picks whichever reads better, so the reader takes both.
  String name() {
    _skipSpace();
    if (_at < _text.length && _text[_at] == '"') return value()! as String;
    return word();
  }

  String word() {
    _skipSpace();
    final start = _at;
    while (_at < _text.length && _text[_at] != ' ') {
      _at++;
    }
    if (start == _at) _fail('expected a word');
    return _text.substring(start, _at);
  }

  String hash() {
    _skipSpace();
    if (_at >= _text.length || _text[_at] != '#') {
      _fail('expected an id, written #like_this');
    }
    _at++;
    final start = _at;
    while (_at < _text.length && _text[_at] != ' ') {
      _at++;
    }
    if (start == _at) _fail('an id cannot be empty');
    return _text.substring(start, _at);
  }

  LatticeType type() {
    final spelling = word();
    final parsed = TypeParser.tryParse(spelling);
    if (parsed == null) _fail('"$spelling" is not a type');
    return parsed;
  }

  /// `name: Type` or `name: Type = default`.
  FieldDef parameter() {
    final name = word().replaceAll(':', '');
    final declared = type();
    Object? fallback;
    final save = _at;
    _skipSpace();
    if (_at < _text.length && _text[_at] == '=') {
      _at++;
      fallback = value();
    } else {
      _at = save;
    }
    return FieldDef(name: name, type: declared, defaultValue: fallback);
  }

  MapEntry<String, Object?> configEntry() {
    final key = _key();
    return MapEntry(key, value());
  }

  MapEntry<String, PropValue> propEntry() {
    final key = _key();
    _skipSpace();
    if (_at >= _text.length) _fail('"$key" has no value');
    switch (_text[_at]) {
      case '<':
        _at++;
        final spelling = word();
        try {
          return MapEntry(key, BindProp(PinRef.parse(spelling)));
        } on Object {
          _fail('"$spelling" is not a pin — a binding reads "<node.pin"');
        }
      case '!':
        _at++;
        return MapEntry(key, EventProp(word()));
      case '`':
        _at++;
        final start = _at;
        while (_at < _text.length && _text[_at] != '`') {
          _at++;
        }
        if (_at >= _text.length) _fail('unterminated expression');
        final code = _text.substring(start, _at).replaceAll(r'\`', '`');
        _at++;
        return MapEntry(key, ExprProp(code));
      default:
        return MapEntry(key, LiteralProp(value()));
    }
  }

  String _key() {
    _skipSpace();
    final start = _at;
    while (_at < _text.length && _text[_at] != '=') {
      _at++;
    }
    if (_at >= _text.length) _fail('expected "name=value"');
    final key = _text.substring(start, _at).trim();
    _at++;
    return key;
  }

  /// A JSON value. Reusing JSON keeps strings, numbers, lists and maps
  /// unambiguous rather than inventing a second literal syntax to get wrong.
  Object? value() {
    _skipSpace();
    if (_at >= _text.length) _fail('expected a value');
    final start = _at;
    final first = _text[_at];
    if (first == '"' || first == '[' || first == '{') {
      _at = _matching(start);
    } else {
      while (_at < _text.length && _text[_at] != ' ') {
        _at++;
      }
    }
    final raw = _text.substring(start, _at);
    try {
      return jsonDecode(raw);
    } on FormatException {
      _fail('"$raw" is not a value');
    }
  }

  /// Walks to the end of a bracketed or quoted run, so a value containing
  /// spaces is one token.
  int _matching(int start) {
    final open = _text[start];
    if (open == '"') {
      var i = start + 1;
      while (i < _text.length) {
        if (_text[i] == r'\') {
          i += 2;
          continue;
        }
        if (_text[i] == '"') return i + 1;
        i++;
      }
      _fail('unterminated string');
    }
    final close = open == '[' ? ']' : '}';
    var depth = 0;
    var i = start;
    var inString = false;
    while (i < _text.length) {
      final c = _text[i];
      if (inString) {
        if (c == r'\') {
          i += 2;
          continue;
        }
        if (c == '"') inString = false;
      } else if (c == '"') {
        inString = true;
      } else if (c == open) {
        depth++;
      } else if (c == close) {
        depth--;
        if (depth == 0) return i + 1;
      }
      i++;
    }
    _fail('unterminated $open');
  }
}
