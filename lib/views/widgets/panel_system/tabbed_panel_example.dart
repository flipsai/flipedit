import 'package:flutter/material.dart';
import 'package:flipedit/views/widgets/panel_system/panel_system.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;

/// Example of a panel with tabs, useful for the editor area with multiple open files
class TabbedPanelExample extends StatefulWidget {
  const TabbedPanelExample({super.key});

  @override
  State<TabbedPanelExample> createState() => _TabbedPanelExampleState();
}

class _TabbedPanelExampleState extends State<TabbedPanelExample> {
  int _selectedTabIndex = 0;
  final List<TabItem> _tabs = [];
  
  @override
  void initState() {
    super.initState();
    _initializeTabs();
  }
  
  void _initializeTabs() {
    _tabs.add(
      TabItem(
        title: 'Video 1.mp4',
        icon: Icons.videocam,
        content: _buildTabContent('Video 1.mp4', Colors.blue[100]!),
      ),
    );
    
    _tabs.add(
      TabItem(
        title: 'Audio.mp3',
        icon: Icons.audiotrack,
        content: _buildTabContent('Audio.mp3', Colors.green[100]!),
      ),
    );
    
    _tabs.add(
      TabItem(
        title: 'Image.jpg',
        icon: Icons.image,
        content: _buildTabContent('Image.jpg', Colors.orange[100]!),
      ),
    );
  }
  
  Widget _buildTabContent(String name, Color color) {
    return Container(
      color: color,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              name,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text('Content area for $name'),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _addNewTab,
              child: const Text('Add New Tab'),
            ),
          ],
        ),
      ),
    );
  }
  
  void _addNewTab() {
    final index = _tabs.length + 1;
    setState(() {
      _tabs.add(
        TabItem(
          title: 'New Tab $index',
          icon: Icons.file_present,
          content: _buildTabContent('New Tab $index', Colors.purple[100]!),
        ),
      );
      _selectedTabIndex = _tabs.length - 1;
    });
  }
  
  void _closeTab(TabItem tab) {
    final index = _tabs.indexWhere((t) => t.id == tab.id);
    if (index >= 0) {
      setState(() {
        _tabs.removeAt(index);
        if (_selectedTabIndex >= _tabs.length) {
          _selectedTabIndex = _tabs.isEmpty ? 0 : _tabs.length - 1;
        }
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return PanelTabs(
      tabs: _tabs,
      selectedIndex: _selectedTabIndex,
      onTabSelected: (index) {
        setState(() {
          _selectedTabIndex = index;
        });
      },
      onTabClosed: _closeTab,
    );
  }
}

/// A panel for displaying a tabbed editor with multiple files
class EditorTabbedPanel extends StatefulWidget {
  const EditorTabbedPanel({super.key});

  @override
  State<EditorTabbedPanel> createState() => _EditorTabbedPanelState();
}

class _EditorTabbedPanelState extends State<EditorTabbedPanel> {
  @override
  Widget build(BuildContext context) {
    return const TabbedPanelExample();
  }
}
