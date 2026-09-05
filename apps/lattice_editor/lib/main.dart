import 'package:flutter/material.dart';

import 'src/editor_shell.dart';
import 'src/host/editor_host.dart';
import 'src/host/host.dart';
import 'src/sample_project.dart';
import 'src/state/editor_controller.dart';
import 'src/theme.dart';

/// The Lattice editor (§6, M1).
///
///     lattice_editor [project-directory]
///
/// With no argument it opens the §8 counter in memory, which is also what the
/// web build always does — there is no filesystem there to open anything from.
void main(List<String> args) {
  runApp(LatticeEditorApp(projectRoot: args.isEmpty ? null : args.first));
}

class LatticeEditorApp extends StatefulWidget {
  const LatticeEditorApp({super.key, this.projectRoot});

  final String? projectRoot;

  @override
  State<LatticeEditorApp> createState() => _LatticeEditorAppState();
}

class _LatticeEditorAppState extends State<LatticeEditorApp> {
  final EditorHost _host = createHost();
  late final EditorController _controller =
      EditorController(project: sampleProject());

  String? _failure;

  @override
  void initState() {
    super.initState();
    final root = widget.projectRoot;
    if (root != null && _host.canOpenProjects) {
      _open(root);
    } else {
      _openDemo();
    }
  }

  Future<void> _openDemo() async {
    final project = await demoProject();
    if (mounted) _controller.load(project);
  }

  Future<void> _open(String root) async {
    try {
      final project = await _host.open(root);
      _controller.load(project, projectRoot: root);
    } on Object catch (error) {
      // Opening a project is the first thing that happens, so a failure here
      // has to say what it could not read rather than showing an empty editor.
      setState(() => _failure = 'Could not open $root:\n$error');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Lattice',
        debugShowCheckedModeBanner: false,
        theme: LatticeTheme.materialTheme(),
        home: _failure != null
            ? _OpenFailed(message: _failure!)
            : EditorShell(controller: _controller, host: _host),
      );
}

class _OpenFailed extends StatelessWidget {
  const _OpenFailed({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: LatticeTheme.canvas,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Text(message, style: LatticeTheme.code),
          ),
        ),
      );
}
