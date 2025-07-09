import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:watch_it/watch_it.dart';

import '../models/tab_item.dart';
import '../viewmodels/tab_system_viewmodel.dart';
import '../services/tab_content_factory.dart';
import 'widgets/tab_system_widget.dart';

class DemoTabSystemView extends StatefulWidget {
  const DemoTabSystemView({super.key});

  @override
  State<DemoTabSystemView> createState() => _DemoTabSystemViewState();
}

class _DemoTabSystemViewState extends State<DemoTabSystemView> {
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeTabSystem();
  }

  Future<void> _initializeTabSystem() async {
    final tabSystem = di<TabSystemViewModel>();
    await tabSystem.initialize();
    
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final tabSystem = di<TabSystemViewModel>();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tab System Demo'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.eraser),
            tooltip: 'Clear State',
            onPressed: () => _clearPersistedState(context, tabSystem),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildControls(context, tabSystem),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).dividerColor,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const TabSystemWidget(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context, TabSystemViewModel tabSystem) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tab System Controls',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            
            // Tab creation controls
            Text(
              'Create Tabs:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ElevatedButton(
                  onPressed: () => _addSampleTab(tabSystem, 'Document'),
                  child: const Text('Document'),
                ),
                ElevatedButton(
                  onPressed: () => _addSampleTab(tabSystem, 'Video'),
                  child: const Text('Video'),
                ),
                ElevatedButton(
                  onPressed: () => _addSampleTab(tabSystem, 'Audio'),
                  child: const Text('Audio'),
                ),
                ElevatedButton(
                  onPressed: () => _addTerminalTab(tabSystem),
                  child: const Text('Terminal'),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Layout controls
            Text(
              'Layout:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ElevatedButton(
                  onPressed: () => tabSystem.createTabGroup(),
                  child: const Text('Add Group'),
                ),
                ElevatedButton(
                  onPressed: () => tabSystem.createTerminalGroup(),
                  child: const Text('Add Terminal Area'),
                ),
                _buildLayoutToggle(context, tabSystem),
                ElevatedButton(
                  onPressed: () => tabSystem.closeAllTabs(),
                  child: const Text('Close All'),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            _buildTabInfo(context, tabSystem),
          ],
        ),
      ),
    );
  }

  Widget _buildLayoutToggle(BuildContext context, TabSystemViewModel tabSystem) {
    return ListenableBuilder(
      listenable: tabSystem.layoutOrientationNotifier,
      builder: (context, child) {
        final isVertical = tabSystem.layoutOrientation == TabSystemLayout.vertical;
        
        return ShadSwitch(
          value: isVertical,
          onChanged: (_) => tabSystem.toggleLayoutOrientation(),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isVertical ? Icons.more_vert : Icons.minimize,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(isVertical ? 'Vertical' : 'Horizontal'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabInfo(BuildContext context, TabSystemViewModel tabSystem) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        tabSystem.tabLinesNotifier,
        tabSystem.activeGroupIdNotifier,
        tabSystem.layoutOrientationNotifier,
      ]),
      builder: (context, child) {
        final tabGroups = tabSystem.tabGroups;
        final activeGroupId = tabSystem.activeGroupId;
        final layoutOrientation = tabSystem.layoutOrientation;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              'Status:',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Groups: ${tabGroups.length}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'Total tabs: ${tabGroups.fold(0, (sum, group) => sum + group.tabCount)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'Layout: ${layoutOrientation.name}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'Active group: ${activeGroupId ?? 'None'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (tabSystem.activeTab != null)
              Text(
                'Active tab: ${tabSystem.activeTab!.title}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            Text(
              'Persistence: ${tabSystem.isInitialized ? 'Enabled' : 'Loading...'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }

  void _addSampleTab(TabSystemViewModel tabSystem, String type) {
    final String id = '${type.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}';
    final String title = '$type ${DateTime.now().millisecond}';

    TabItem tab;
    switch (type) {
      case 'Document':
        tab = TabContentFactory.createDocumentTab(
          id: id,
          title: title,
          isModified: true,
        );
        break;
      case 'Video':
        tab = TabContentFactory.createVideoTab(
          id: id,
          title: title,
        );
        break;
      case 'Audio':
        tab = TabContentFactory.createAudioTab(
          id: id,
          title: title,
        );
        break;
      default:
        tab = TabContentFactory.createGenericTab(
          id: id,
          title: title,
        );
    }

    tabSystem.addTab(tab);
  }

  void _addTerminalTab(TabSystemViewModel tabSystem) {
    final String id = 'terminal_${DateTime.now().millisecondsSinceEpoch}';
    final String title = 'Terminal ${DateTime.now().millisecond}';

    final tab = TabContentFactory.createTerminalTab(
      id: id,
      title: title,
    );

    // Try to add to terminal group first, otherwise active group
    final terminalGroup = tabSystem.tabGroups.firstWhere(
      (group) => group.id == 'terminal_group',
      orElse: () => tabSystem.activeGroup!,
    );
    
    tabSystem.addTab(tab, targetGroupId: terminalGroup.id);
  }

  Future<void> _clearPersistedState(BuildContext context, TabSystemViewModel tabSystem) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Persisted State'),
        content: const Text(
          'This will clear all saved tab layouts and restart with a clean state. '
          'Current tabs will be lost. Are you sure?'
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          ElevatedButton(
            child: const Text('Clear'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (result == true) {
      await tabSystem.clearPersistedState();
      tabSystem.closeAllTabs();
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('All persisted tab data has been cleared.'),
            action: SnackBarAction(
              label: 'OK',
              onPressed: () {},
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }
} 