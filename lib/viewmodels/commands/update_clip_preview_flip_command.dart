import 'dart:convert';
import 'package:flutter_box_transform/flutter_box_transform.dart' show Flip; // Import Flip
import 'package:flutter/foundation.dart';
import 'package:watch_it/watch_it.dart';

import '../../models/clip.dart';
import '../../services/project_database_service.dart';
import '../../services/preview_sync_service.dart';
import '../../services/undo_redo_service.dart';
import '../../utils/logger.dart';
// import '../timeline_viewmodel.dart'; // No longer needed
import '../timeline_state_viewmodel.dart'; // Import State VM
import 'timeline_command.dart';
import 'package:watch_it/watch_it.dart'; // Import for di

class UpdateClipPreviewFlipCommand extends TimelineCommand {
  // final TimelineViewModel vm; // REMOVED
  final int clipId;
  final Flip newFlip;
  final String _logTag = 'UpdateClipPreviewFlipCommand';

  // Services
  final ProjectDatabaseService _dbService = di<ProjectDatabaseService>();
  final UndoRedoService _undoRedoService = di<UndoRedoService>();
  final PreviewSyncService _previewSyncService = di<PreviewSyncService>();
  final TimelineStateViewModel _stateViewModel = di<TimelineStateViewModel>(); // Inject State VM

  // State for optimistic update / potential manual revert (though service handles DB)
  ClipModel? _originalClipModel;
  int? _originalClipIndex;

  UpdateClipPreviewFlipCommand({
    // required this.vm, // REMOVED
    required this.clipId,
    required this.newFlip,
  }); // No super call needed

  @override
  Future<void> execute() async {
    logInfo('Executing UpdateClipPreviewFlipCommand for clip $clipId', _logTag);

    // 1. Find the original clip and its index in the State ViewModel
    _originalClipIndex = _stateViewModel.clipsNotifier.value.indexWhere((c) => c.databaseId == clipId);
    if (_originalClipIndex == null || _originalClipIndex! < 0) {
      logError('Clip with ID $clipId not found in ViewModel.', null, null, _logTag);
      throw Exception('Clip not found for update');
    }
    // Store the original model instance *before* modification
    _originalClipModel = _stateViewModel.clipsNotifier.value[_originalClipIndex!];

    // 2. Create the updated clip model for optimistic update
    final updatedClipModel = _originalClipModel!.copyWithPreviewFlip(newFlip);

    // 3. Update Database (DAO handles logging the change)
    final metadataJson = updatedClipModel.metadata.isNotEmpty ? jsonEncode(updatedClipModel.metadata) : null;
    final success = await _dbService.clipDao?.updateClipFields(
      clipId,
      {'metadataJson': metadataJson},
      // log: true // DAO defaults to true
    );

    if (success != true) {
      logError('Failed to update clip $clipId preview flip in database.', null, null, _logTag);
      // Don't update optimistically if DB fails
      throw Exception('Database update failed');
    }

    // 4. Update State ViewModel state (optimistic)
    final updatedList = List<ClipModel>.from(_stateViewModel.clipsNotifier.value);
    updatedList[_originalClipIndex!] = updatedClipModel;
    _stateViewModel.clipsNotifier.value = updatedList;

    // 5. Sync with preview server
    await _previewSyncService.sendClipsToPreviewServer();

    // 6. Notify Undo/Redo Service to reload logs
    await _undoRedoService.init();

    logInfo('Successfully updated preview flip for clip $clipId', _logTag);
  }

  @override
  Future<void> undo() async {
    logInfo('Undoing UpdateClipPreviewFlipCommand for clip $clipId', _logTag);

    // 1. Tell the service to undo the last operation
    await _undoRedoService.undo();

    // 2. Refresh the State ViewModel's clips from the database
    await _stateViewModel.refreshClips(); // Refresh State VM

    // 3. Sync with preview server again after state is refreshed
    await _previewSyncService.sendClipsToPreviewServer();

    logInfo('Successfully triggered undo for preview flip update for clip $clipId. ViewModel refreshed.', _logTag);
  }
}