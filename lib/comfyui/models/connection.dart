/// Represents a connection between nodes in a ComfyUI workflow
class Connection {
  final String fromNodeId;
  final String fromOutputName;
  final String toNodeId;
  final String toInputName;

  Connection({
    required this.fromNodeId,
    required this.fromOutputName,
    required this.toNodeId,
    required this.toInputName,
  });

  /// Create a new connection from JSON
  factory Connection.fromJson(Map<String, dynamic> json) {
    return Connection(
      fromNodeId: json['from_node'] ?? '',
      fromOutputName: json['from_output'] ?? '',
      toNodeId: json['to_node'] ?? '',
      toInputName: json['to_input'] ?? '',
    );
  }

  /// Convert connection to JSON for ComfyUI
  Map<String, dynamic> toJson() {
    return {
      'from_node': fromNodeId,
      'from_output': fromOutputName,
      'to_node': toNodeId,
      'to_input': toInputName,
    };
  }
}
