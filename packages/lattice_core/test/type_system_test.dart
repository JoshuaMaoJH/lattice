import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

void main() {
  group('TypeParser', () {
    test('parses primitives', () {
      expect(TypeParser.parse('int'), PrimitiveType.int_);
      expect(TypeParser.parse('String'), PrimitiveType.string);
      expect(TypeParser.parse(' bool '), PrimitiveType.bool_);
    });

    test('parses nested generics', () {
      final type = TypeParser.parse('List<Map<String, int>>');
      expect(type.dartName, 'List<Map<String, int>>');
      expect(type, isA<ListType>());
      expect((type as ListType).element, isA<MapType>());
    });

    test('parses nullability', () {
      final type = TypeParser.parse('List<String>?');
      expect(type, isA<NullableType>());
      expect(type.dartName, 'List<String>?');
    });

    test('recognises registered Flutter enums', () {
      expect(TypeParser.parse('MainAxisAlignment'), isA<EnumType>());
    });

    test('treats an unknown name as a user model', () {
      expect(TypeParser.parse('Todo'), const ModelType('Todo'));
    });

    test('rejects malformed input', () {
      expect(() => TypeParser.parse('List<int'),
          throwsA(isA<TypeParseException>()));
      expect(() => TypeParser.parse('Set<int>'),
          throwsA(isA<TypeParseException>()));
      expect(
          () => TypeParser.parse('int??'), throwsA(isA<TypeParseException>()));
      expect(TypeParser.tryParse('List<int'), isNull);
    });

    test('round-trips through dartName', () {
      for (final spec in [
        'int',
        'String?',
        'List<double>',
        'Map<String, List<bool>>',
        'List<Todo>?',
        'Future<String>',
      ]) {
        expect(TypeParser.parse(spec).dartName, spec, reason: spec);
      }
    });
  });

  group('assignability', () {
    test('allows only the documented numeric widening', () {
      expect(PrimitiveType.int_.isAssignableTo(PrimitiveType.double_), isTrue);
      expect(PrimitiveType.int_.isAssignableTo(PrimitiveType.num_), isTrue);
      expect(PrimitiveType.double_.isAssignableTo(PrimitiveType.int_), isFalse);
      expect(PrimitiveType.num_.isAssignableTo(PrimitiveType.int_), isFalse);
    });

    test('accepts a value into a nullable slot but not the reverse', () {
      final nullableInt = TypeParser.parse('int?');
      expect(PrimitiveType.int_.isAssignableTo(nullableInt), isTrue);
      expect(nullableInt.isAssignableTo(PrimitiveType.int_), isFalse);
    });

    test('is covariant in list elements', () {
      expect(
        TypeParser.parse('List<int>')
            .isAssignableTo(TypeParser.parse('List<double>')),
        isTrue,
      );
      expect(
        TypeParser.parse('List<String>')
            .isAssignableTo(TypeParser.parse('List<int>')),
        isFalse,
      );
    });

    test('keeps distinct models apart', () {
      expect(
        const ModelType('Todo').isAssignableTo(const ModelType('User')),
        isFalse,
      );
      expect(
        const ModelType('Todo').isAssignableTo(const ModelType('Todo')),
        isTrue,
      );
    });

    test('never mixes data and event pins', () {
      expect(PrimitiveType.string.isAssignableTo(const EventType()), isFalse);
      expect(const EventType().isAssignableTo(PrimitiveType.string), isFalse);
    });

    test('lets an action ignore a payload it does not need', () {
      expect(
        const EventType(PrimitiveType.string).isAssignableTo(const EventType()),
        isTrue,
      );
      expect(
        const EventType().isAssignableTo(const EventType(PrimitiveType.string)),
        isFalse,
      );
    });
  });

  group('serializability', () {
    test('marks Flutter-only types as not crossing a server boundary', () {
      expect(PrimitiveType.string.isSerializable, isTrue);
      expect(TypeParser.parse('List<int>').isSerializable, isTrue);
      expect(PrimitiveType.color.isSerializable, isFalse);
      expect(const WidgetType().isSerializable, isFalse);
    });
  });

  _nodeShapes();

  group('PinRef', () {
    test('parses plain and indexed references', () {
      expect(PinRef.parse('n_count.value'), const PinRef('n_count', 'value'));
      expect(
        PinRef.parse('n_fmt.args[2]'),
        const PinRef('n_fmt', 'args', index: 2),
      );
    });

    test('round-trips through toString', () {
      for (final source in ['a.b', 'n_fmt.args[0]']) {
        expect(PinRef.parse(source).toString(), source);
      }
    });

    test('drops the index for base lookups', () {
      expect(
        const PinRef('n', 'args', index: 3).base,
        const PinRef('n', 'args'),
      );
    });

    test('rejects malformed references', () {
      expect(() => PinRef.parse('nodeonly'),
          throwsA(isA<ProjectFormatException>()));
    });
  });
}

/// Node pin types that are easy to get subtly wrong.
void _nodeShapes() {
  group('node pin types', () {
    final context = NodeContext(graph: Graph.empty);
    LatticeType outputOf(String type,
        {Map<String, Object?> config = const {}}) {
      final node = GraphNode(id: 'n', type: type, config: config);
      return NodeRegistry.lookup(type)!.output(node, context, 'out')!.type;
    }

    test('Divide yields a double even for int operands, as Dart does', () {
      expect(outputOf('Divide', config: {'dartType': 'int'}),
          PrimitiveType.double_);
      expect(outputOf('IntegerDivide'), PrimitiveType.int_);
    });

    test('arithmetic keeps the configured operand type', () {
      expect(outputOf('Add', config: {'dartType': 'double'}),
          PrimitiveType.double_);
      expect(
          outputOf('Modulo', config: {'dartType': 'int'}), PrimitiveType.int_);
    });

    test('comparisons always yield bool', () {
      for (final type in ['Equals', 'GreaterThan', 'LessOrEqual']) {
        expect(outputOf(type, config: {'dartType': 'double'}),
            PrimitiveType.bool_);
      }
    });
  });
}
