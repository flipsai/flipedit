import 'tab_item.dart';
import '../services/tab_content_factory.dart';

enum TabGroupOrientation { horizontal, vertical }

class TabGroup {
  final String id;
  final List<TabItem> tabs;
  final int activeIndex;
  final TabGroupOrientation orientation;
  final double? flexSize;
  final double minSize;
  final double maxSize;
  final bool isCollapsible;
  final bool isCollapsed;

  const TabGroup({
    required this.id,
    required this.tabs,
    this.activeIndex = 0,
    this.orientation = TabGroupOrientation.horizontal,
    this.flexSize,
    this.minSize = 100.0,
    this.maxSize = double.infinity,
    this.isCollapsible = false,
    this.isCollapsed = false,
  });

  bool get hasActiveTabs => tabs.isNotEmpty && activeIndex >= 0 && activeIndex < tabs.length;
  TabItem? get activeTab => hasActiveTabs ? tabs[activeIndex] : null;
  bool get isEmpty => tabs.isEmpty;
  int get tabCount => tabs.length;

  TabGroup copyWith({
    String? id,
    List<TabItem>? tabs,
    int? activeIndex,
    TabGroupOrientation? orientation,
    double? flexSize,
    double? minSize,
    double? maxSize,
    bool? isCollapsible,
    bool? isCollapsed,
  }) {
    return TabGroup(
      id: id ?? this.id,
      tabs: tabs ?? this.tabs,
      activeIndex: activeIndex ?? this.activeIndex,
      orientation: orientation ?? this.orientation,
      flexSize: flexSize ?? this.flexSize,
      minSize: minSize ?? this.minSize,
      maxSize: maxSize ?? this.maxSize,
      isCollapsible: isCollapsible ?? this.isCollapsible,
      isCollapsed: isCollapsed ?? this.isCollapsed,
    );
  }

  TabGroup addTab(TabItem tab, {int? atIndex}) {
    final List<TabItem> newTabs = List.from(tabs);
    final int insertIndex = atIndex ?? newTabs.length;
    newTabs.insert(insertIndex, tab);
    
    int newActiveIndex = activeIndex;
    if (insertIndex <= activeIndex) {
      newActiveIndex = activeIndex + 1;
    } else if (tabs.isEmpty) {
      newActiveIndex = 0;
    }

    return copyWith(tabs: newTabs, activeIndex: newActiveIndex);
  }

  TabGroup removeTab(String tabId) {
    final int tabIndex = tabs.indexWhere((tab) => tab.id == tabId);
    if (tabIndex == -1) return this;

    final List<TabItem> newTabs = List.from(tabs);
    newTabs.removeAt(tabIndex);

    int newActiveIndex = activeIndex;
    if (tabIndex == activeIndex) {
      if (newTabs.isEmpty) {
        newActiveIndex = -1;
      } else if (tabIndex >= newTabs.length) {
        newActiveIndex = newTabs.length - 1;
      }
    } else if (tabIndex < activeIndex) {
      newActiveIndex = activeIndex - 1;
    }

    return copyWith(tabs: newTabs, activeIndex: newActiveIndex);
  }

  TabGroup moveTab(int fromIndex, int toIndex) {
    if (fromIndex == toIndex || fromIndex < 0 || fromIndex >= tabs.length) {
      return this;
    }

    final List<TabItem> newTabs = List.from(tabs);
    final TabItem movedTab = newTabs.removeAt(fromIndex);
    final int actualToIndex = toIndex > fromIndex ? toIndex - 1 : toIndex;
    newTabs.insert(actualToIndex, movedTab);

    int newActiveIndex = activeIndex;
    if (fromIndex == activeIndex) {
      newActiveIndex = actualToIndex;
    } else if (fromIndex < activeIndex && actualToIndex >= activeIndex) {
      newActiveIndex = activeIndex - 1;
    } else if (fromIndex > activeIndex && actualToIndex <= activeIndex) {
      newActiveIndex = activeIndex + 1;
    }

    return copyWith(tabs: newTabs, activeIndex: newActiveIndex);
  }

  TabGroup setActiveTab(String tabId) {
    final int tabIndex = tabs.indexWhere((tab) => tab.id == tabId);
    if (tabIndex == -1) return this;
    return copyWith(activeIndex: tabIndex);
  }

  TabGroup setActiveIndex(int index) {
    if (index < 0 || index >= tabs.length) return this;
    return copyWith(activeIndex: index);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tabs': tabs.map((tab) => tab.toJson()).toList(),
      'activeIndex': activeIndex,
      'orientation': orientation.name,
      'flexSize': flexSize,
      'minSize': minSize,
      'maxSize': maxSize == double.infinity ? null : maxSize,
      'isCollapsible': isCollapsible,
      'isCollapsed': isCollapsed,
    };
  }

  static TabGroup fromJson(Map<String, dynamic> json) {
    final List<dynamic> tabsJson = json['tabs'] as List<dynamic>;
    final List<TabItem> tabs = tabsJson
        .map((tabJson) => TabContentFactory.recreateTabFromJson(tabJson as Map<String, dynamic>))
        .toList();

    return TabGroup(
      id: json['id'] as String,
      tabs: tabs,
      activeIndex: json['activeIndex'] as int? ?? 0,
      orientation: _parseOrientation(json['orientation'] as String?),
      flexSize: (json['flexSize'] as num?)?.toDouble(),
      minSize: (json['minSize'] as num?)?.toDouble() ?? 100.0,
      maxSize: json['maxSize'] != null 
          ? (json['maxSize'] as num).toDouble() 
          : double.infinity,
      isCollapsible: json['isCollapsible'] as bool? ?? false,
      isCollapsed: json['isCollapsed'] as bool? ?? false,
    );
  }

  static TabGroupOrientation _parseOrientation(String? orientationString) {
    switch (orientationString) {
      case 'horizontal':
        return TabGroupOrientation.horizontal;
      case 'vertical':
        return TabGroupOrientation.vertical;
      default:
        return TabGroupOrientation.horizontal;
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TabGroup && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'TabGroup(id: $id, tabCount: $tabCount, activeIndex: $activeIndex)';
  }
} 