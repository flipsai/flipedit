import 'package:flutter/material.dart';

class TabItem {
  final String id;
  final String title;
  final String? subtitle;
  final Widget content;
  final Widget? icon;
  final bool isClosable;
  final bool isModified;
  final bool isPinned;
  final Color? accentColor;
  final Map<String, dynamic>? metadata;

  const TabItem({
    required this.id,
    required this.title,
    required this.content,
    this.subtitle,
    this.icon,
    this.isClosable = true,
    this.isModified = false,
    this.isPinned = false,
    this.accentColor,
    this.metadata,
  });

  TabItem copyWith({
    String? id,
    String? title,
    String? subtitle,
    Widget? content,
    Widget? icon,
    bool? isClosable,
    bool? isModified,
    bool? isPinned,
    Color? accentColor,
    Map<String, dynamic>? metadata,
  }) {
    return TabItem(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      content: content ?? this.content,
      icon: icon ?? this.icon,
      isClosable: isClosable ?? this.isClosable,
      isModified: isModified ?? this.isModified,
      isPinned: isPinned ?? this.isPinned,
      accentColor: accentColor ?? this.accentColor,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'isClosable': isClosable,
      'isModified': isModified,
      'isPinned': isPinned,
      'accentColor': accentColor?.value,
      'metadata': metadata,
    };
  }

  static TabItem fromJson(Map<String, dynamic> json) {
    // This will be handled by TabContentFactory to recreate the content widget
    throw UnimplementedError(
      'Use TabContentFactory.recreateTabFromJson() instead of TabItem.fromJson()'
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TabItem && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'TabItem(id: $id, title: $title, isModified: $isModified, isPinned: $isPinned)';
  }
} 