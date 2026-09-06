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

/// A Flutter controller the page owns: allocated in `initState`, kept in step
/// with a signal, disposed in `dispose` (see [ControllerBinding]).
final class ControllerIr {
  const ControllerIr({
    required this.widgetId,
    required this.name,
    required this.type,
    required this.property,
    required this.initial,
    required this.isReactive,
  });

  final String widgetId;

  /// The State field name, e.g. `_inputController`.
  final String name;

  /// The controller class, e.g. `TextEditingController`.
  final String type;

  /// The property holding the value, e.g. `text`.
  final String property;

  /// The bound expression: the controller's seed value, and — when reactive —
  /// what the sync effect watches.
  final Emitted initial;

  /// Whether the bound expression reads a signal and therefore needs an
  /// effect keeping the controller in step.
  final bool isReactive;

  /// The field holding the effect's disposer.
  String get disposerName => '${name}Sync';
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
    this.scopeParameters = const [],
    this.isAsync = false,
  });

  final String eventNodeId;
  final String name;
  final LatticeType? payloadType;
  final String payloadName;

  /// Loop variables handed in from an enclosing `ForEach` template. Empty for
  /// a handler on an ordinary widget (ADR-009).
  final List<({String name, LatticeType type})> scopeParameters;

  final List<Code> statements;

  /// True when the chain contains an awaited action. Flutter accepts a
  /// `Future<void> Function()` wherever a `VoidCallback` is expected, so the
  /// call site does not change.
  final bool isAsync;

  /// The chain of action node ids, for the `// ev_btn -> a_inc` comment that
  /// anchors generated code back to the graph (§8).
  final List<String> trace;
}

/// Everything needed to emit one page file.
final class PageIr {
  const PageIr({
    required this.unit,
    required this.className,
    required this.fileName,
    required this.signals,
    required this.hoisted,
    required this.helpers,
    required this.handlers,
    required this.controllers,
    required this.body,
    required this.usesModels,
    this.extraImports = const [],
    this.usesHttp = false,
    this.usesJson = false,
    this.usesRpc = false,
    this.usesDebug = false,
    this.usesCollections = false,
    this.usedPrefabs = const [],
  });

  /// The page or prefab this file was compiled from.
  final WidgetUnit unit;

  final String className;

  /// Values the unit is constructed with (R12, R9).
  List<FieldDef> get parameters => unit.parameters;
  final String fileName;
  final List<SignalIr> signals;
  final List<HoistedIr> hoisted;
  final List<HelperIr> helpers;
  final List<HandlerIr> handlers;
  final List<ControllerIr> controllers;

  /// The root widget expression for `build()`.
  final Emitted body;

  /// Whether the page references any user model, and therefore needs the
  /// models import.
  final bool usesModels;

  /// Imports requested by `Dart Code` and `Computed` nodes, relative to the
  /// generated project's `lib/`. This is how a graph reaches hand-written
  /// helpers in `lib/custom/` (§7.8, R11).
  final List<String> extraImports;

  /// Whether the page performs an HTTP request, and therefore needs the
  /// `http` package.
  final bool usesHttp;

  /// Whether it decodes JSON, and therefore needs `dart:convert`.
  final bool usesJson;

  /// Whether the page calls a server function, and therefore needs the
  /// generated RPC stubs (§7.7).
  final bool usesRpc;

  /// Whether this page reports state changes on the debug channel (R21).
  final bool usesDebug;

  /// Whether this page reads or writes a collection (R19).
  final bool usesCollections;

  /// File names of the prefabs this unit places, for its imports (R9).
  final List<String> usedPrefabs;

  /// A page with no state and no callbacks compiles to a `StatelessWidget`;
  /// there is no reason to pay for a `State` object that holds nothing.
  bool get isStateful =>
      signals.isNotEmpty ||
      hoisted.isNotEmpty ||
      handlers.isNotEmpty ||
      controllers.isNotEmpty;

  /// Controllers are the only reason a generated page needs `initState` and
  /// `dispose`; without them the State class is just fields and `build`.
  bool get needsLifecycle => controllers.isNotEmpty;
}

/// One server function, lowered (§7.7).
final class ServerFunctionIr {
  const ServerFunctionIr({
    required this.function,
    required this.helpers,
    required this.body,
    required this.usesModels,
    required this.usesJson,
    required this.usesHttp,
    required this.extraImports,
  });

  final ServerFunction function;
  final List<HelperIr> helpers;

  /// The expression the function answers with.
  final Emitted body;

  final bool usesModels;
  final bool usesJson;
  final bool usesHttp;
  final List<String> extraImports;
}

/// The lowered form of a whole project.
final class ProjectIr {
  const ProjectIr({
    required this.project,
    required this.pages,
    this.serverFunctions = const [],
  });

  final Project project;
  final List<PageIr> pages;
  final List<ServerFunctionIr> serverFunctions;

  bool get hasServer => serverFunctions.isNotEmpty;

  /// Whether any page talks HTTP, which decides the generated pubspec's
  /// dependencies. Calling a server function counts: the stubs use `http`.
  bool get usesHttp => pages.any((p) => p.usesHttp || p.usesRpc) || hasServer;
}
