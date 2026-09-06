import 'package:flutter/material.dart';

import '../host/debug_channel.dart';
import '../host/editor_host.dart';
import '../state/editor_controller.dart';
import '../theme.dart';

/// What the running app is actually doing (R21).
///
/// The canvas already shows each signal's current value on its node; this is
/// the part a node cannot show — the order things happened in. Reading down
/// the list is reading the data flow.
class DataFlowPanel extends StatelessWidget {
  const DataFlowPanel({
    super.key,
    required this.controller,
    required this.host,
  });

  final EditorController controller;
  final EditorHost host;

  @override
  Widget build(BuildContext context) {
    final flow = host.dataFlow;
    if (!host.canRunPreview) {
      return _message(
        'The data flow comes from a running preview, and this is '
        '${host.description}.',
      );
    }
    if (flow.isEmpty) {
      return _message(
        host.previewStatus == PreviewStatus.running
            ? 'Nothing has changed yet. Interact with the preview.'
            : 'Start the preview to watch state change.',
      );
    }

    final signals = flow.signals.values.toList()
      ..sort((a, b) => b.sequence.compareTo(a.sequence));

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        for (final observation in signals) _row(flow, observation),
      ],
    );
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            text,
            style: LatticeTheme.secondary,
            textAlign: TextAlign.center,
          ),
        ),
      );

  Widget _row(DebugChannel flow, SignalObservation observation) {
    final node = controller.activeUnit.graph.node(observation.nodeId);
    final label = node?.get<String>('name') ?? observation.nodeId;
    final recent = flow.isRecent(observation.nodeId);

    return InkWell(
      onTap: () => controller.select(NodeSelection(observation.nodeId)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 160,
              child: Text(
                label,
                style: LatticeTheme.monoSmall.copyWith(
                  color:
                      recent ? LatticeTheme.warning : LatticeTheme.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: Text(
                '${observation.value}',
                style: LatticeTheme.monoSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              // How many times, not when: a timestamp would be noise at this
              // rate, but "written 14 times" catches a loop immediately.
              observation.changes == 1
                  ? 'once'
                  : '${observation.changes} times',
              style: LatticeTheme.secondary,
            ),
          ],
        ),
      ),
    );
  }
}
