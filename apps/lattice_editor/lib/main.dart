import 'package:flutter/material.dart';

import 'src/editor_shell.dart';
import 'src/host/host.dart';
import 'src/sample_project.dart';
import 'src/state/editor_controller.dart';
import 'src/theme.dart';

void main() {
  runApp(const LatticeEditorApp());
}

/// The Lattice editor (§6, M1).
class LatticeEditorApp extends StatefulWidget {
  const LatticeEditorApp({super.key});

  @override
  State<LatticeEditorApp> createState() => _LatticeEditorAppState();
}

class _LatticeEditorAppState extends State<LatticeEditorApp> {
  final _host = createHost();
  late final EditorController _controller =
      EditorController(project: sampleProject());

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
        home: EditorShell(controller: _controller, host: _host),
      );
}
