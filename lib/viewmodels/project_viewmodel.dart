import 'dart:async';

import 'package:flipedit/models/project_asset.dart' as model;
import 'package:flipedit/persistence/database/project_database.dart';
import 'package:flipedit/persistence/database/project_metadata_database.dart';
import 'package:flipedit/services/project_metadata_service.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/services/undo_redo_service.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/viewmodels/timeline_state_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart'; // Added import

import 'commands/import_media_command.dart';
import 'commands/create_project_command.dart';
import 'commands/load_project_command.dart';

const _lastProjectIdKey = 'last_opened_project_id';
const _logTag = 'ProjectViewModel';

class ProjectViewModel {
  final ProjectMetadataService _metadataService = di<ProjectMetadataService>();
  final ProjectDatabaseService _databaseService = di<ProjectDatabaseService>();
  final SharedPreferences _prefs;
  final UndoRedoService _undoRedoService = di<UndoRedoService>();
  final TimelineNavigationViewModel _timelineNavViewModel =
      di<TimelineNavigationViewModel>(); // Added injection

  // Commands
  late final ImportMediaCommand importMediaCommand;
  late final CreateProjectCommand createProjectCommand;
  late final LoadProjectCommand loadProjectCommand;

  late final ValueNotifier<ProjectMetadata?> currentProjectNotifier;
  late final ValueNotifier<bool> isProjectLoadedNotifier;
  late final ValueNotifier<List<Track>> tracksNotifier;
  late final ValueNotifier<List<model.ProjectAsset>> projectAssetsNotifier;

  ProjectViewModel({required SharedPreferences prefs}) : _prefs = prefs {
    currentProjectNotifier = _metadataService.currentProjectMetadataNotifier;
    isProjectLoadedNotifier = ValueNotifier(
      currentProjectNotifier.value != null,
    );

    // Use tracks from the database service
    tracksNotifier = _databaseService.tracksNotifier;

    // Use assets from the database service
    projectAssetsNotifier = _databaseService.assetsNotifier;

    currentProjectNotifier.addListener(_onProjectChanged);

    // Initialize commands
    importMediaCommand = ImportMediaCommand(this, _databaseService);
    createProjectCommand = CreateProjectCommand(_metadataService);
    loadProjectCommand = LoadProjectCommand(
      _metadataService,
      _databaseService,
      _prefs,
      _undoRedoService,
    );
  }

  void _onProjectChanged() {
    final projectLoaded = currentProjectNotifier.value != null;
    // Only update and notify if the value actually changed
    if (isProjectLoadedNotifier.value != projectLoaded) {
      isProjectLoadedNotifier.value = projectLoaded;
    }
  }

  ProjectMetadata? get currentProject => currentProjectNotifier.value;
  bool get isProjectLoaded => isProjectLoadedNotifier.value;
  List<Track> get tracks => tracksNotifier.value;
  List<model.ProjectAsset> get projectAssets => projectAssetsNotifier.value;

  Future<int> createNewProject(String name) async {
    return await createProjectCommand.execute(name: name);
  }

  Future<List<ProjectMetadata>> getAllProjects() async {
    try {
      return await _metadataService.watchAllProjectsMetadata().first;
    } catch (e) {
      debugPrint('Error getting projects: $e');
      return [];
    }
  }

  Future<void> loadProject(int projectId) async {
    await loadProjectCommand.execute(projectId);
    const int initialFrameIndex = 0;
    try {
      _timelineNavViewModel.currentFrame = initialFrameIndex;
      logInfo(
        'Set TimelineNavigationViewModel currentFrame to $initialFrameIndex',
        _logTag,
      );
    } catch (e, stackTrace) {
      logError(
        'Failed to fetch initial frame $initialFrameIndex for project $projectId',
        e,
        stackTrace,
        _logTag,
      );
    }
  }

  Future<void> loadLastOpenedProjectCommand() async {
    final lastProjectId = _prefs.getInt(_lastProjectIdKey);
    if (lastProjectId != null) {
      try {
        // Attempt to load the project using the stored ID
        await loadProject(lastProjectId);
        logInfo(
          "ProjectViewModel",
          "Successfully loaded last project ID: $lastProjectId",
        );
      } catch (e) {
        // Handle cases where the last project might have been deleted or is otherwise inaccessible
        logError(
          "ProjectViewModel",
          "Failed to load last project ID $lastProjectId: $e",
        );
        // Optionally clear the invalid ID
        await _prefs.remove(_lastProjectIdKey);
      }
    } else {
      logInfo(
        "ProjectViewModel",
        "No last project ID found in SharedPreferences.",
      );
    }
  }

  Future<void> addTrackCommand({required String type}) async {
    await _databaseService.addTrack(type: type);
  }

  Future<bool> importMedia(BuildContext context) async {
    return await importMediaCommand.execute(context);
  }

  Future<void> importMediaWithUI(BuildContext context) async {
    final loadingOverlay = _showLoadingOverlay(context, 'Selecting file...');
    try {
      final importSuccess = await importMedia(context);
      loadingOverlay.remove();
      if (importSuccess) {
        _showNotification(
          context,
          'Media imported successfully',
          severity: InfoBarSeverity.success,
        );
      } else {
        _showNotification(
          context,
          'Failed to import media or cancelled',
          severity: InfoBarSeverity.warning,
        );
      }
    } catch (e) {
      loadingOverlay.remove();
      _showNotification(
        context,
        'Error importing media: ${e.toString()}',
        severity: InfoBarSeverity.error,
      );
      logError(_logTag, "Unexpected error in import flow: $e");
    }
  }

  // Method to create a new project with UI dialog
  Future<void> createNewProjectWithDialog(BuildContext context) async {
    final projectNameController = TextEditingController();
    await showDialog<String>(
      context: context,
      builder:
          (context) => ContentDialog(
            title: const Text('New Project'),
            content: SizedBox(
              height: 50,
              child: TextBox(
                controller: projectNameController,
                placeholder: 'Enter project name',
              ),
            ),
            actions: [
              Button(
                child: const Text('Cancel'),
                onPressed: () => Navigator.of(context).pop(),
              ),
              FilledButton(
                child: const Text('Create'),
                onPressed: () {
                  Navigator.of(context).pop(projectNameController.text);
                },
              ),
            ],
          ),
    ).then((projectName) async {
      if (projectName != null && projectName.trim().isNotEmpty) {
        try {
          final newProjectId = await createNewProject(projectName.trim());
          logInfo(_logTag, "Created new project with ID: $newProjectId");
          await loadProject(newProjectId);
          logInfo(_logTag, "Loaded newly created project ID: $newProjectId");
        } catch (e) {
          logError(_logTag, "Error creating or loading project: $e");
          _showNotification(
            context,
            'Error creating project: ${e.toString()}',
            severity: InfoBarSeverity.error,
          );
        }
      } else if (projectName != null) {
        logWarning(_logTag, "Project name cannot be empty.");
        _showNotification(
          context,
          'Project name cannot be empty',
          severity: InfoBarSeverity.warning,
        );
      }
    });
  }

  // Method to open project with UI dialog
  Future<void> openProjectDialog(BuildContext context) async {
    List<ProjectMetadata> projects = [];
    try {
      projects = await getAllProjects();
    } catch (e) {
      logError(_logTag, "Error fetching projects: $e");
      _showNotification(
        context,
        'Error fetching projects: ${e.toString()}',
        severity: InfoBarSeverity.error,
      );
      return;
    }

    if (projects.isEmpty) {
      await showDialog(
        context: context,
        builder:
            (context) => ContentDialog(
              title: const Text('Open Project'),
              content: const Text('No projects found. Create one first?'),
              actions: [
                Button(
                  child: const Text('OK'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
      );
      return;
    }

    await showDialog<int>(
      context: context,
      builder: (context) {
        return ContentDialog(
          title: const Text('Open Project'),
          content: SizedBox(
            height: 300,
            width: 300,
            child: ListView.builder(
              itemCount: projects.length,
              itemBuilder: (context, index) {
                final project = projects[index];
                return ListTile.selectable(
                  title: Text(project.name),
                  subtitle: Text('Created: ${project.createdAt.toLocal()}'),
                  selected: false,
                  onPressed: () {
                    Navigator.of(context).pop(project.id);
                  },
                );
              },
            ),
          ),
          actions: [
            Button(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    ).then((selectedProjectId) {
      if (selectedProjectId != null) {
        logInfo(_logTag, "Attempting to load project ID: $selectedProjectId");
        loadProject(selectedProjectId).catchError((e) {
          logError(_logTag, "Error loading project $selectedProjectId: $e");
          _showNotification(
            context,
            'Error loading project: ${e.toString()}',
            severity: InfoBarSeverity.error,
          );
        });
      }
    });
  }

  OverlayEntry _showLoadingOverlay(BuildContext context, String message) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder:
          (context) => Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:
                    FluentTheme.of(context).resources.subtleFillColorSecondary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ProgressRing(),
                  const SizedBox(height: 16),
                  Text(message),
                ],
              ),
            ),
          ),
    );
    overlay.insert(entry);
    return entry;
  }

  void _showNotification(
    BuildContext context,
    String message, {
    InfoBarSeverity severity = InfoBarSeverity.info,
  }) {
    displayInfoBar(
      context,
      builder: (context, close) {
        return InfoBar(
          title: Text(message),
          severity: severity,
          onClose: close,
        );
      },
    );
  }

  final ValueNotifier<String?> _exportFormatNotifier = ValueNotifier<String?>(
    null,
  );
  final ValueNotifier<String?> _exportResolutionNotifier =
      ValueNotifier<String?>(null);
  final ValueNotifier<String> _exportPathNotifier = ValueNotifier<String>(
    'Select output folder...',
  );

  ValueNotifier<String?> get exportFormatNotifier => _exportFormatNotifier;
  ValueNotifier<String?> get exportResolutionNotifier =>
      _exportResolutionNotifier;
  ValueNotifier<String> get exportPathNotifier => _exportPathNotifier;

  // Search term notifier for media list panel
  final ValueNotifier<String> _searchTermNotifier = ValueNotifier<String>('');
  ValueNotifier<String> get searchTermNotifier => _searchTermNotifier;

  // Method to set search term
  void setSearchTerm(String term) {
    _searchTermNotifier.value = term;
  }

  /// Delete an asset from the project by its database ID
  Future<bool> deleteAssetCommand(int assetId) async {
    try {
      // Get a reference to TimelineStateViewModel for refreshing clips
      TimelineStateViewModel? timelineStateViewModel;
      try {
        timelineStateViewModel = di<TimelineStateViewModel>();
      } catch (e) {
        // TimelineStateViewModel might not be registered yet if we're not in the editor
        logInfo(
          _logTag,
          "TimelineStateViewModel not available, timeline refresh will be skipped",
        );
      }

      // First, get the asset to find its source path
      final assets = projectAssets;
      model.ProjectAsset? asset;

      // Find the asset with the given ID
      for (final a in assets) {
        if (a.databaseId == assetId) {
          asset = a;
          break;
        }
      }

      if (asset == null) {
        logError(_logTag, "Asset with ID $assetId not found");
        return false;
      }

      // Delete all clips that use this asset's source path
      final sourcePath = asset.sourcePath;
      final clipsDeleted = await _databaseService.deleteClipsBySourcePath(
        sourcePath,
      );
      logInfo(
        _logTag,
        "Deleted $clipsDeleted clips using asset with ID $assetId",
      );

      // Now delete the asset itself
      final success = await _databaseService.deleteAsset(assetId);

      // Force the timeline to refresh its clips state
      if (success && clipsDeleted > 0 && timelineStateViewModel != null) {
        // This ensures the timeline UI updates immediately
        await timelineStateViewModel.refreshClips();
        logInfo(_logTag, "Refreshed timeline clips after deleting media");
      }

      return success;
    } catch (e) {
      logError(_logTag, "Error deleting asset: $e");
      return false;
    }
  }

  void setExportFormat(String? format) {
    _exportFormatNotifier.value = format;
  }

  void setExportResolution(String? resolution) {
    _exportResolutionNotifier.value = resolution;
  }

  Future<String?> selectExportPath(BuildContext context) async {
    // Placeholder for selecting export path
    // In a real implementation, this would open a file picker dialog
    return null;
  }

  void exportProject(BuildContext context) {
    // Placeholder for export logic
    if (_exportFormatNotifier.value != null &&
        _exportResolutionNotifier.value != null) {
      _showNotification(
        context,
        'Exporting project...',
        severity: InfoBarSeverity.info,
      );
      // Implement actual export logic here
    } else {
      _showNotification(
        context,
        'Please select format and resolution',
        severity: InfoBarSeverity.warning,
      );
    }
  }

  void dispose() {
    currentProjectNotifier.removeListener(_onProjectChanged);
    isProjectLoadedNotifier.dispose();
    _exportFormatNotifier.dispose();
    _exportResolutionNotifier.dispose();
    _exportPathNotifier.dispose();
    _searchTermNotifier.dispose();
  }
}
