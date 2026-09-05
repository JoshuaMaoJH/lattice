import '../models.dart';

/// Hand-written, called from the graph through a `Dart Code` node.
///
/// Codegen copies `custom/` into the generated project's `lib/custom/` and
/// never overwrites it, so this file is the escape hatch that makes Lattice's
/// expressive ceiling equal to Dart's own (§7.8).
String decorate(String title, {required bool done}) =>
    done ? '✓ $title' : title;

/// Counts finished items. A fold is a fold — no reason to draw one.
int countDone(List<Todo> todos) => todos.where((todo) => todo.done).length;
