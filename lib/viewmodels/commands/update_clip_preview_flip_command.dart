import 'dart:convert';
import 'package:flutter_box_transform/flutter_box_transform.dart' show Flip;
import 'package:watch_it/watch_it.dart';

import '../../models/clip.dart';
import '../../services/project_database_service.dart';
import '../../services/preview_sync_service.dart';
import '../../services/undo_redo_service.dart';
import '../../utils/logger.dart';
import '../timeline_state_viewmodel.dart';
import 'timeline_command.dart';

class UpdateClipPreviewFlipCommand extends TimelineCommand {
  final int clipId;
  final Flip newFlip;
  final String _logTag = 'UpdateClipPreviewFlipCommand';

  final ProjectDatabaseService _dbService = di<ProjectDatabaseService>();
  final UndoRedoService _undoRedoService = di<UndoRedoService>();
  final PreviewSyncService _previewSyncService = di<PreviewSyncService>();
  final TimelineStateViewModel _stateViewModel = di<TimelineStateViewModel>();

  ClipModel? _originalClipModel;
  int? _originalClipIndex;

  UpdateClipPreviewFlipCommand({required this.clipId, required this.newFlip});

  @override
  Future<void> execute() async {
    logInfo('Executing UpdateClipPreviewFlipCommand for clip $clipId', _logTag);

    _originalClipIndex = _stateViewModel.clipsNotifier.value.indexWhere(
      (c) => c.databaseId == clipId,
    );
    if (_originalClipIndex == null || _originalClipIndex! < 0) {
      logError(
        'Clip with ID $clipId not found in ViewModel.',
        null,
        null,
        _logTag,
      );
      throw Exception('Clip not found for update');
    }
    _originalClipModel =
        _stateViewModel.clipsNotifier.value[_originalClipIndex!];

    final updatedClipModel = _originalClipModel!.copyWithPreviewFlip(newFlip);

    final metadataJson =
        updatedClipModel.metadata.isNotEmpty
            ? jsonEncode(updatedClipModel.metadata)
            : null;
    final success = await _dbService.clipDao?.updateClipFields(clipId, {
      'metadataJson': metadataJson,
    });

    if (success != true) {
      logError(
        'Failed to update clip $clipId preview flip in database.',
        null,
        null,
        _logTag,
      );
      throw Exception('Database update failed');
    }

    final updatedList = List<ClipModel>.from(
      _stateViewModel.clipsNotifier.value,
    );
    updatedList[_originalClipIndex!] = updatedClipModel;
    _stateViewModel.clipsNotifier.value = updatedList;

    await _previewSyncService.sendClipsToPreviewServer();

    await _undoRedoService.init();

    logInfo('Successfully updated preview flip for clip $clipId', _logTag);
  }

  @override
  Future<void> undo() async {
    logInfo('Undoing UpdateClipPreviewFlipCommand for clip $clipId', _logTag);

    await _undoRedoService.undo();

    await _stateViewModel.refreshClips();

    await _previewSyncService.sendClipsToPreviewServer();

    logInfo(
      'Successfully triggered undo for preview flip update for clip $clipId. ViewModel refreshed.',
      _logTag,
    );
  }
}
