# VS Code-Like Panel System for FlipEdit

This package provides a flexible panel system similar to VS Code's layout system with:
- Draggable and resizable panels
- Panels that can be split horizontally or vertically
- Tabbed panels for organizing content
- Drag and drop interface

## Core Components

### PanelGridSystem

The main component that manages the layout of panels:

```dart
PanelGridSystem(
  initialPanels: panels,
  backgroundColor: const Color(0xFFF3F3F3),
  resizeHandleColor: Colors.grey[300],
)
```

### PanelDefinition

Defines a panel's content and metadata:

```dart
PanelDefinition(
  title: 'Inspector',
  icon: FluentIcons.edit_mirrored,
  content: const InspectorPanel(),
)
```

### PanelTabs

A component for tabbed interfaces within a panel:

```dart
PanelTabs(
  tabs: _tabs,
  selectedIndex: _selectedTabIndex,
  onTabSelected: (index) {
    setState(() {
      _selectedTabIndex = index;
    });
  },
  onTabClosed: _closeTab,
)
```

## Usage

### Basic Setup

1. Define your panels in the `EditorViewModel`:

```dart
void initializePanelLayout() {
  _createPreviewPanel();
  _createTimelinePanel();
  _createInspectorPanel();
  
  _panelLayout = PanelLayoutModel.fromInitialPanels(_panels);
}
```

2. Use the `PanelGridSystem` in your layout:

```dart
Expanded(
  child: PanelGridSystem(
    initialPanels: editorViewModel.getPanelDefinitions(),
    backgroundColor: const Color(0xFFF3F3F3),
  ),
)
```

### Adding Tabs to a Panel

To add tabs to a panel, use the `PanelTabs` component as the content of your panel:

```dart
PanelDefinition(
  title: 'Editor',
  icon: FluentIcons.edit,
  content: EditorTabbedPanel(),
)
```

### Handling Panel Actions

The panel system provides callbacks for various actions:

- `onResize`: Called when a panel is resized
- `onTabSelected`: Called when a tab is selected
- `onTabClosed`: Called when a tab is closed
- `onTabDragged`: Called when a tab is dragged to a new position

## VS Code Comparison

This implementation is inspired by VS Code's layout system:

- **Grid Layout**: Similar to VS Code's `Grid` class
- **Sash**: Our `ResizeHandle` is similar to VS Code's sash
- **Part**: Like VS Code's `Part` component
- **EditorTabbedPanel**: Similar to VS Code's editor area with multiple tabs

## Extending the System

To add more functionality:

1. Enhance the `PanelLayoutModel` to support more complex layouts
2. Add support for splitting panels at runtime
3. Implement panel state persistence
4. Add keyboard shortcuts for panel operations

## Example

See `tabbed_panel_example.dart` for a complete example of a panel with tabs.
