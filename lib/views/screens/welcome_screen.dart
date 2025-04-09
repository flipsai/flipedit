import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/di/service_locator.dart';
import 'package:flipedit/viewmodels/app_viewmodel.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/views/screens/editor_screen.dart';
import 'package:watch_it/watch_it.dart';

class WelcomeScreen extends StatelessWidget with WatchItMixin {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Use watch_it's data binding to observe multiple properties
    final isInitialized = watchValue((AppViewModel vm) => vm.isInitializedNotifier);
    final isDownloading = watchValue((AppViewModel vm) => vm.isDownloadingNotifier);
    final statusMessage = watchValue((AppViewModel vm) => vm.statusMessageNotifier);
    final progress = watchValue((AppViewModel vm) => vm.downloadProgressNotifier);
    
    return ScaffoldPage(
      header: const PageHeader(
        title: Text('Welcome to FlipEdit'),
      ),
      content: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              isDownloading
                  ? const _InitializingView()
                  : isInitialized
                      ? _WelcomeView()
                      : _ErrorView(errorMessage: statusMessage),
              if (isDownloading) ...[
                const SizedBox(height: 16),
                Text(statusMessage, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ProgressBar(value: progress * 100),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InitializingView extends StatelessWidget {
  const _InitializingView();

  @override
  Widget build(BuildContext context) {
    return const InfoBar(
      title: Text('Setting up environment'),
      content: Text('Please wait while we set up the required components...'),
      severity: InfoBarSeverity.info,
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String errorMessage;

  const _ErrorView({required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    return InfoBar(
      title: const Text('Setup Error'),
      content: Text(errorMessage),
      severity: InfoBarSeverity.error,
    );
  }
}

class _WelcomeView extends StatelessWidget with WatchItMixin {
  _WelcomeView();

  @override
  Widget build(BuildContext context) {
    // Use watch_it's data binding to observe the recentProjects property
    final recentProjects = watchValue((ProjectViewModel vm) => vm.recentProjectsNotifier);
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Get Started',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Button(
              child: const Text('New Project'),
              onPressed: () {
                _createNewProject(context);
              },
            ),
            const SizedBox(height: 8),
            Button(
              child: const Text('Open Project'),
              onPressed: () {
                _openProject(context);
              },
            ),
            if (recentProjects.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'Recent Projects',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...recentProjects.map((project) => _RecentProjectItem(project: project)),
            ],
          ],
        ),
      ),
    );
  }

  void _createNewProject(BuildContext context) {
    // Use di directly for actions without storing in a local variable
    di<ProjectViewModel>().createNewProject('New Project', '/path/to/project');
    
    // Navigate to the editor
    Navigator.of(context).pushReplacement(
      FluentPageRoute(builder: (context) => const EditorScreen()),
    );
  }

  void _openProject(BuildContext context) {
    // In a real app, this would show a file picker
    // For now, we'll just create a dummy project
    di<ProjectViewModel>().createNewProject('Opened Project', '/path/to/opened/project');
    
    // Navigate to the editor
    Navigator.of(context).pushReplacement(
      FluentPageRoute(builder: (context) => const EditorScreen()),
    );
  }
}

class _RecentProjectItem extends StatelessWidget {
  final dynamic project;
  
  const _RecentProjectItem({required this.project});
  
  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(project.name),
      subtitle: Text(project.path),
      onPressed: () {
        di<ProjectViewModel>().openProject(project);
        
        Navigator.of(context).pushReplacement(
          FluentPageRoute(builder: (context) => const EditorScreen()),
        );
      },
    );
  }
}
