import 'package:fluent_ui/fluent_ui.dart';

/// A label widget for timeline tracks that displays an icon and text
class TrackLabel extends StatelessWidget {
  final String label;
  final IconData icon;

  const TrackLabel({
    super.key,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      margin: const EdgeInsets.only(
        bottom: 4,
        left: 4,
        right: 4,
      ),
      decoration: BoxDecoration(
        color: theme.resources.subtleFillColorTertiary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.resources.textFillColorSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.typography.body?.copyWith(
                color: theme.resources.textFillColorPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
} 