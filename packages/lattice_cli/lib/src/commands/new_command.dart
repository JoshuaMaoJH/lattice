import 'dart:io';

import 'package:lattice_codegen/lattice_codegen.dart';
import 'package:lattice_core/io.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:path/path.dart' as p;

import 'base.dart';

/// `lattice new` — writes a minimal but complete project.
///
/// The starter is the counter from §8: small enough to read in one screen, and
/// it exercises every part of the pipeline (a signal, a computed binding, an
/// event chain, a reactive boundary).
class NewCommand extends LatticeCommand {
  NewCommand(super.console) {
    argParser
      ..addOption('name', help: 'Application display name.', valueHelp: 'name')
      ..addOption(
        'package',
        help: 'Dart package name for the generated project.',
        valueHelp: 'snake_case',
      )
      ..addOption(
        'runtime',
        help: 'Reactive backend for generated code.',
        allowed: ['signals', 'value_notifier'],
        defaultsTo: 'signals',
      );
  }

  @override
  String get name => 'new';

  @override
  String get description => 'Create a new Lattice project.';

  @override
  String get invocation => 'lattice new <directory> [--name "My App"]';

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? const [];
    if (rest.isEmpty) {
      console.error('Give a directory: lattice new my_app');
      return 1;
    }
    final root = p.absolute(rest.first);
    final directory = Directory(root);
    if (directory.existsSync() && directory.listSync().isNotEmpty) {
      console.error('"$root" already exists and is not empty.');
      return 1;
    }

    final folder = p.basename(root);
    final appName = argResults?['name'] as String? ?? _titleCase(folder);
    final packageName =
        argResults?['package'] as String? ?? _packageName(folder);

    final project = Project(
      id: _packageName(folder),
      config: ProjectConfig(
        appName: appName,
        packageName: packageName,
        bundleId: 'com.example.$packageName',
        description: 'A Lattice project.',
        runtime: RuntimeBackend.fromId(argResults?['runtime'] as String?),
      ),
      pages: [_counterPage(appName)],
    );

    await ProjectIo.save(project, root);
    await File(p.join(root, 'custom', 'README.md'))
        .create(recursive: true)
        .then(
          (file) => file.writeAsString(const SupportFiles().customReadme()),
        );
    console.success('Created ${p.relative(root)}');
    console.info('');
    console.info('  lattice run ${p.relative(root)}');
    return 0;
  }

  /// The §8 counter, expressed in the project model rather than in JSON, so
  /// this doubles as a worked example of the data structures.
  Page _counterPage(String appName) => Page(
        id: 'page_home',
        name: 'Home',
        route: '/',
        isHome: true,
        hierarchy: WidgetNode(
          id: 'w_root',
          type: 'Scaffold',
          props: {
            'appBar': WidgetProp(
              WidgetNode(
                id: 'w_appbar',
                type: 'AppBar',
                props: {
                  'title': WidgetProp(
                    WidgetNode(
                      id: 'w_title',
                      type: 'Text',
                      props: {'data': LiteralProp(appName)},
                    ),
                  ),
                },
              ),
            ),
          },
          children: [
            WidgetNode(
              id: 'w_center',
              type: 'Center',
              children: [
                WidgetNode(
                  id: 'w_col',
                  type: 'Column',
                  props: {
                    'mainAxisAlignment': const LiteralProp('center'),
                  },
                  children: [
                    WidgetNode(
                      id: 'w_txt',
                      type: 'Text',
                      props: {
                        'data': const BindProp(PinRef('n_fmt', 'out')),
                      },
                    ),
                    WidgetNode(
                      id: 'w_gap',
                      type: 'SizedBox',
                      props: {'height': const LiteralProp(12)},
                    ),
                    WidgetNode(
                      id: 'w_btn',
                      type: 'ElevatedButton',
                      props: {
                        'onPressed': const EventProp('ev_btn'),
                      },
                      children: [
                        WidgetNode(
                          id: 'w_btn_label',
                          type: 'Text',
                          props: {'data': const LiteralProp('+1')},
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        graph: Graph(
          nodes: [
            GraphNode(
              id: 'n_count',
              type: 'Signal',
              config: {'dartType': 'int', 'init': 0, 'name': 'count'},
            ),
            GraphNode(
              id: 'n_fmt',
              type: 'Format',
              config: {'template': 'Count: {0}'},
            ),
            GraphNode(
              id: 'ev_btn',
              type: 'Event',
              config: {'widget': 'w_btn', 'event': 'onPressed'},
            ),
            GraphNode(
              id: 'a_inc',
              type: 'UpdateSignal',
              config: {'signal': 'n_count', 'fn': '(x) => x + 1'},
            ),
          ],
          edges: const [
            Edge(PinRef('n_count', 'value'), PinRef('n_fmt', 'args', index: 0)),
            Edge(PinRef('ev_btn', 'fire'), PinRef('a_inc', 'exec')),
          ],
        ),
        layout: const {
          'n_count': CanvasPos(120, 80),
          'n_fmt': CanvasPos(340, 80),
          'ev_btn': CanvasPos(120, 260),
          'a_inc': CanvasPos(340, 260),
        },
      );

  static String _packageName(String raw) {
    final cleaned = raw
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '_')
        .replaceAll(RegExp('^_+|_+\$'), '');
    final safe = cleaned.isEmpty ? 'lattice_app' : cleaned;
    return RegExp('^[0-9]').hasMatch(safe) ? 'app_$safe' : safe;
  }

  static String _titleCase(String raw) => raw
      .split(RegExp('[^A-Za-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
