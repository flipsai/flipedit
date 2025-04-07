import 'dart:convert';
import 'dart:io';
import 'node.dart';
import 'connection.dart';

/// Represents a ComfyUI workflow
class Workflow {
  final String id;
  final String name;
  final List<Node> nodes;
  final List<Connection> connections;
  final Map<String, dynamic> metadata;
  
  Workflow({
    required this.id,
    required this.name,
    required this.nodes,
    required this.connections,
    this.metadata = const {},
  });
  
  /// Create a new workflow from JSON
  factory Workflow.fromJson(Map<String, dynamic> json) {
    final nodesList = <Node>[];
    final connectionsList = <Connection>[];
    
    // Parse nodes
    if (json.containsKey('nodes')) {
      for (final nodeJson in json['nodes'].entries) {
        nodesList.add(Node.fromJson(nodeJson.key, nodeJson.value));
      }
    }
    
    // Parse connections
    if (json.containsKey('connections')) {
      for (final connectionJson in json['connections']) {
        connectionsList.add(Connection.fromJson(connectionJson));
      }
    }
    
    return Workflow(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name'] ?? 'Untitled Workflow',
      nodes: nodesList,
      connections: connectionsList,
      metadata: json['metadata'] ?? {},
    );
  }
  
  /// Convert workflow to JSON for ComfyUI
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> nodesMap = {};
    for (final node in nodes) {
      nodesMap[node.id] = node.toJson();
    }
    
    final List<Map<String, dynamic>> connectionsJson = [];
    for (final connection in connections) {
      connectionsJson.add(connection.toJson());
    }
    
    return {
      'id': id,
      'name': name,
      'nodes': nodesMap,
      'connections': connectionsJson,
      'metadata': metadata,
    };
  }
  
  /// Load workflow from a JSON file
  static Future<Workflow?> fromFile(String filePath) async {
    try {
      final file = await File(filePath).readAsString();
      final json = jsonDecode(file);
      return Workflow.fromJson(json);
    } catch (e) {
      print('Error loading workflow: $e');
      return null;
    }
  }
  
  /// Save workflow to a JSON file
  Future<bool> toFile(String filePath) async {
    try {
      final file = File(filePath);
      await file.writeAsString(jsonEncode(toJson()));
      return true;
    } catch (e) {
      print('Error saving workflow: $e');
      return false;
    }
  }
}
