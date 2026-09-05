import 'editor_host.dart';
import 'memory_host_factory.dart' if (dart.library.io) 'io_host.dart'
    as platform;

/// The host for wherever this build is running.
///
/// On desktop that is real files and a real preview process; in a browser it
/// is a host that owns up to having neither.
EditorHost createHost() => platform.createHost();
