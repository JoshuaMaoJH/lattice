import 'package:flutter/foundation.dart';

import 'reactive.dart';

/// Debug-only registry of the signals in a running generated app.
///
/// The editor's Debug panel reads this to show current values and which
/// widgets subscribe to them — "看得见的数据流" (user story 10 / R21). In a
/// release build [register] is a no-op and the map stays empty.
class SignalInspector {
  SignalInspector._();

  static final Map<String, Signal<Object?>> _signals = {};

  static Map<String, Signal<Object?>> get signals => Map.unmodifiable(_signals);

  /// Registers [signal] under its graph node id and returns it unchanged, so
  /// generated code can wrap a declaration without changing its shape.
  static Signal<T> register<T>(String nodeId, Signal<T> signal) {
    if (kDebugMode) {
      _signals[nodeId] = signal as Signal<Object?>;
    }
    return signal;
  }

  static void unregister(String nodeId) {
    if (kDebugMode) _signals.remove(nodeId);
  }

  /// A snapshot of every signal's current value, keyed by node id.
  static Map<String, Object?> snapshot() => {
        for (final entry in _signals.entries) entry.key: entry.value.peek,
      };
}
