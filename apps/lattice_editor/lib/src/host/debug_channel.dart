import 'dart:convert';

/// What the running preview has told us about one signal.
final class SignalObservation {
  const SignalObservation({
    required this.nodeId,
    required this.value,
    required this.changes,
    required this.sequence,
  });

  final String nodeId;

  /// The value as it was reported. Already decoded; shown, never round-tripped
  /// back into the project.
  final Object? value;

  /// How many times this signal has been written since the preview started.
  final int changes;

  /// Position in the global order of observations, so "what changed last" is
  /// answerable without timestamps.
  final int sequence;
}

/// Reads the data-flow channel out of the preview process's output (R21).
///
/// The generated app prints one marked line per state change and per handler
/// entry. Parsing stdout rather than opening a socket means there is no port
/// to choose, nothing to clean up when the app dies, and it works identically
/// for a desktop preview and a web one.
///
/// Everything here is display state. A malformed line is dropped rather than
/// raised: the preview's output is not a protocol we control, and a debug
/// panel must never be the reason the editor stops.
final class DebugChannel {
  static const marker = '__lattice__';

  final Map<String, SignalObservation> _signals = {};
  final List<String> _events = [];
  int _sequence = 0;

  Map<String, SignalObservation> get signals => Map.unmodifiable(_signals);

  /// Event node ids in the order their handlers ran, newest last.
  List<String> get events => List.unmodifiable(_events);

  bool get isEmpty => _signals.isEmpty && _events.isEmpty;

  /// The most recently written signals, newest first, at most [count].
  List<SignalObservation> recent({int count = 3}) {
    final ordered = _signals.values.toList()
      ..sort((a, b) => b.sequence.compareTo(a.sequence));
    return ordered.take(count).toList();
  }

  /// Whether [nodeId] is among the most recent writes — what the canvas
  /// highlights so a change is visible where the graph is, not only in a list.
  bool isRecent(String nodeId, {int count = 3}) =>
      recent(count: count).any((o) => o.nodeId == nodeId);

  /// Feeds one line of preview output. Returns true if it was ours, so the
  /// caller can keep it out of the human-readable log.
  bool consume(String line) {
    final start = line.indexOf(marker);
    if (start < 0) return false;
    final payload = line.substring(start + marker.length).trim();
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      // A line that carries the marker but not valid JSON is still ours —
      // swallowing it keeps half a message out of the log.
      return true;
    }
    if (decoded is! Map<String, Object?>) return true;

    final event = decoded['event'];
    if (event is String) {
      _events.add(event);
      if (_events.length > 50) _events.removeAt(0);
      return true;
    }

    final node = decoded['node'];
    if (node is! String) return true;
    _sequence++;
    _signals[node] = SignalObservation(
      nodeId: node,
      value: decoded['value'],
      changes: (_signals[node]?.changes ?? 0) + 1,
      sequence: _sequence,
    );
    return true;
  }

  /// Forgets everything. Called when the preview restarts, because values from
  /// a dead process are worse than no values.
  void clear() {
    _signals.clear();
    _events.clear();
    _sequence = 0;
  }
}
