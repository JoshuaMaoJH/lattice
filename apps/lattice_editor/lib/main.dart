import 'package:flutter/material.dart';

import 'src/editor_shell.dart';
import 'src/host/editor_host.dart';
import 'src/host/host.dart';
import 'src/sample_project.dart';
import 'src/state/editor_controller.dart';
import 'src/panels/project_browser.dart';
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
    } else if (!_host.canOpenProjects) {
      // The web build has no filesystem to open anything from, so the demo is
      // the only thing there is.
      _openDemo();
    } else {
      // Launched from a desktop entry with no argument. Silently opening the
      // demo used to leave people editing a sample and wondering where their
      // project went, so ask first.
      setState(() => _needsProject = true);
    }
  }

  /// True before the user has said which project they want.
  bool _needsProject = false;

  Future<void> _adopt(ProjectChoice choice) async {
    try {
      final project = choice.isNew
          ? await _host.createProject(choice.path, appName: choice.appName)
          : await _host.open(choice.path);
      if (!mounted) return;
      _controller.load(project, projectRoot: choice.path);
      setState(() => _needsProject = false);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _failure = 'Could not open ${choice.path}:\n$error');
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
            : _needsProject
                ? _StartScreen(
                    host: _host,
                    onChoice: _adopt,
                    onDemo: () {
                      setState(() => _needsProject = false);
                      _openDemo();
                    },
                  )
                : EditorShell(controller: _controller, host: _host),
      );
}

/// What the editor shows when nobody has said which project to open.
///
/// Three ways in and nothing else on screen: the previous behaviour was to
/// open the bundled counter, which looks identical to having lost your work.
class _StartScreen extends StatelessWidget {
  const _StartScreen({
    required this.host,
    required this.onChoice,
    required this.onDemo,
  });

  final EditorHost host;
  final Future<void> Function(ProjectChoice) onChoice;
  final VoidCallback onDemo;

  Future<void> _pick(BuildContext context, ProjectBrowserMode mode) async {
    final choice = await ProjectBrowser.show(context, host, mode: mode);
    if (choice != null) await onChoice(choice);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: LatticeTheme.canvas,
        body: Center(
          child: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Lattice', style: LatticeTheme.title),
                const SizedBox(height: 6),
                const Text(
                  'Open a project, or start one.',
                  style: LatticeTheme.secondary,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => _pick(context, ProjectBrowserMode.open),
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('Open project'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _pick(context, ProjectBrowserMode.create),
                  icon: const Icon(Icons.note_add_outlined, size: 18),
                  label: const Text('New project'),
                ),
                const SizedBox(height: 22),
                TextButton(
                  onPressed: onDemo,
                  child: const Text('Look at the bundled counter instead'),
                ),
              ],
            ),
          ),
        ),
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
