import 'tab_group.dart';

class TabLine {
  final String id;
  final List<TabGroup> tabColumns;
  final double? flexSize;

  const TabLine({
    required this.id,
    required this.tabColumns,
    this.flexSize,
  });

  bool get isEmpty => tabColumns.isEmpty;
  bool get isNotEmpty => !isEmpty;

  TabLine addColumn(TabGroup group, {int? atIndex}) {
    final updatedColumns = List<TabGroup>.from(tabColumns);
    if (atIndex != null && atIndex >= 0 && atIndex <= updatedColumns.length) {
      updatedColumns.insert(atIndex, group);
    } else {
      updatedColumns.add(group);
    }
    
    return TabLine(
      id: id,
      tabColumns: updatedColumns,
      flexSize: flexSize,
    );
  }

  TabLine removeColumn(String groupId) {
    final updatedColumns = tabColumns.where((group) => group.id != groupId).toList();
    
    return TabLine(
      id: id,
      tabColumns: updatedColumns,
      flexSize: flexSize,
    );
  }

  TabLine updateColumn(String groupId, TabGroup updatedGroup) {
    final updatedColumns = tabColumns.map((group) {
      return group.id == groupId ? updatedGroup : group;
    }).toList();
    
    return TabLine(
      id: id,
      tabColumns: updatedColumns,
      flexSize: flexSize,
    );
  }

  // Serialization methods for persistence
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tabColumns': tabColumns.map((group) => group.toJson()).toList(),
      'flexSize': flexSize,
    };
  }

  factory TabLine.fromJson(Map<String, dynamic> json) {
    return TabLine(
      id: json['id'] as String,
      tabColumns: (json['tabColumns'] as List)
          .map((groupJson) => TabGroup.fromJson(groupJson as Map<String, dynamic>))
          .toList(),
      flexSize: json['flexSize'] as double?,
    );
  }

  @override
  String toString() => 'TabLine(id: $id, columns: ${tabColumns.length}, flexSize: $flexSize)';
} 