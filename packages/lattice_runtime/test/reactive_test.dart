import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice_runtime/lattice_runtime.dart';

void main() {
  group('Signal', () {
    test('notifies only on a real change', () {
      final count = signal(0);
      var notifications = 0;
      count.addListener(() => notifications++);

      count.value = 1;
      count.value = 1; // same value
      expect(notifications, 1);

      count.value = 2;
      expect(notifications, 2);
    });

    test('update applies a function to the current value', () {
      final count = signal(1);
      count.update((x) => x + 41);
      expect(count.value, 42);
    });

    test('peek reads without creating a dependency', () {
      final count = signal(0);
      final derived = computed(() => count.peek + 1);
      expect(derived.value, 1);

      count.value = 10;
      // Nothing was tracked, so the cached value stands.
      expect(derived.value, 1);
    });
  });

  group('Computed', () {
    test('derives from signals and recomputes lazily', () {
      final first = signal(2);
      final second = signal(3);
      var evaluations = 0;
      final sum = computed(() {
        evaluations++;
        return first.value + second.value;
      });

      expect(sum.value, 5);
      expect(evaluations, 1);

      // Reading again does not re-evaluate.
      expect(sum.value, 5);
      expect(evaluations, 1);

      first.value = 10;
      expect(sum.value, 13);
      expect(evaluations, 2);
    });

    test('chains', () {
      final base = signal(1);
      final doubled = computed(() => base.value * 2);
      final labelled = computed(() => 'v=${doubled.value}');

      expect(labelled.value, 'v=2');
      base.value = 21;
      expect(labelled.value, 'v=42');
    });

    test('drops dependencies it stops reading', () {
      final toggle = signal(true);
      final a = signal(1);
      final b = signal(100);
      var evaluations = 0;
      final picked = computed(() {
        evaluations++;
        return toggle.value ? a.value : b.value;
      });

      expect(picked.value, 1);
      final afterFirst = evaluations;

      // `b` is not a dependency yet.
      b.value = 200;
      expect(picked.value, 1);
      expect(evaluations, afterFirst);

      toggle.value = false;
      expect(picked.value, 200);

      // Now `a` is no longer a dependency.
      final afterSwitch = evaluations;
      a.value = 5;
      expect(picked.value, 200);
      expect(evaluations, afterSwitch);
    });
  });

  group('batch', () {
    test('collapses several writes into one notification', () {
      final a = signal(0);
      final b = signal(0);
      final sum = computed(() => a.value + b.value);
      var notifications = 0;
      sum.addListener(() => notifications++);
      expect(sum.value, 0);

      batch(() {
        a.value = 1;
        b.value = 2;
      });

      expect(notifications, 1);
      expect(sum.value, 3);
    });
  });

  group('effect', () {
    test('runs immediately and on every dependency change', () {
      final count = signal(0);
      final seen = <int>[];
      final dispose = effect(() => seen.add(count.value));

      expect(seen, [0]);
      count.value = 1;
      count.value = 2;
      expect(seen, [0, 1, 2]);

      dispose();
      count.value = 3;
      expect(seen, [0, 1, 2]);
    });
  });

  group('SignalBuilder', () {
    testWidgets('rebuilds when a signal it read changes', (tester) async {
      final count = signal(0);
      var builds = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: SignalBuilder(
            builder: (context) {
              builds++;
              return Text('${count.value}', textDirection: TextDirection.ltr);
            },
          ),
        ),
      );

      expect(find.text('0'), findsOneWidget);
      expect(builds, 1);

      count.value = 7;
      await tester.pump();

      expect(find.text('7'), findsOneWidget);
      expect(builds, 2);
    });

    testWidgets('does not rebuild for a signal it never read', (tester) async {
      final watched = signal(0);
      final ignored = signal(0);
      var builds = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: SignalBuilder(
            builder: (context) {
              builds++;
              return Text('${watched.value}', textDirection: TextDirection.ltr);
            },
          ),
        ),
      );
      expect(builds, 1);

      ignored.value = 99;
      await tester.pump();
      expect(builds, 1);
    });

    testWidgets('stops listening once disposed', (tester) async {
      final count = signal(0);

      await tester.pumpWidget(
        MaterialApp(
          home: SignalBuilder(builder: (context) => Text('${count.value}')),
        ),
      );
      expect(count.hasSubscribers, isTrue);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(count.hasSubscribers, isFalse);
    });
  });

  group('SignalInspector', () {
    test('records signals for the data-flow debugger (R21)', () {
      final count = SignalInspector.register('n_count', signal(3));
      expect(SignalInspector.snapshot()['n_count'], 3);

      count.value = 9;
      expect(SignalInspector.snapshot()['n_count'], 9);

      SignalInspector.unregister('n_count');
      expect(SignalInspector.snapshot().containsKey('n_count'), isFalse);
    });
  });
}
