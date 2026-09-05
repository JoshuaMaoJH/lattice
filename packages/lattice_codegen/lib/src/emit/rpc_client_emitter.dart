import 'package:code_builder/code_builder.dart';
import 'package:lattice_core/lattice_core.dart';

import '../ir/page_ir.dart';
import 'render.dart';

/// Emits `lib/rpc.dart` in the generated Flutter project: one typed function
/// per server function (§7.7, `Future<R> name(Args)` stubs on the client).
///
/// The graph draws one `Call Server` node; this is the other half of it. The
/// decoding lives here rather than in the calling page, so the page reads as
/// `quote.value = await priceFor(sku.value, quantity.value)` and nothing else.
class RpcClientEmitter {
  const RpcClientEmitter();

  String emit(ProjectIr ir) {
    final project = ir.project;
    final library = Library(
      (b) => b
        ..directives.addAll([
          Directive.import('dart:convert'),
          Directive.import('package:http/http.dart', as: 'http'),
          if (project.models.isNotEmpty) Directive.import('models.dart'),
        ])
        ..body.addAll([
          _baseUrl(project.config),
          _exception(),
          for (final function in ir.serverFunctions) _stub(function.function),
          _call(),
        ]),
    );
    return '$_header\n${formatLibrary(library)}';
  }

  Spec _baseUrl(ProjectConfig config) => Field(
        (f) => f
          ..name = 'serverBaseUrl'
          ..modifier = FieldModifier.constant
          ..docs.addAll([
            '/// Where the server functions live.',
            '///',
            '/// Override at build time with',
            '/// `--dart-define=LATTICE_SERVER=https://…`, so one build serves',
            '/// both a laptop and a deployment.',
          ])
          ..assignment = Code(
            "String.fromEnvironment('LATTICE_SERVER', "
            "defaultValue: '${config.serverUrl}')",
          ),
      );

  Spec _exception() => Class(
        (c) => c
          ..name = 'RpcException'
          ..docs.add('/// The server answered, and what it said was an error.')
          ..implements.add(refer('Exception'))
          ..fields.add(
            Field((f) => f
              ..name = 'message'
              ..modifier = FieldModifier.final$
              ..type = refer('String')),
          )
          ..constructors.add(
            Constructor((ctor) => ctor
              ..constant = true
              ..requiredParameters.add(
                Parameter((p) => p
                  ..name = 'message'
                  ..toThis = true),
              )),
          )
          ..methods.add(
            Method((m) => m
              ..name = 'toString'
              ..returns = refer('String')
              ..annotations.add(refer('override'))
              ..lambda = true
              ..body = const Code('message')),
          ),
      );

  Method _stub(ServerFunction function) => Method(
        (m) => m
          ..name = function.name
          ..modifier = MethodModifier.async
          ..returns = refer('Future<${function.returns.dartName}>')
          ..docs.addAll(['', '/// `POST ${function.route}` — ${function.id}.'])
          ..requiredParameters.addAll([
            for (final parameter in function.parameters)
              Parameter(
                (p) => p
                  ..name = parameter.name
                  ..type = refer(parameter.type.dartName),
              ),
          ])
          ..body = Code('''
final answer = await _call('${function.name}', {
${function.parameters.map((p) => "  '${p.name}': ${_encodeArgument(p)},").join('\n')}
});
return ${_decode(function.returns, 'answer')};'''),
      );

  static String _encodeArgument(FieldDef parameter) => switch (parameter.type) {
        ModelType() => '${parameter.name}.toJson()',
        NullableType(inner: ModelType()) => '${parameter.name}?.toJson()',
        ListType(element: ModelType()) =>
          '[for (final e in ${parameter.name}) e.toJson()]',
        _ => parameter.name,
      };

  static String _decode(LatticeType type, String source) => switch (type) {
        ModelType(:final name) =>
          '$name.fromJson($source! as Map<String, Object?>)',
        ListType(element: ModelType(:final name)) =>
          '[for (final e in $source! as List<Object?>) '
              '$name.fromJson(e as Map<String, Object?>)]',
        PrimitiveType(kind: PrimitiveKind.double$) =>
          '($source! as num).toDouble()',
        NullableType(:final inner) =>
          '$source == null ? null : ${_decode(inner, source)}',
        ListType(:final element) =>
          '[for (final e in $source! as List<Object?>) '
              '${_decode(element, 'e')}]',
        _ => '$source! as ${type.dartName}',
      };

  Method _call() => Method(
        (m) => m
          ..name = '_call'
          ..modifier = MethodModifier.async
          ..returns = refer('Future<Object?>')
          ..docs.addAll([
            '',
            '/// One shape for every call: `POST /rpc/<name>` with a JSON',
            '/// object of arguments, answering `{"result": …}` or',
            '/// `{"error": …}`.',
          ])
          ..requiredParameters.addAll([
            Parameter((p) => p
              ..name = 'name'
              ..type = refer('String')),
            Parameter((p) => p
              ..name = 'arguments'
              ..type = refer('Map<String, Object?>')),
          ])
          ..body = const Code(r'''
final response = await http.post(
  Uri.parse('$serverBaseUrl/rpc/$name'),
  headers: const {'content-type': 'application/json'},
  body: jsonEncode(arguments),
);

final Map<String, Object?> body;
try {
  body = jsonDecode(response.body) as Map<String, Object?>;
} on Object {
  // A proxy or a crash can answer with something that is not ours; say so
  // rather than throwing a cast error at the caller.
  throw RpcException(
    'The server answered ${response.statusCode} with something that is not '
    'a Lattice reply.',
  );
}

final error = body['error'];
if (error != null) throw RpcException('$error');
return body['result'];'''),
      );

  static const _header = '''
// Generated by Lattice — the client half of the project's server functions.
//
// Safe to edit once you have ejected: this is ordinary Dart with no runtime
// dependency on the editor.
''';
}
