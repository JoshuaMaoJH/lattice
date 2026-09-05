import 'package:code_builder/code_builder.dart';
import 'package:lattice_core/lattice_core.dart';

import '../emit/emitted.dart';

/// A `Signal` node, lowered to a field declaration.
final class SignalIr {
  const SignalIr({
    required this.nodeId,
    required this.name,
    required this.type,
    required this.init,
  });

  final String nodeId;

  /// The Dart field name, e.g. `count`.
  final String name;

  final LatticeType type;
  final Emitted init;
}

/// A computation referenced from more than one place, promoted out of the
/// widget tree into a `computed()` field (§7.5 step 3).
final class HoistedIr {
  const HoistedIr({
    required this.pin,
    required this.name,
    required this.type,
    required this.body,
    required this.signalDeps,
  });

  final PinRef pin;
  final String name;
  final LatticeType type;
  final Emitted body;
  final Set<String> signalDeps;

  bool get isReactive => signalDeps.isNotEmpty;
}

/// A private function holding a user-authored expression or body — the
/// compiled form of `Computed` and `Dart Code` nodes (§7.8).
final class HelperIr {
  const HelperIr({
    required this.nodeId,
    required this.name,
    required this.returnType,
    required this.parameters,
    required this.body,
    this.isExpressionBody = true,
  });

  final String nodeId;
  final String name;
  final LatticeType returnType;
  final List<({String name, LatticeType type})> parameters;

  /// Raw Dart written by the user; embedded verbatim (§7.8).
  final String body;

  /// `=> body;` versus `{ body }`.
  final bool isExpressionBody;
}

/// One widget callback, lowered to a method on the page's `State`.
final class HandlerIr {
  const HandlerIr({
    required this.eventNodeId,
    required this.name,
    required this.payloadType,
    required this.payloadName,
    required this.statements,
    required this.trace,
  });

  final String eventNodeId;
  final String name;
  final LatticeType? payloadType;
  final String payloadName;
  final List<Code> statements;

  /// The chain of action node ids, for the `// ev_btn -> a_inc` comment that
  /// anchors generated code back to the graph (§8).
  final List<String> trace;
}

/// Everything needed to emit one page file.
final class PageIr {
  const PageIr({
    required this.page,
    required this.className,
    required this.fileName,
    required this.signals,
    required this.hoisted,
    required this.helpers,
    required this.handlers,
    required this.body,
    required this.usesModels,
  });

  final Page page;
  final String className;
  final String fileName;
  final List<SignalIr> signals;
  final List<HoistedIr> hoisted;
  final List<HelperIr> helpers;
  final List<HandlerIr> handlers;

  /// The root widget expression for `build()`.
  final Emitted body;

  /// Whether the page references any user model, and therefore needs the
  /// models import.
  final bool usesModels;

  /// A page with no state and no callbacks compiles to a `StatelessWidget`;
  /// there is no reason to pay for a `State` object that holds nothing.
  bool get isStateful =>
      signals.isNotEmpty || hoisted.isNotEmpty || handlers.isNotEmpty;
}

/// The lowered form of a whole project.
final class ProjectIr {
  const ProjectIr({
    required this.project,
    required this.pages,
  });

  final Project project;
  final List<PageIr> pages;
}
