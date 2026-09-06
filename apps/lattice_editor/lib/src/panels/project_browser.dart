import 'package:flutter/material.dart';

import '../host/editor_host.dart';
import '../theme.dart';

/// Picking a project without leaving the editor.
///
/// Self-drawn rather than a platform file dialog, for the same reason the
/// canvas is self-drawn: a directory chooser that cannot tell a Lattice
/// project from any other folder makes the user do the recognising. This one
/// marks projects, so "where do I stop descending" is answered on screen.
class ProjectBrowser extends StatefulWidget {
  const ProjectBrowser({super.key, required this.host, required this.mode});

  final EditorHost host;
  final ProjectBrowserMode mode;

  /// Returns the chosen directory, or null if the user backed out.
  static Future<ProjectChoice?> show(
    BuildContext context,
    EditorHost host, {
    ProjectBrowserMode mode = ProjectBrowserMode.open,
  }) =>
      showDialog<ProjectChoice>(
        context: context,
        builder: (_) => ProjectBrowser(host: host, mode: mode),
      );

  @override
  State<ProjectBrowser> createState() => _ProjectBrowserState();
}

enum ProjectBrowserMode { open, create }

/// What the browser came back with.
final class ProjectChoice {
  const ProjectChoice({required this.path, required this.isNew, this.appName});

  final String path;
  final bool isNew;
  final String? appName;
}

class _ProjectBrowserState extends State<ProjectBrowser> {
  String? _current;
  List<DirectoryEntry> _entries = const [];
  List<String> _recents = const [];
  bool _loading = true;
  String? _failure;

  final _nameController = TextEditingController();

  bool get _isCreate => widget.mode == ProjectBrowserMode.create;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final recents = await widget.host.recentProjects();
    final start = await widget.host.browseStart();
    if (!mounted) return;
    setState(() => _recents = recents);
    await _go(start);
  }

  Future<void> _go(String path) async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final entries = await widget.host.browse(path);
      if (!mounted) return;
      setState(() {
        _current = path;
        _entries = entries;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      // A directory the user cannot read is a normal thing to walk into, so
      // it says so in place rather than closing the dialog.
      setState(() {
        _failure = '$path could not be read:\n$error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final parent = _current == null ? null : widget.host.parentOf(_current!);
    return Dialog(
      backgroundColor: LatticeTheme.panel,
      child: SizedBox(
        width: 620,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(parent),
            const Divider(height: 1, color: LatticeTheme.hairline),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _failure != null
                      ? _message(_failure!)
                      : _list(),
            ),
            const Divider(height: 1, color: LatticeTheme.hairline),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header(String? parent) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        child: Row(
          children: [
            Text(
              _isCreate ? 'New project in' : 'Open project',
              style: LatticeTheme.title,
            ),
            const SizedBox(width: 16),
            IconButton(
              tooltip: 'Up one level',
              iconSize: 18,
              color: LatticeTheme.textSecondary,
              onPressed: parent == null ? null : () => _go(parent),
              icon: const Icon(Icons.arrow_upward),
            ),
            Expanded(
              child: Text(
                _current ?? '',
                style: LatticeTheme.monoSmall,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      );

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, style: LatticeTheme.secondary),
        ),
      );

  Widget _list() {
    if (_entries.isEmpty && _recents.isEmpty) {
      return _message('Nothing here.');
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        if (_recents.isNotEmpty && !_isCreate) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Recent', style: LatticeTheme.eyebrow),
          ),
          for (final root in _recents)
            _row(
              icon: Icons.history,
              label: root,
              mono: true,
              onTap: () => Navigator.of(context)
                  .pop(ProjectChoice(path: root, isNew: false)),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text('Browse', style: LatticeTheme.eyebrow),
          ),
        ],
        if (_entries.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('No sub-directories.', style: LatticeTheme.secondary),
          ),
        for (final entry in _entries)
          _row(
            icon: entry.isProject
                ? Icons.widgets_outlined
                : Icons.folder_outlined,
            label: entry.name,
            highlight: entry.isProject,
            trailing: entry.isProject && !_isCreate
                ? TextButton(
                    onPressed: () => Navigator.of(context)
                        .pop(ProjectChoice(path: entry.path, isNew: false)),
                    child: const Text('Open'),
                  )
                : null,
            onTap: () => _go(entry.path),
          ),
      ],
    );
  }

  Widget _row({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool highlight = false,
    bool mono = false,
    Widget? trailing,
  }) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: highlight
                    ? LatticeTheme.selectionEdge
                    : LatticeTheme.textFaint,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: mono ? LatticeTheme.monoSmall : LatticeTheme.body,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      );

  Widget _footer() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            if (_isCreate)
              Expanded(
                child: TextField(
                  controller: _nameController,
                  style: LatticeTheme.body,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Folder name',
                    hintText: 'my_app',
                  ),
                  onSubmitted: (_) => _create(),
                ),
              )
            else
              const Expanded(
                child: Text(
                  'A folder with a project.json is a Lattice project.',
                  style: LatticeTheme.secondary,
                ),
              ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            if (_isCreate)
              FilledButton(
                onPressed: _create,
                child: const Text('Create'),
              ),
          ],
        ),
      );

  void _create() {
    final folder = _nameController.text.trim();
    final root = _current;
    if (folder.isEmpty || root == null) return;
    Navigator.of(context).pop(
      ProjectChoice(path: '$root/$folder', isNew: true, appName: null),
    );
  }
}
