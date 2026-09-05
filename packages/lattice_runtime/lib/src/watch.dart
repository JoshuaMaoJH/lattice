import 'package:flutter/widgets.dart';

import 'reactive.dart';

/// Rebuilds [builder] whenever any signal it read has changed.
///
/// Codegen wraps *only* the widgets whose parameters depend on a signal
/// (§7.5 step 2), which is what keeps the rest of the tree `const`.
class Watch extends StatefulWidget {
  const Watch(this.builder, {super.key, this.debugLabel});

  final Widget Function(BuildContext context) builder;

  /// The widget id this boundary was generated for, for the data-flow
  /// inspector (R21).
  final String? debugLabel;

  @override
  State<Watch> createState() => _WatchState();
}

class _WatchState extends State<Watch> {
  final Set<Listenable> _dependencies = {};

  // Same contract as ValueListenableBuilder: mark dirty and let the framework
  // coalesce. `batch()` covers the several-writes-in-one-handler case.
  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final reads = <Listenable>{};
    final child = trackReads(reads, () => widget.builder(context));

    for (final gone in _dependencies.difference(reads)) {
      gone.removeListener(_onChanged);
    }
    for (final added in reads.difference(_dependencies)) {
      added.addListener(_onChanged);
    }
    _dependencies
      ..clear()
      ..addAll(reads);

    return child;
  }

  @override
  void dispose() {
    for (final dep in _dependencies) {
      dep.removeListener(_onChanged);
    }
    _dependencies.clear();
    super.dispose();
  }
}

/// A [Watch] over a single value, for the common one-signal case.
class WatchValue<T> extends StatelessWidget {
  const WatchValue(this.source, this.builder, {super.key});

  final ReadonlySignal<T> source;
  final Widget Function(BuildContext context, T value) builder;

  @override
  Widget build(BuildContext context) =>
      Watch((context) => builder(context, source.value));
}

/// The reactive boundary generated code emits.
///
/// Named and shaped to match `signals_flutter`'s `SignalBuilder`, so one
/// emitted form works against either runtime backend and switching between
/// them touches only an import line (§15).
class SignalBuilder extends StatelessWidget {
  const SignalBuilder(
      {super.key, required this.builder, this.dependencies = const []});

  final Widget Function(BuildContext context) builder;

  /// Signals to watch even if the builder does not read them this pass.
  final List<ReadonlySignal<Object?>> dependencies;

  @override
  Widget build(BuildContext context) => Watch((context) {
        for (final dependency in dependencies) {
          dependency.value;
        }
        return builder(context);
      });
}
