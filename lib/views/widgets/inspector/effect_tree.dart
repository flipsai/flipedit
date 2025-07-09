import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter/material.dart';
import 'package:flipedit/models/effect.dart';
import 'package:flipedit/models/enums/effect_type.dart';

class EffectTree extends StatelessWidget {
  final List<Effect> effects;
  final Function(Effect) onEffectSelected;

  const EffectTree({
    super.key,
    required this.effects,
    required this.onEffectSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (effects.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text('No effects applied'),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.withAlpha(77)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _EffectTreeItem(
            label: 'Original Footage',
            level: 0,
            icon: LucideIcons.video,
            onTap: () {},
          ),

          ...effects.expand((effect) => _buildEffectItems(effect, 1)),
        ],
      ),
    );
  }

  List<Widget> _buildEffectItems(Effect effect, int level) {
    final List<Widget> items = [];

    items.add(
      _EffectTreeItem(
        label: effect.name,
        level: level,
        icon: _getIconForEffectType(effect.type),
        onTap: () => onEffectSelected(effect),
      ),
    );

    for (final childEffect in effect.childEffects) {
      items.addAll(_buildEffectItems(childEffect, level + 1));
    }

    return items;
  }

  IconData _getIconForEffectType(EffectType type) {
    switch (type) {
      case EffectType.backgroundRemoval:
        return LucideIcons.scissors;
      case EffectType.objectTracking:
        return LucideIcons.eye;
      case EffectType.colorCorrection:
        return LucideIcons.palette;
      case EffectType.transform:
        return LucideIcons.move;
      case EffectType.filter:
        return LucideIcons.settings;
      case EffectType.transition:
        return LucideIcons.shuffle;
      case EffectType.text:
        return LucideIcons.type;
    }
  }
}

class _EffectTreeItem extends StatelessWidget {
  final String label;
  final int level;
  final IconData icon;
  final VoidCallback onTap;

  const _EffectTreeItem({
    required this.label,
    required this.level,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.only(
          left: 8.0 + level * 16.0,
          right: 8.0,
          top: 6.0,
          bottom: 6.0,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.withAlpha(77))),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: Colors.grey),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
