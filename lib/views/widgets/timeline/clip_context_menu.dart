import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter/material.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/viewmodels/commands/remove_clip_command.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/utils/logger.dart' as logger;

/// Widget for clip context menu
class ClipContextMenu extends StatelessWidget {
  final ClipModel clip;

  const ClipContextMenu({super.key, required this.clip});

  @override
  Widget build(BuildContext context) {
    final timelineVm = di<TimelineViewModel>();

    return ShadContextMenu(
      items: [
        ShadContextMenuItem(
          leading: const Icon(LucideIcons.trash),
          child: const Text('Remove Clip'),
          onPressed: () {
            Navigator.of(context).pop();
            if (clip.databaseId != null) {
              timelineVm.runCommand(
                RemoveClipCommand(vm: timelineVm, clipId: clip.databaseId!),
              );
            } else {
              logger.logError(
                '[TimelineClip] Attempted to remove clip without databaseId',
                'UI',
              );
            }
          },
        ),
      ],
      child: const SizedBox.shrink(),
    );
  }
}
