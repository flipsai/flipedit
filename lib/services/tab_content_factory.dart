import 'package:fluent_ui/fluent_ui.dart';
import '../models/tab_item.dart';

enum TabContentType {
  document,
  video,
  audio,
  terminal,
  generic,
}

class TabContentFactory {
  static TabItem createDocumentTab({
    required String id,
    required String title,
    bool isModified = false,
    Map<String, dynamic>? metadata,
  }) {
    return TabItem(
      id: id,
      title: title,
      icon: const Icon(FluentIcons.document, size: 16),
      content: _buildDocumentContent(title),
      isModified: isModified,
      metadata: {
        'type': TabContentType.document.name,
        ...?metadata,
      },
    );
  }

  static TabItem createVideoTab({
    required String id,
    required String title,
    bool isModified = false,
    Map<String, dynamic>? metadata,
  }) {
    return TabItem(
      id: id,
      title: title,
      icon: const Icon(FluentIcons.video, size: 16),
      content: _buildVideoContent(title),
      isModified: isModified,
      metadata: {
        'type': TabContentType.video.name,
        ...?metadata,
      },
    );
  }

  static TabItem createAudioTab({
    required String id,
    required String title,
    bool isModified = false,
    Map<String, dynamic>? metadata,
  }) {
    return TabItem(
      id: id,
      title: title,
      icon: const Icon(FluentIcons.music_note, size: 16),
      content: _buildAudioContent(title),
      isModified: isModified,
      metadata: {
        'type': TabContentType.audio.name,
        ...?metadata,
      },
    );
  }

  static TabItem createGenericTab({
    required String id,
    required String title,
    bool isModified = false,
    Map<String, dynamic>? metadata,
  }) {
    return TabItem(
      id: id,
      title: title,
      icon: const Icon(FluentIcons.document, size: 16),
      content: _buildGenericContent(title),
      isModified: isModified,
      metadata: {
        'type': TabContentType.generic.name,
        ...?metadata,
      },
    );
  }

  static TabItem createTerminalTab({
    required String id,
    required String title,
    bool isModified = false,
    Map<String, dynamic>? metadata,
  }) {
    return TabItem(
      id: id,
      title: title,
      icon: const Icon(FluentIcons.code, size: 16),
      content: _buildTerminalContent(title),
      isModified: isModified,
      metadata: {
        'type': TabContentType.terminal.name,
        ...?metadata,
      },
    );
  }

  static TabItem recreateTabFromJson(Map<String, dynamic> json) {
    final String id = json['id'] as String;
    final String title = json['title'] as String;
    final bool isModified = json['isModified'] as bool? ?? false;
    final Map<String, dynamic>? metadata = json['metadata'] as Map<String, dynamic>?;

    final String typeString = metadata?['type'] as String? ?? TabContentType.generic.name;
    
    switch (typeString) {
      case 'document':
        return createDocumentTab(
          id: id,
          title: title,
          isModified: isModified,
          metadata: metadata,
        );
      case 'video':
        return createVideoTab(
          id: id,
          title: title,
          isModified: isModified,
          metadata: metadata,
        );
      case 'audio':
        return createAudioTab(
          id: id,
          title: title,
          isModified: isModified,
          metadata: metadata,
        );
      case 'terminal':
        return createTerminalTab(
          id: id,
          title: title,
          isModified: isModified,
          metadata: metadata,
        );
      default:
        return createGenericTab(
          id: id,
          title: title,
          isModified: isModified,
          metadata: metadata,
        );
    }
  }

  static Widget _buildDocumentContent(String title) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text(
            'This is a document editor. In a real application, this would contain '
            'a rich text editor with formatting options, syntax highlighting, and more.',
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
              ),
              padding: const EdgeInsets.all(12),
              child: const Text(
                'Lorem ipsum dolor sit amet, consectetur adipiscing elit. '
                'Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. '
                'Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris '
                'nisi ut aliquip ex ea commodo consequat.',
                style: TextStyle(fontFamily: 'Courier'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildVideoContent(String title) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      FluentIcons.video,
                      size: 64,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Video Preview',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                    const Text(
                      'This would show video content and timeline controls',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildAudioContent(String title) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    FluentIcons.music_note,
                    size: 64,
                    color: Color.fromARGB(255, 10, 10, 10),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Audio Waveform',
                    style: TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 300,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text('🎵 Audio waveform visualization would go here'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildGenericContent(String title) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text('This is a generic tab content area.'),
        ],
      ),
    );
  }

  static Widget _buildTerminalContent(String title) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF1E1E1E), // Dark terminal background
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                FluentIcons.code,
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTerminalLine('user@flipedit:~\$ flutter run'),
                  _buildTerminalLine('Flutter 3.19.0 • channel stable'),
                  _buildTerminalLine('Running on macOS...'),
                  _buildTerminalLine('✓ Built successfully'),
                  _buildTerminalLine(''),
                  _buildTerminalLine('user@flipedit:~\$ _', isPrompt: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildTerminalLine(String text, {bool isPrompt = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Courier',
          fontSize: 13,
          color: isPrompt ? const Color(0xFF00FF00) : const Color(0xFFE0E0E0),
        ),
      ),
    );
  }
} 