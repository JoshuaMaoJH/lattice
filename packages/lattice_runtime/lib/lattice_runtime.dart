/// The thin runtime that Lattice-generated projects depend on (§6).
///
/// This is the zero-dependency backend: `Signal` / `Computed` / `Watch` built
/// on `ChangeNotifier`, with automatic dependency tracking. Projects
/// configured with `runtime: signals` import `signals_flutter` instead and do
/// not need this package at all — the two present the same surface, which is
/// what keeps §15's open question open.
library;

export 'src/inspector.dart';
export 'src/reactive.dart'
    show
        Computed,
        ReadonlySignal,
        Signal,
        batch,
        computed,
        effect,
        signal,
        untracked;
export 'src/watch.dart' show SignalBuilder, Watch, WatchValue;
