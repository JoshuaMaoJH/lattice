import 'package:flutter_test/flutter_test.dart';
import 'package:lattice_editor/src/host/debug_channel.dart';

void main() {
  late DebugChannel channel;

  setUp(() => channel = DebugChannel());

  test('an ordinary log line is left alone', () {
    expect(channel.consume('Syncing files to device Linux...'), isFalse);
    expect(channel.isEmpty, isTrue);
  });

  test('a marked line is claimed and recorded', () {
    expect(
      channel.consume('__lattice__ {"node":"n_count","value":3}'),
      isTrue,
    );

    final observation = channel.signals['n_count']!;
    expect(observation.value, 3);
    expect(observation.changes, 1);
  });

  test('the marker is found even behind flutter run\'s own prefix', () {
    // `flutter run` prefixes app output with `I/flutter (12345):`.
    channel.consume('I/flutter (1234): __lattice__ {"node":"n_a","value":1}');

    expect(channel.signals['n_a']?.value, 1);
  });

  test('repeated writes count up rather than pile up', () {
    channel.consume('__lattice__ {"node":"n_count","value":1}');
    channel.consume('__lattice__ {"node":"n_count","value":2}');

    expect(channel.signals, hasLength(1));
    expect(channel.signals['n_count']!.changes, 2);
    expect(channel.signals['n_count']!.value, 2);
  });

  test('recent order is by last write, newest first', () {
    channel.consume('__lattice__ {"node":"a","value":1}');
    channel.consume('__lattice__ {"node":"b","value":1}');
    channel.consume('__lattice__ {"node":"a","value":2}');

    expect(channel.recent().map((o) => o.nodeId), ['a', 'b']);
    expect(channel.isRecent('a'), isTrue);
  });

  test('a malformed payload is swallowed, not raised', () {
    // The preview's output is not a protocol we control; a debug panel must
    // never be the reason the editor stops.
    expect(channel.consume('__lattice__ {not json'), isTrue);
    expect(channel.consume('__lattice__ ["unexpected"]'), isTrue);
    expect(channel.consume('__lattice__ {"value":3}'), isTrue);
    expect(channel.isEmpty, isTrue);
  });

  test('handler entries are recorded separately from values', () {
    channel.consume('__lattice__ {"event":"ev_btn"}');

    expect(channel.events, ['ev_btn']);
    expect(channel.signals, isEmpty);
  });

  test('clearing forgets a dead process', () {
    channel.consume('__lattice__ {"node":"n","value":1}');
    channel.clear();

    expect(channel.isEmpty, isTrue);
    // Sequence restarts too, or the first write after a restart would sort
    // below values that no longer exist.
    channel.consume('__lattice__ {"node":"m","value":1}');
    expect(channel.signals['m']!.sequence, 1);
  });
}
