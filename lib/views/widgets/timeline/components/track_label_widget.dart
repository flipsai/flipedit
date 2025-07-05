import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/persistence/database/project_database.dart';
import 'package:flutter/services.dart';

class TrackLabelWidget extends StatefulWidget {
  final Track track;
  final bool isSelected;
  final double width;
  final VoidCallback onDelete;
  final ValueChanged<String> onRename;
  final VoidCallback onSelect;

  const TrackLabelWidget({
    super.key,
    required this.track,
    required this.isSelected,
    required this.width,
    required this.onDelete,
    required this.onRename,
    required this.onSelect,
  });

  @override
  State<TrackLabelWidget> createState() => _TrackLabelWidgetState();
}

class _TrackLabelWidgetState extends State<TrackLabelWidget> {
  bool _isEditing = false;
  late TextEditingController _textController;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.track.name);
    _focusNode = FocusNode();

    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isEditing) {
        _submitRename();
      }
    });
  }

  @override
  void didUpdateWidget(covariant TrackLabelWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.track.name != oldWidget.track.name && !_isEditing) {
      _textController.text = widget.track.name;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _enterEditingMode() {
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

  void _submitRename() {
    final newName = _textController.text.trim();
    if (_isEditing) {
      if (newName.isNotEmpty && newName != widget.track.name) {
        widget.onRename(newName);
      }
      setState(() {
        _isEditing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return GestureDetector(
      onTap: widget.onSelect,
      child: Container(
        width: widget.width,
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        decoration: BoxDecoration(
          color:
              widget.isSelected
                  ? theme.accentColor.withValues(alpha: 0.2)
                  : theme.resources.subtleFillColorTertiary,
          border: Border(
            right: BorderSide(color: theme.resources.controlStrokeColorDefault),
            left:
                widget.isSelected
                    ? BorderSide(color: theme.accentColor, width: 3.0)
                    : BorderSide.none,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ReorderableDragStartListener(
              index: 0,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Icon(
                    FluentIcons.more_vertical,
                    size: 12,
                    color: theme.resources.textFillColorSecondary,
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onDoubleTap: _enterEditingMode,
                child:
                    _isEditing
                        ? TextBox(
                          controller: _textController,
                          focusNode: _focusNode,
                          placeholder: 'Track Name',
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6.0,
                            vertical: 4.0,
                          ),
                          style: theme.typography.body,
                          decoration: WidgetStateProperty.all(
                            BoxDecoration(
                              color: theme.resources.controlFillColorDefault,
                              borderRadius: BorderRadius.circular(4.0),
                            ),
                          ),
                          onSubmitted: (_) => _submitRename(),
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(64),
                          ],
                        )
                        : Text(
                          widget.track.name,
                          overflow: TextOverflow.ellipsis,
                          style: theme.typography.body,
                        ),
              ),
            ),
            IconButton(
              icon: const Icon(FluentIcons.delete, size: 14),
              onPressed: widget.onDelete,
              style: ButtonStyle(
                padding: WidgetStateProperty.all(EdgeInsets.zero),
                textStyle: WidgetStateProperty.all(
                  const TextStyle(inherit: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
