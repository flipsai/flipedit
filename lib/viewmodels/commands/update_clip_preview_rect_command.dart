import 'dart:convert';
import 'dart:ui' show Rect;

import 'package:watch_it/watch_it.dart';

import '../../models/clip.dart';
import '../../services/project_database_service.dart';
import '../../services/preview_sync_service.dart';
import '../../services/undo_redo_service.dart';
import '../../utils/logger.dart';
import '../timeline_state_viewmodel.dart';
import 'timeline_command.dart';

class UpdateClipPreviewRectCommand extends TimelineCommand {
  final int clipId;
  final Rect newRect;
  final String _logTag = 'UpdateClipPreviewRectCommand';

  final ProjectDatabaseService _dbService = di<ProjectDatabaseService>();
  final UndoRedoService _undoRedoService = di<UndoRedoService>();
  final PreviewSyncService _previewSyncService = di<PreviewSyncService>();
  final TimelineStateViewModel _stateViewModel = di<TimelineStateViewModel>();

  ClipModel? _originalClipModel;
  int? _originalClipIndex;

  UpdateClipPreviewRectCommand({required this.clipId, required this.newRect});

  @override
  Future<void> execute() async {
    logInfo('Executing UpdateClipPreviewRectCommand for clip $clipId', _logTag);

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

    final updatedClipModel = _originalClipModel!.copyWithPreviewRect(newRect);

    final metadataJson =
        updatedClipModel.metadata.isNotEmpty
            ? jsonEncode(updatedClipModel.metadata)
            : null;
    final success = await _dbService.clipDao?.updateClipFields(clipId, {
      'metadataJson': metadataJson,
    });

    if (success != true) {
      logError(
        'Failed to update clip $clipId preview rect in database.',
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

    logInfo('Successfully updated preview rect for clip $clipId', _logTag);
  }

  @override
  Future<void> undo() async {
    logInfo('Undoing UpdateClipPreviewRectCommand for clip $clipId', _logTag);

    await _undoRedoService.undo();

    await _stateViewModel.refreshClips();

    await _previewSyncService.sendClipsToPreviewServer();

    logInfo(
      'Successfully triggered undo for preview rect update for clip $clipId. ViewModel refreshed.',
      _logTag,
    );
  }
}
