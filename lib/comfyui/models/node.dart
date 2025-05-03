/// Represents a node in a ComfyUI workflow
class Node {
  final String id;
  final String type;
  final Map<String, dynamic> inputs;
  final Map<String, dynamic> outputs;
  final Map<String, dynamic> properties;
  final int posX;
  final int posY;

  Node({
    required this.id,
    required this.type,
    this.inputs = const {},
    this.outputs = const {},
    this.properties = const {},
    this.posX = 0,
    this.posY = 0,
  });

  /// Create a new node from JSON
  factory Node.fromJson(String id, Map<String, dynamic> json) {
    return Node(
      id: id,
      type: json['type'] ?? '',
      inputs: json['inputs'] ?? {},
      outputs: json['outputs'] ?? {},
      properties: json['properties'] ?? {},
      posX: json['pos_x'] ?? 0,
      posY: json['pos_y'] ?? 0,
    );
  }

  /// Convert node to JSON for ComfyUI
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'inputs': inputs,
      'outputs': outputs,
      'properties': properties,
      'pos_x': posX,
      'pos_y': posY,
    };
  }
}
