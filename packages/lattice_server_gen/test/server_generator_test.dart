import 'package:lattice_codegen/lattice_codegen.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:lattice_server_gen/lattice_server_gen.dart';
import 'package:test/test.dart';

import 'support/quote_fixture.dart';

/// What the two halves of a server function look like (§7.7).
void main() {
  Map<String, String> serverFiles(Project project) {
    final result = const ServerGenerator().generate(project);
    expect(result.isSuccess, isTrue, reason: result.diagnostics.join('\n'));
    return {
      for (final entry in result.files.entries)
        entry.key: entry.value.replaceAll(RegExp(r'\s+'), ' '),
    };
  }

  test('a project with no server functions generates no server', () {
    final result = const ServerGenerator().generate(
      Project(
        id: 'p',
        config: const ProjectConfig(appName: 'P', packageName: 'p'),
        pages: [quoteProject().pages.first],
      ),
    );
    // No pages either — the point is that an empty server is not an error.
    expect(result.files, isEmpty);
  });

  group('the server', () {
    test('is a plain Dart program with no framework', () {
      final files = serverFiles(quoteProject());
      expect(files.keys, containsAll(['bin/server.dart', 'lib/handlers.dart']));
      expect(files['pubspec.yaml'], isNot(contains('dart_frog')));
      expect(files['pubspec.yaml'], isNot(contains('shelf')));
      // The whole HTTP surface is dart:io.
      expect(files['bin/server.dart'], contains("import 'dart:io';"));
    });

    test('compiles the graph into an ordinary function', () {
      expect(
        serverFiles(quoteProject())['lib/handlers.dart'],
        contains('Quote priceFor(String sku, int quantity) =>'),
      );
    });

    test('routes by name and 404s anything else', () {
      final handlers = serverFiles(quoteProject())['lib/handlers.dart']!;
      expect(handlers, contains("case 'priceFor': return _priceForFromJson"));
      expect(handlers, contains('throw UnknownRpc(name)'));
    });

    test('names a missing argument instead of failing a null check', () {
      final handlers = serverFiles(quoteProject())['lib/handlers.dart']!;
      expect(handlers, contains('throw MissingArgument(name)'));
      expect(handlers, contains("_argument(arguments, 'sku') as String"));
    });

    test('encodes the answer by its declared type', () {
      expect(
        serverFiles(quoteProject())['lib/handlers.dart'],
        contains('.toJson()'),
      );
    });

    test('shares the models file with the client, unchanged', () {
      final server = serverFiles(quoteProject())['lib/models.dart']!;
      // No Flutter on this side, so the models cannot depend on it.
      expect(server, isNot(contains('flutter')));
      expect(server, contains('class Quote'));
    });
  });

  group('the client half', () {
    Map<String, String> clientFiles(Project project) {
      final result = const LatticeGenerator().generate(project);
      expect(result.isSuccess, isTrue, reason: result.diagnostics.join('\n'));
      return {
        for (final entry in result.files.entries)
          entry.key: entry.value.replaceAll(RegExp(r'\s+'), ' '),
      };
    }

    test('is a typed stub per function', () {
      final rpc = clientFiles(quoteProject())['lib/rpc.dart']!;
      expect(
        rpc,
        contains('Future<Quote> priceFor(String sku, int quantity) async'),
      );
      expect(rpc, contains("_call('priceFor'"));
      expect(rpc, contains('Quote.fromJson(answer! as Map<String, Object?>)'));
    });

    test('reads its base URL from the environment', () {
      expect(
        clientFiles(quoteProject())['lib/rpc.dart'],
        contains("String.fromEnvironment( 'LATTICE_SERVER',"),
      );
    });

    test('the calling page just awaits the stub', () {
      expect(
        clientFiles(quoteProject())['lib/pages/home_page.dart'],
        contains('quote.value = await priceFor(sku.value, quantity.value);'),
      );
    });

    test('a project with no server has no rpc.dart', () {
      final withoutServer = quoteProject().copyWith(serverFunctions: const []);
      expect(
        const LatticeGenerator()
            .generate(withoutServer)
            .files
            .containsKey('lib/rpc.dart'),
        isFalse,
      );
    });
  });

  group('the boundary', () {
    test('rejects a parameter that cannot survive JSON', () {
      final broken = quoteProject().copyWith(
        serverFunctions: [
          quoteProject().serverFunctions.first.copyWith(
            parameters: [
              const FieldDef(
                name: 'style',
                type: PrimitiveType.textStyle,
              ),
            ],
          ),
        ],
      );
      expect(
        const Validator().validate(broken).errors.map((e) => e.code),
        contains('unserializable_boundary'),
      );
    });

    test('rejects client state inside a server function', () {
      final function = quoteProject().serverFunctions.first;
      final broken = quoteProject().copyWith(
        serverFunctions: [
          function.copyWith(
            graph: Graph(
              nodes: [
                ...function.graph.nodes,
                GraphNode(
                  id: 'n_state',
                  type: 'Signal',
                  config: const {'dartType': 'int', 'init': 0},
                ),
              ],
              edges: function.graph.edges,
            ),
          ),
        ],
      );
      expect(
        const Validator().validate(broken).errors.map((e) => e.code),
        contains('client_node_on_server'),
      );
    });

    test('requires exactly one Return', () {
      final function = quoteProject().serverFunctions.first;
      final broken = quoteProject().copyWith(
        serverFunctions: [
          function.copyWith(
            graph: Graph(
              nodes: [
                for (final n in function.graph.nodes)
                  if (n.type != 'Return') n,
              ],
              edges: function.graph.edges,
            ),
          ),
        ],
      );
      expect(
        const Validator().validate(broken).errors.map((e) => e.code),
        contains('missing_return'),
      );
    });
  });
}
