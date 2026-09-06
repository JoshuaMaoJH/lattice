import 'package:lattice_core/lattice_core.dart';

/// How the preview subprocess is doing.
enum PreviewStatus { stopped, starting, running, failed }

/// One directory the in-app browser can show.
final class DirectoryEntry {
  const DirectoryEntry(
      {required this.name, required this.path, required this.isProject});

  final String name;
  final String path;

  /// Whether this directory has a `project.json` — the browser marks these so
  /// the user can see where to stop descending.
  final bool isProject;
}

/// Everything the editor needs from the machine it is running on.
///
/// Behind an interface because the editor is also compiled for the web, where
/// there is no filesystem and no subprocess — and because a headless test
/// wants to drive builds and previews without either.
abstract interface class EditorHost {
  /// Shown in the UI when a capability is missing, so the explanation can name
  /// where the user actually is.
  String get description;

  bool get canOpenProjects;
  bool get canRunPreview;

  /// Which of [names] are set in this process's environment.
  ///
  /// Presence only. §7.9 keeps credentials out of project files; reading their
  /// values into the editor would put them somewhere just as wrong.
  Set<String> presentEnvironment(Iterable<String> names);

  /// Whether the path in the environment variable [name] points at a file that
  /// is actually there.
  bool environmentPathExists(String name);

  /// Where the project browser should start: the last place the user opened
  /// something, or their home directory.
  Future<String> browseStart();

  /// The directories directly inside [path], sorted by name. Files are not
  /// listed: a Lattice project is a directory, so a file is never a target.
  Future<List<DirectoryEntry>> browse(String path);

  /// The parent of [path], or null at the root.
  String? parentOf(String path);

  /// Project roots the user opened before, most recent first.
  Future<List<String>> recentProjects();

  /// Creates a new project in [root] and returns it.
  Future<Project> createProject(String root, {String? appName});

  /// Loads the project rooted at [root].
  Future<Project> open(String root);

  /// Writes the project back to [root].
  Future<void> save(Project project, String root);

  /// Generates the Flutter project and returns where it landed.
  Future<String> build(Project project, String root);

  /// Exports a standalone copy (R8, G5).
  Future<String> export(Project project, String root, String destination);

  /// Starts `flutter run` against the generated project.
  Future<void> startPreview(Project project, String root, {String? device});

  /// Regenerates and hot-reloads (§7.6).
  Future<void> reloadPreview(Project project, String root);

  Future<void> stopPreview();

  PreviewStatus get previewStatus;

  /// Lines from the preview process, newest last.
  List<String> get previewLog;

  /// Fires whenever [previewStatus] or [previewLog] changes.
  Stream<void> get previewChanges;
}

/// The host used where there is no filesystem: the web build, and tests.
///
/// It does not pretend. Every capability it lacks is reported as false so the
/// UI can say what is missing rather than failing when a button is pressed.
class MemoryHost implements EditorHost {
  MemoryHost({this.description = 'Running in a browser'});

  @override
  final String description;

  @override
  bool get canOpenProjects => false;

  @override
  bool get canRunPreview => false;

  @override
  PreviewStatus get previewStatus => PreviewStatus.stopped;

  @override
  List<String> get previewLog => const [];

  @override
  Stream<void> get previewChanges => const Stream.empty();

  Never _unavailable(String action) => throw UnsupportedError(
        '$action needs the desktop editor; this one is $description.',
      );

  @override
  Set<String> presentEnvironment(Iterable<String> names) => const {};

  @override
  bool environmentPathExists(String name) => false;

  @override
  Future<String> browseStart() async => _unavailable('Browsing');

  @override
  Future<List<DirectoryEntry>> browse(String path) async =>
      _unavailable('Browsing');

  @override
  String? parentOf(String path) => null;

  @override
  Future<List<String>> recentProjects() async => const [];

  @override
  Future<Project> createProject(String root, {String? appName}) async =>
      _unavailable('Creating a project');

  @override
  Future<Project> open(String root) async => _unavailable('Opening a project');

  @override
  Future<void> save(Project project, String root) async =>
      _unavailable('Saving');

  @override
  Future<String> build(Project project, String root) async =>
      _unavailable('Building');

  @override
  Future<String> export(
          Project project, String root, String destination) async =>
      _unavailable('Exporting');

  @override
  Future<void> startPreview(Project project, String root,
          {String? device}) async =>
      _unavailable('The preview');

  @override
  Future<void> reloadPreview(Project project, String root) async {}

  @override
  Future<void> stopPreview() async {}
}
