import 'package:code_builder/code_builder.dart';
import 'package:collection/collection.dart';
import 'package:lattice_core/lattice_core.dart';

import '../codegen_exception.dart';
import 'emitted.dart';

/// Turns the JSON-shaped values held in project files into Dart literals.
///
/// Every value produced here is a compile-time constant, which is what lets a
/// static subtree collapse into a single `const` in the generated `build`
/// method (§8).
class LiteralEmitter {
  const LiteralEmitter({this.models = const []});

  final List<DataModelDef> models;

  Emitted emit(
    LatticeType type,
    Object? value, {
    String? where,
    String? pageId,
    String? widgetId,
    String? nodeId,
  }) {
    Never fail(String reason) => throw CodegenException(
          '$reason${where == null ? '' : ' (at $where)'}',
          pageId: pageId,
          widgetId: widgetId,
          nodeId: nodeId,
        );

    if (value == null) {
      if (type is! NullableType && type != PrimitiveType.dynamic_) {
        fail('null is not a valid ${type.dartName}');
      }
      return Emitted.constant(literalNull);
    }

    switch (type) {
      case NullableType(:final inner):
        return emit(inner, value,
            where: where, pageId: pageId, widgetId: widgetId, nodeId: nodeId);

      case PrimitiveType(kind: PrimitiveKind.string$):
        if (value is! String) fail('expected a string, got $value');
        return Emitted.constant(literalString(value, raw: false));

      case PrimitiveType(kind: PrimitiveKind.bool$):
        if (value is! bool) fail('expected a bool, got $value');
        return Emitted.constant(literalBool(value));

      case PrimitiveType(
          kind:
              PrimitiveKind.int$ || PrimitiveKind.double$ || PrimitiveKind.num$
        ):
        if (value is! num) fail('expected a number, got $value');
        return Emitted.constant(literalNum(value));

      case PrimitiveType(kind: PrimitiveKind.color$):
        return Emitted.constant(_color(value, fail));

      case PrimitiveType(kind: PrimitiveKind.edgeInsets$):
        return _insets(value, fail);

      case PrimitiveType(kind: PrimitiveKind.textStyle$):
        return _textStyle(value, fail);

      case PrimitiveType(kind: PrimitiveKind.iconData$):
        if (value is! String) fail('expected an icon name, got $value');
        return Emitted.constant(
          refer('Icons', _material).property(_identifier(value, fail)),
        );

      case PrimitiveType(kind: PrimitiveKind.alignment$):
        if (value is! String) fail('expected an alignment name, got $value');
        return Emitted.constant(
          refer('Alignment', _material).property(_identifier(value, fail)),
        );

      case PrimitiveType(kind: PrimitiveKind.duration$):
        return _duration(value, fail);

      case PrimitiveType(kind: PrimitiveKind.dynamic$):
        return _inferred(value, fail);

      case PrimitiveType(kind: PrimitiveKind.void$):
        fail('void has no values');

      case EnumType(:final name, :final values):
        if (value is! String) fail('expected one of ${values.join(", ")}');
        if (!values.contains(value)) {
          fail('"$value" is not a $name; expected one of ${values.join(", ")}');
        }
        return Emitted.constant(
          refer(name, _material).property(value),
        );

      case ListType(:final element):
        if (value is! List) fail('expected a list, got $value');
        final items = [
          for (final item in value)
            emit(element, item,
                where: where,
                pageId: pageId,
                widgetId: widgetId,
                nodeId: nodeId),
        ];
        return Emitted(
          (asConst) => asConst
              ? literalConstList(
                  [for (final i in items) i.inContext(parentIsConst: true)])
              : literalList(
                  [for (final i in items) i.inContext(parentIsConst: false)]),
          isConst: Emitted.merge(items).isConst,
        );

      case MapType(key: final keyType, value: final valueType):
        if (value is! Map) fail('expected a map, got $value');
        final entries = <Emitted, Emitted>{
          for (final entry in value.entries)
            emit(keyType, entry.key, where: where): emit(valueType, entry.value,
                where: where,
                pageId: pageId,
                widgetId: widgetId,
                nodeId: nodeId),
        };
        final parts = [...entries.keys, ...entries.values];
        return Emitted(
          (asConst) {
            final built = {
              for (final e in entries.entries)
                e.key.inContext(parentIsConst: asConst):
                    e.value.inContext(parentIsConst: asConst),
            };
            return asConst ? literalConstMap(built) : literalMap(built);
          },
          isConst: Emitted.merge(parts).isConst,
        );

      case ModelType(:final name):
        return _model(name, value, fail,
            pageId: pageId, widgetId: widgetId, nodeId: nodeId);

      case WidgetType():
        fail('a widget cannot be written as a literal');

      case FutureType():
        fail('a Future cannot be written as a literal');

      case EventType():
        fail('an event cannot be written as a literal');
    }
  }

  // ---------------------------------------------------------------------------

  static const _material = 'package:flutter/material.dart';

  Expression _color(Object? value, Never Function(String) fail) {
    int argb;
    if (value is int) {
      argb = value;
    } else if (value is String) {
      final text = value.trim();
      if (text.startsWith('#')) {
        final hex = text.substring(1);
        final parsed = int.tryParse(hex, radix: 16);
        if (parsed == null) fail('"$text" is not a hex colour');
        argb = hex.length <= 6 ? 0xFF000000 | parsed : parsed;
      } else {
        // A Material palette name, e.g. "blue".
        return refer('Colors', _material).property(_identifier(text, fail));
      }
    } else {
      fail('expected a colour, got $value');
    }
    final hex = argb.toRadixString(16).padLeft(8, '0').toUpperCase();
    return refer('Color', _material)
        .newInstance([CodeExpression(Code('0x$hex'))]);
  }

  Emitted _insets(Object? value, Never Function(String) fail) {
    Expression build(String ctor, Map<String, Expression> args, bool asConst) {
      final target = refer('EdgeInsets', _material);
      return asConst
          ? target.constInstanceNamed(ctor, const [], args)
          : target.newInstanceNamed(ctor, const [], args);
    }

    if (value is num) {
      return Emitted(
        (asConst) {
          final target = refer('EdgeInsets', _material);
          return asConst
              ? target.constInstanceNamed('all', [literalNum(value)])
              : target.newInstanceNamed('all', [literalNum(value)]);
        },
        isConst: true,
      );
    }
    if (value is Map) {
      final map = value.cast<String, Object?>();
      num? pick(String key) => map[key] is num ? map[key]! as num : null;

      final horizontal = pick('horizontal');
      final vertical = pick('vertical');
      if (horizontal != null || vertical != null) {
        return Emitted(
          (asConst) => build(
              'symmetric',
              {
                if (horizontal != null) 'horizontal': literalNum(horizontal),
                if (vertical != null) 'vertical': literalNum(vertical),
              },
              asConst),
          isConst: true,
        );
      }
      final sides = {
        for (final side in const ['left', 'top', 'right', 'bottom'])
          if (pick(side) != null) side: literalNum(pick(side)!),
      };
      if (sides.isNotEmpty) {
        return Emitted((asConst) => build('only', sides, asConst),
            isConst: true);
      }
    }
    fail('expected a number or an EdgeInsets object, got $value');
  }

  Emitted _textStyle(Object? value, Never Function(String) fail) {
    if (value is! Map) fail('expected a TextStyle object, got $value');
    final map = value.cast<String, Object?>();
    final args = <String, Expression>{};

    final fontSize = map['fontSize'];
    if (fontSize is num) args['fontSize'] = literalNum(fontSize);

    final fontWeight = map['fontWeight'];
    if (fontWeight is String) {
      args['fontWeight'] = refer('FontWeight', _material)
          .property(_identifier(fontWeight, fail));
    }

    final color = map['color'];
    if (color != null) args['color'] = _color(color, fail);

    final letterSpacing = map['letterSpacing'];
    if (letterSpacing is num) args['letterSpacing'] = literalNum(letterSpacing);

    final height = map['height'];
    if (height is num) args['height'] = literalNum(height);

    final fontStyle = map['fontStyle'];
    if (fontStyle is String) {
      args['fontStyle'] =
          refer('FontStyle', _material).property(_identifier(fontStyle, fail));
    }

    return Emitted(
      (asConst) => asConst
          ? refer('TextStyle', _material).constInstance(const [], args)
          : refer('TextStyle', _material).newInstance(const [], args),
      isConst: true,
    );
  }

  Emitted _duration(Object? value, Never Function(String) fail) {
    if (value is num) {
      return Emitted(
        (asConst) {
          final args = {'milliseconds': literalNum(value)};
          return asConst
              ? refer('Duration').constInstance(const [], args)
              : refer('Duration').newInstance(const [], args);
        },
        isConst: true,
      );
    }
    if (value is Map) {
      final args = <String, Expression>{
        for (final unit in const [
          'days',
          'hours',
          'minutes',
          'seconds',
          'milliseconds',
          'microseconds',
        ])
          if (value[unit] is num) unit: literalNum(value[unit]! as num),
      };
      if (args.isNotEmpty) {
        return Emitted(
          (asConst) => asConst
              ? refer('Duration').constInstance(const [], args)
              : refer('Duration').newInstance(const [], args),
          isConst: true,
        );
      }
    }
    fail('expected milliseconds or a Duration object, got $value');
  }

  Emitted _model(
    String name,
    Object? value,
    Never Function(String) fail, {
    String? pageId,
    String? widgetId,
    String? nodeId,
  }) {
    final model = models.where((m) => m.name == name).firstOrNull;
    if (model == null) fail('unknown model "$name"');
    if (value is! Map) fail('expected an object for $name, got $value');
    final map = value.cast<String, Object?>();

    final args = <String, Emitted>{};
    for (final field in model.fields) {
      final raw =
          map.containsKey(field.name) ? map[field.name] : field.defaultValue;
      if (raw == null && field.type is! NullableType) {
        fail('$name.${field.name} has no value and no default');
      }
      args[field.name] = emit(field.type, raw,
          where: '$name.${field.name}',
          pageId: pageId,
          widgetId: widgetId,
          nodeId: nodeId);
    }

    final merged = Emitted.merge(args.values);
    return Emitted(
      (asConst) {
        final built = {
          for (final e in args.entries)
            e.key: e.value.inContext(parentIsConst: asConst),
        };
        final target = refer(name);
        return asConst
            ? target.constInstance(const [], built)
            : target.newInstance(const [], built);
      },
      isConst: merged.isConst,
      signalDeps: merged.deps,
    );
  }

  /// Best-effort literal for a `dynamic` slot — used by `Format` arguments and
  /// `Const` nodes that did not declare a type.
  Emitted _inferred(Object? value, Never Function(String) fail) =>
      switch (value) {
        final String s => Emitted.constant(literalString(s, raw: false)),
        final bool b => Emitted.constant(literalBool(b)),
        final num n => Emitted.constant(literalNum(n)),
        final List<Object?> l => Emitted(
            (asConst) {
              final items = [
                for (final i in l)
                  _inferred(i, fail).inContext(parentIsConst: asConst)
              ];
              return asConst ? literalConstList(items) : literalList(items);
            },
            isConst: true,
          ),
        final Map<String, Object?> m => Emitted(
            (asConst) {
              final built = {
                for (final e in m.entries)
                  literalString(e.key): _inferred(e.value, fail)
                      .inContext(parentIsConst: asConst),
              };
              return asConst ? literalConstMap(built) : literalMap(built);
            },
            isConst: true,
          ),
        _ => fail('cannot express $value as a literal'),
      };

  static String _identifier(String value, Never Function(String) fail) {
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value)) {
      fail('"$value" is not a valid Dart identifier');
    }
    return value;
  }
}
