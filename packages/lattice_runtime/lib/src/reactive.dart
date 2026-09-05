import 'package:flutter/foundation.dart';

/// Anything the graph can read reactively.
abstract interface class ReadonlySignal<T> implements Listenable {
  T get value;

  /// Sugar so a generated expression can read `count()` as well as
  /// `count.value`.
  T call();
}

/// Collects the signals read during one computation.
///
/// This is what makes `computed` and [Watch] dependency-free at the call site:
/// nothing declares what it depends on, the read itself registers it.
class _Tracker {
  _Tracker();

  static _Tracker? current;

  final Set<Listenable> reads = {};

  static R run<R>(_Tracker tracker, R Function() body) {
    final previous = current;
    current = tracker;
    try {
      return body();
    } finally {
      current = previous;
    }
  }
}

/// Runs [body] without recording any of its reads as dependencies.
T untracked<T>(T Function() body) {
  final previous = _Tracker.current;
  _Tracker.current = null;
  try {
    return body();
  } finally {
    _Tracker.current = previous;
  }
}

int _batchDepth = 0;
final Set<_Notifier> _pending = {};

/// Applies several writes and notifies listeners once, at the end.
///
/// A generated event handler that writes three signals should cause one
/// rebuild, not three.
void batch(void Function() body) {
  _batchDepth++;
  try {
    body();
  } finally {
    _batchDepth--;
    if (_batchDepth == 0) {
      final flushing = List<_Notifier>.of(_pending);
      _pending.clear();
      for (final n in flushing) {
        n.flush();
      }
    }
  }
}

/// Shared notification plumbing with batching support.
abstract class _Notifier extends ChangeNotifier {
  void schedule() {
    if (_batchDepth > 0) {
      _pending.add(this);
    } else {
      notifyListeners();
    }
  }

  void flush() => notifyListeners();

  /// Whether anything is currently subscribed.
  ///
  /// Exposed because the data-flow inspector wants to show which signals have
  /// live readers (R21), and because a test needs to see that a disposed
  /// `SignalBuilder` really did unsubscribe.
  bool get hasSubscribers => hasListeners;
}

/// The one mutable state primitive (§5). Writing it re-runs everything that
/// read it.
class Signal<T> extends _Notifier implements ReadonlySignal<T> {
  Signal(this._value, {this.debugLabel});

  T _value;

  /// The originating graph node id, kept for the data-flow inspector (R21).
  final String? debugLabel;

  @override
  T get value {
    _Tracker.current?.reads.add(this);
    return _value;
  }

  set value(T next) {
    if (identical(next, _value) || next == _value) return;
    _value = next;
    schedule();
  }

  @override
  T call() => value;

  /// Reads the current value without registering a dependency — the right
  /// thing inside an event handler.
  T get peek => _value;

  /// `signal.update((x) => x + 1)`, the shape `UpdateSignal` compiles to.
  void update(T Function(T current) fn) => value = fn(_value);

  @override
  String toString() => 'Signal<$T>($_value)';
}

/// A pure derived value. Recomputes lazily, and only when a dependency
/// actually changed.
class Computed<T> extends _Notifier implements ReadonlySignal<T> {
  Computed(this._compute, {this.debugLabel});

  final T Function() _compute;
  final String? debugLabel;

  late T _cached;
  bool _dirty = true;
  final Set<Listenable> _dependencies = {};

  @override
  T get value {
    if (_dirty) _recompute();
    _Tracker.current?.reads.add(this);
    return _cached;
  }

  @override
  T call() => value;

  void _recompute() {
    final tracker = _Tracker();
    _cached = _Tracker.run(tracker, _compute);
    _dirty = false;

    for (final old in _dependencies.difference(tracker.reads)) {
      old.removeListener(_onDependencyChanged);
    }
    for (final added in tracker.reads.difference(_dependencies)) {
      added.addListener(_onDependencyChanged);
    }
    _dependencies
      ..clear()
      ..addAll(tracker.reads);
  }

  void _onDependencyChanged() {
    if (_dirty) return;
    _dirty = true;
    schedule();
  }

  @override
  void dispose() {
    for (final dep in _dependencies) {
      dep.removeListener(_onDependencyChanged);
    }
    _dependencies.clear();
    super.dispose();
  }

  @override
  String toString() => 'Computed<$T>(${_dirty ? "dirty" : _cached})';
}

/// A side effect that re-runs whenever what it read changes.
///
/// Returns a disposer; generated `State` classes call it from `dispose()`.
VoidCallback effect(void Function() body) {
  final dependencies = <Listenable>{};
  late void Function() run;
  var disposed = false;

  void onChanged() {
    if (!disposed) run();
  }

  run = () {
    final tracker = _Tracker();
    _Tracker.run(tracker, body);
    for (final old in dependencies.difference(tracker.reads)) {
      old.removeListener(onChanged);
    }
    for (final added in tracker.reads.difference(dependencies)) {
      added.addListener(onChanged);
    }
    dependencies
      ..clear()
      ..addAll(tracker.reads);
  };

  run();
  return () {
    disposed = true;
    for (final dep in dependencies) {
      dep.removeListener(onChanged);
    }
    dependencies.clear();
  };
}

/// Creates a [Signal]. Named to match the generated source in §8.
Signal<T> signal<T>(T initial, {String? debugLabel}) =>
    Signal<T>(initial, debugLabel: debugLabel);

/// Creates a [Computed].
Computed<T> computed<T>(T Function() compute, {String? debugLabel}) =>
    Computed<T>(compute, debugLabel: debugLabel);

/// Internal hook used by [Watch]. Not exported from `lattice_runtime.dart`;
/// generated code never calls it.
R trackReads<R>(Set<Listenable> into, R Function() body) {
  final tracker = _Tracker();
  final result = _Tracker.run(tracker, body);
  into.addAll(tracker.reads);
  return result;
}
