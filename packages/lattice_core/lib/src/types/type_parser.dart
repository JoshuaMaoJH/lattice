import 'lattice_type.dart';

/// Thrown when a type string in a project file cannot be understood.
class TypeParseException implements Exception {
  TypeParseException(this.source, this.reason);

  final String source;
  final String reason;

  @override
  String toString() => 'TypeParseException: "$source" — $reason';
}

/// Flutter enums the graph is allowed to talk about.
///
/// Kept as an explicit registry rather than free-form strings so the Inspector
/// can render a dropdown and the validator can reject typos (§7.3).
class EnumRegistry {
  EnumRegistry._();

  static final Map<String, EnumType> _byName = {
    for (final e in _builtins) e.name: e,
  };

  static const List<EnumType> _builtins = [
    EnumType('MainAxisAlignment', [
      'start',
      'end',
      'center',
      'spaceBetween',
      'spaceAround',
      'spaceEvenly',
    ]),
    EnumType('CrossAxisAlignment', [
      'start',
      'end',
      'center',
      'stretch',
      'baseline',
    ]),
    EnumType('MainAxisSize', ['min', 'max']),
    EnumType('TextAlign', [
      'left',
      'right',
      'center',
      'justify',
      'start',
      'end',
    ]),
    EnumType('TextOverflow', ['clip', 'fade', 'ellipsis', 'visible']),
    EnumType('Axis', ['horizontal', 'vertical']),
    EnumType('BoxFit', [
      'fill',
      'contain',
      'cover',
      'fitWidth',
      'fitHeight',
      'none',
      'scaleDown',
    ]),
    EnumType('FontWeight', [
      'w100',
      'w200',
      'w300',
      'w400',
      'w500',
      'w600',
      'w700',
      'w800',
      'w900',
      'normal',
      'bold',
    ]),
    EnumType('TextInputType', [
      'text',
      'multiline',
      'number',
      'phone',
      'emailAddress',
      'url',
    ]),
  ];

  static EnumType? lookup(String name) => _byName[name];

  static Iterable<EnumType> get all => _builtins;

  /// Registers an enum contributed by a plugin node library (R20).
  static void register(EnumType type) => _byName[type.name] = type;
}

/// Parses the Dart-like type spellings used throughout project files, e.g.
/// `List<Map<String, int>>?`.
class TypeParser {
  const TypeParser._();

  static LatticeType parse(String source) {
    final text = source.trim();
    if (text.isEmpty) {
      throw TypeParseException(source, 'empty type');
    }

    if (text.endsWith('?')) {
      final inner = parse(text.substring(0, text.length - 1));
      if (inner is NullableType) {
        throw TypeParseException(source, 'doubly nullable');
      }
      return NullableType(inner);
    }

    final generic = _splitGeneric(text, source);
    if (generic != null) {
      final (name, args) = generic;
      switch (name) {
        case 'List':
          _expectArity(source, args, 1);
          return ListType(parse(args[0]));
        case 'Map':
          _expectArity(source, args, 2);
          return MapType(parse(args[0]), parse(args[1]));
        case 'Future':
          _expectArity(source, args, 1);
          return FutureType(parse(args[0]));
        case 'Event':
          _expectArity(source, args, 1);
          return EventType(parse(args[0]));
        default:
          throw TypeParseException(source, 'unknown generic type "$name"');
      }
    }

    if (text == 'Widget') return const WidgetType();
    if (text == 'Event') return const EventType();

    final primitive = PrimitiveKind.byName(text);
    if (primitive != null) return PrimitiveType(primitive);

    final enumType = EnumRegistry.lookup(text);
    if (enumType != null) return enumType;

    if (!_identifier.hasMatch(text)) {
      throw TypeParseException(source, 'not a valid type name');
    }
    // Anything else is assumed to be a user model; the validator confirms it
    // actually exists in `models/` and reports a precise diagnostic if not.
    return ModelType(text);
  }

  /// Same as [parse] but returns `null` instead of throwing.
  static LatticeType? tryParse(String source) {
    try {
      return parse(source);
    } on TypeParseException {
      return null;
    }
  }

  static final RegExp _identifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

  static void _expectArity(String source, List<String> args, int arity) {
    if (args.length != arity) {
      throw TypeParseException(
        source,
        'expected $arity type argument(s), got ${args.length}',
      );
    }
  }

  /// Splits `Map<String, int>` into `('Map', ['String', ' int'])`.
  /// Returns null when [text] has no type arguments.
  static (String, List<String>)? _splitGeneric(String text, String source) {
    final open = text.indexOf('<');
    if (open < 0) return null;
    if (!text.endsWith('>')) {
      throw TypeParseException(source, 'unbalanced type arguments');
    }

    final name = text.substring(0, open).trim();
    final body = text.substring(open + 1, text.length - 1);

    final args = <String>[];
    var depth = 0;
    var start = 0;
    for (var i = 0; i < body.length; i++) {
      switch (body[i]) {
        case '<':
          depth++;
        case '>':
          depth--;
          if (depth < 0) throw TypeParseException(source, 'unbalanced "<>"');
        case ',':
          if (depth == 0) {
            args.add(body.substring(start, i));
            start = i + 1;
          }
      }
    }
    if (depth != 0) throw TypeParseException(source, 'unbalanced "<>"');
    args.add(body.substring(start));
    return (name, args);
  }
}
