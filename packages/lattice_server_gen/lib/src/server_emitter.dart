import 'package:code_builder/code_builder.dart';
import 'package:lattice_codegen/lattice_codegen.dart';
import 'package:lattice_core/lattice_core.dart';

/// Emits the server side of a project's `@server` subgraphs (§7.7).
///
/// The output is a plain Dart program: `dart run bin/server.dart` and it is up.
/// That matters more than it sounds — a backend you cannot start without first
/// installing a second code generator is not the "一种语言、一张图、前后端"
/// the proposal is after (ADR-012).
class ServerEmitter {
  const ServerEmitter();

  /// `lib/handlers.dart` — one Dart function per server function, plus the
  /// JSON decoding that gets the arguments there.
  String handlers(ProjectIr ir) {
    final library = Library(
      (b) => b
        ..directives.addAll([
          // Only when a function actually decodes JSON itself; the routing in
          // bin/server.dart does its own.
          if (_decodesJson(ir)) Directive.import('dart:convert'),
          if (ir.project.models.isNotEmpty) Directive.import('models.dart'),
          for (final import in _extraImports(ir)) Directive.import(import),
        ])
        ..body.addAll([
          _unknownRpc(),
          _missingArgument(),
          _argumentReader(),
          for (final function in ir.serverFunctions) ..._functionOf(function),
          _dispatcher(ir),
        ]),
    );
    return '$_header\n${formatLibrary(library)}';
  }

  /// A name that is not in the graph is a 404, not a crash.
  Spec _unknownRpc() => Class(
        (c) => c
          ..name = 'UnknownRpc'
          ..docs.add('/// Thrown for an RPC name this server does not serve.')
          ..implements.add(refer('Exception'))
          ..fields.add(
            Field((f) => f
              ..name = 'name'
              ..modifier = FieldModifier.final$
              ..type = refer('String')),
          )
          ..constructors.add(
            Constructor((ctor) => ctor
              ..constant = true
              ..requiredParameters.add(
                Parameter((p) => p
                  ..name = 'name'
                  ..toThis = true),
              )),
          )
          ..methods.add(
            Method((m) => m
              ..name = 'toString'
              ..returns = refer('String')
              ..annotations.add(refer('override'))
              ..lambda = true
              ..body = const Code("'No server function named \"\$name\".'")),
          ),
      );

  /// A missing argument is the caller's mistake, so the answer names it
  /// rather than reporting whatever null check happened to fail first.
  Spec _missingArgument() => Class(
        (c) => c
          ..name = 'MissingArgument'
          ..docs.add('/// Thrown when a call leaves out a required argument.')
          ..implements.add(refer('Exception'))
          ..fields.add(
            Field((f) => f
              ..name = 'name'
              ..modifier = FieldModifier.final$
              ..type = refer('String')),
          )
          ..constructors.add(
            Constructor((ctor) => ctor
              ..constant = true
              ..requiredParameters.add(
                Parameter((p) => p
                  ..name = 'name'
                  ..toThis = true),
              )),
          )
          ..methods.add(
            Method((m) => m
              ..name = 'toString'
              ..returns = refer('String')
              ..annotations.add(refer('override'))
              ..lambda = true
              ..body = const Code(
                "'Missing required argument \"\$name\".'",
              )),
          ),
      );

  Spec _argumentReader() => Method(
        (m) => m
          ..name = '_argument'
          ..returns = refer('Object?')
          ..docs.addAll([
            '',
            '/// Reads one argument, naming it if it is not there.',
          ])
          ..requiredParameters.addAll([
            Parameter((p) => p
              ..name = 'arguments'
              ..type = refer('Map<String, Object?>')),
            Parameter((p) => p
              ..name = 'name'
              ..type = refer('String')),
          ])
          ..body = const Code('''
final value = arguments[name];
if (value == null) throw MissingArgument(name);
return value;'''),
      );

  List<Spec> _functionOf(ServerFunctionIr ir) {
    final function = ir.function;
    return [
      Method(
        (m) => m
          ..name = function.name
          ..returns = refer(function.returns.dartName)
          ..docs.addAll([
            '',
            '/// `POST ${function.route}` — from ${function.id}.',
          ])
          ..requiredParameters.addAll([
            for (final parameter in function.parameters)
              Parameter(
                (p) => p
                  ..name = parameter.name
                  ..type = refer(parameter.type.dartName),
              ),
          ])
          ..lambda = true
          ..body = ir.body.standalone().code,
      ),
      // The decoder is generated beside the function so the two cannot drift.
      Method(
        (m) => m
          ..name = '_${function.name}FromJson'
          ..returns = refer('Object?')
          ..docs.addAll(['', '/// Decodes the arguments and calls it.'])
          ..requiredParameters.add(
            Parameter(
              (p) => p
                ..name = 'arguments'
                ..type = refer('Map<String, Object?>'),
            ),
          )
          ..lambda = true
          ..body = Code(
            _encode(
              function.returns,
              '${function.name}('
              '${function.parameters.map(_readArgument).join(', ')})',
            ),
          ),
      ),
      for (final helper in ir.helpers) helperMethod(helper),
    ];
  }

  /// Turns the answer into something `jsonEncode` accepts, by its declared
  /// type rather than by inspecting the value.
  static String _encode(LatticeType type, String source) => switch (type) {
        ModelType() => '($source).toJson()',
        ListType(element: ModelType()) =>
          '[for (final e in $source) e.toJson()]',
        NullableType(inner: ModelType()) => '($source)?.toJson()',
        NullableType(inner: ListType(element: ModelType())) =>
          '($source)?.map((e) => e.toJson()).toList()',
        _ => source,
      };

  String _readArgument(FieldDef parameter) {
    final access = "_argument(arguments, '${parameter.name}')";
    final type = parameter.type;

    String decode(LatticeType target, String source) => switch (target) {
          ModelType(:final name) =>
            '$name.fromJson($source! as Map<String, Object?>)',
          ListType(element: ModelType(:final name)) =>
            '[for (final e in $source! as List<Object?>) '
                '$name.fromJson(e as Map<String, Object?>)]',
          PrimitiveType(kind: PrimitiveKind.double$) =>
            '($source! as num).toDouble()',
          NullableType(:final inner) =>
            '$source == null ? null : ${decode(inner, source)}',
          _ => '$source as ${target.dartName}',
        };

    if (parameter.defaultValue != null || type is NullableType) {
      final optional = "arguments['${parameter.name}']";
      final fallback =
          parameter.defaultValue == null ? 'null' : _literal(parameter);
      return '$optional == null ? $fallback '
          ': ${decode(_nonNull(type), optional)}';
    }
    return decode(type, access);
  }

  static LatticeType _nonNull(LatticeType type) =>
      type is NullableType ? type.inner : type;

  static String _literal(FieldDef parameter) =>
      switch (parameter.defaultValue) {
        final String s => "'${s.replaceAll("'", r"\'")}'",
        final bool b => '$b',
        final num n => '$n',
        _ => 'null',
      };

  /// The one place that knows the route table, so adding a function to the
  /// graph is the only edit a new endpoint needs.
  Spec _dispatcher(ProjectIr ir) => Method(
        (m) => m
          ..name = 'dispatch'
          ..returns = refer('Object?')
          ..docs.addAll([
            '',
            '/// Routes one RPC name to its function.',
            '///',
            '/// Throws [UnknownRpc] for a name that is not in the graph, which',
            '/// the server turns into a 404 rather than a 500.',
          ])
          ..requiredParameters.addAll([
            Parameter((p) => p
              ..name = 'name'
              ..type = refer('String')),
            Parameter((p) => p
              ..name = 'arguments'
              ..type = refer('Map<String, Object?>')),
          ])
          ..body = Code('''
switch (name) {
${ir.serverFunctions.map((f) => "  case '${f.function.name}': return _${f.function.name}FromJson(arguments);").join('\n')}
  default:
    throw UnknownRpc(name);
}'''),
      );

  static bool _decodesJson(ProjectIr ir) =>
      ir.serverFunctions.any((f) => f.usesJson);

  Iterable<String> _extraImports(ProjectIr ir) => {
        for (final function in ir.serverFunctions) ...function.extraImports,
      };

  /// `bin/server.dart` — the whole HTTP surface, in one file a person can read.
  String server(ProjectIr ir) => '''
$_header
import 'dart:convert';
import 'dart:io';

import 'package:$_packageName/handlers.dart';

/// Every server function is reached the same way: `POST /rpc/<name>` with a
/// JSON object of arguments, answering `{"result": …}` or `{"error": …}`.
Future<void> main(List<String> arguments) async {
  final port = int.tryParse(
        arguments.isNotEmpty ? arguments.first : Platform.environment['PORT'] ?? '',
      ) ??
      8080;

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('lattice server listening on port \$port');
  stdout.writeln('routes:');
${ir.serverFunctions.map((f) => "  stdout.writeln('  POST ${f.function.route}');").join('\n')}

  await for (final request in server) {
    await _handle(request);
  }
}

Future<void> _handle(HttpRequest request) async {
  // A browser will preflight anything with a JSON body.
  request.response.headers
    ..set('Access-Control-Allow-Origin', '*')
    ..set('Access-Control-Allow-Methods', 'POST, OPTIONS')
    ..set('Access-Control-Allow-Headers', 'Content-Type');

  if (request.method == 'OPTIONS') {
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
    return;
  }

  if (request.method == 'GET' && request.uri.path == '/health') {
    await _respond(request, HttpStatus.ok, {'status': 'ok'});
    return;
  }

  if (request.method != 'POST' || !request.uri.path.startsWith('/rpc/')) {
    await _respond(request, HttpStatus.notFound, {
      'error': 'Use POST /rpc/<name>.',
    });
    return;
  }

  final name = request.uri.pathSegments.last;
  try {
    final body = await utf8.decoder.bind(request).join();
    final arguments = body.isEmpty
        ? const <String, Object?>{}
        : jsonDecode(body) as Map<String, Object?>;
    await _respond(request, HttpStatus.ok, {
      'result': dispatch(name, arguments),
    });
  } on UnknownRpc catch (error) {
    await _respond(request, HttpStatus.notFound, {'error': '\$error'});
  } on Object catch (error) {
    // The client shows this, so it names the route and says what went wrong
    // rather than answering an opaque 500.
    await _respond(request, HttpStatus.badRequest, {
      'error': '\$name: \$error',
    });
  }
}

Future<void> _respond(
  HttpRequest request,
  int status,
  Map<String, Object?> body,
) async {
  request.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  await request.response.close();
}
''';

  String pubspec(Project project) => '''
# Generated by Lattice. Edit freely after ejecting.
name: $_packageName
description: 'Server functions for ${project.config.appName}.'
publish_to: none
version: '${project.config.version}'

environment:
  sdk: ^3.6.0

dev_dependencies:
  lints: ^5.1.0
''';

  String analysisOptions() => '''
include: package:lints/recommended.yaml

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
''';

  String readme(Project project, ProjectIr ir) => '''
# ${project.config.appName} — server

Generated by Lattice from the project's `@server` subgraphs (§7.7).
Plain Dart: no framework, no second code generator.

```bash
dart pub get
dart run bin/server.dart 8080
```

| Route | Arguments | Answers |
|---|---|---|
${ir.serverFunctions.map((f) => '| `POST ${f.function.route}` | ${f.function.parameters.isEmpty ? '—' : f.function.parameters.map((p) => '`${p.name}: ${p.type.dartName}`').join(', ')} | `${f.function.returns.dartName}` |').join('\n')}

Every call is `POST /rpc/<name>` with a JSON object of arguments, answering
`{"result": …}` or `{"error": …}`. `GET /health` answers `{"status":"ok"}`.

Regenerate with `lattice build --server`; edits here are overwritten.
''';

  static const _packageName = 'lattice_server';

  static const _header = '''
// Generated by Lattice.
//
// Safe to edit once you have ejected: this is ordinary Dart with no runtime
// dependency on the editor. Node ids appear as comments so a change here can
// still be traced back to the graph.
''';
}
