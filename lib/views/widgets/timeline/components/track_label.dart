import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/persistence/database/project_database.dart';

/// A label widget for timeline tracks that displays an icon, text,
/// and allows renaming on double-click.
class TrackLabel extends StatefulWidget with WatchItStatefulWidgetMixin {
  final Track track;
  final VoidCallback? onDelete;

  const TrackLabel({super.key, required this.track, this.onDelete});

  @override
  State<TrackLabel> createState() => _TrackLabelState();
}

class _TrackLabelState extends State<TrackLabel> {
  bool _isEditing = false;
  late TextEditingController _textController;
  final FocusNode _focusNode = FocusNode();

  late ProjectDatabaseService databaseService;

  @override
  void initState() {
    super.initState();
    databaseService = di<ProjectDatabaseService>();
    _textController = TextEditingController(text: widget.track.name);

    _focusNode.addListener(() {
      if (_focusNode.hasFocus && !_isEditing) {
        setState(() {
          _isEditing = true;
        });
      }
      if (!_focusNode.hasFocus && _isEditing) {
        _submitNameChange();
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TrackLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.track.name != oldWidget.track.name && !_isEditing) {
      _textController.text = widget.track.name;
    }
  }

  void _startEditing() {
    if (!_isEditing) {
      setState(() {
        _isEditing = true;
        _textController.text = widget.track.name;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
        _textController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _textController.text.length,
        );
      });
    }
  }

  void _submitNameChange() {
    if (_isEditing) {
      final newName = _textController.text.trim();
      if (newName.isNotEmpty && newName != widget.track.name) {
        databaseService.updateTrackName(widget.track.id, newName);
      }
      setState(() {
        _isEditing = false;
        _textController.text = widget.track.name;
      });
      _focusNode.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon =
        widget.track.type == 'video'
            ? Icons.videocam
            : Icons.music_note;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        if (_isEditing && !_focusNode.hasFocus) {
          _submitNameChange();
        }
      },
      onDoubleTap: _startEditing,
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        margin: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
        decoration: BoxDecoration(
          color: theme.disabledColor.withAlpha(50),
          borderRadius: BorderRadius.circular(4),
          border:
              _isEditing
                  ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                  : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: theme.hintColor),
            const SizedBox(width: 8),
            Expanded(
              child:
                  _isEditing
                      ? TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        style: theme.textTheme.bodyMedium,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 6,
                          ),
                        ),
                        onSubmitted: (_) => _submitNameChange(),
                      )
                      : Text(
                        widget.track.name,
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
            ),
            if (widget.onDelete != null)
              SizedBox(
                width: 20,
                height: 20,
                child: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 12),
                  onPressed: widget.onDelete,
                  style: IconButton.styleFrom(
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
