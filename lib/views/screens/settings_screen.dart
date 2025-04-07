import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/comfyui/comfyui_service.dart';
import 'package:flipedit/di/service_locator.dart';
import 'package:flipedit/services/uv_manager.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final UvManager _uvManager = di<UvManager>();
  final ComfyUIService _comfyUIService = di<ComfyUIService>();
  
  List<String> _availableVenvs = [];
  String? _selectedVenv;
  final _comfyPathController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _initializeSettings();
  }
  
  Future<void> _initializeSettings() async {
    await _refreshVenvs();
    
    // Set initial values
    _comfyPathController.text = _comfyUIService.comfyUIPath ?? '';
    
    if (_comfyUIService.selectedPythonEnv.isNotEmpty) {
      setState(() {
        _selectedVenv = _comfyUIService.selectedPythonEnv;
      });
    }
  }
  
  Future<void> _refreshVenvs() async {
    try {
      final venvs = await _uvManager.listVenvs();
      
      setState(() {
        _availableVenvs = venvs;
        if (_selectedVenv != null && !venvs.contains(_selectedVenv)) {
          _selectedVenv = null;
        }
      });
    } catch (e) {
      print("Error refreshing environments: $e");
    }
  }
  
  Future<void> _selectComfyUIPath() async {
    // In a real app, this would show a folder picker
    // For now, we'll just use a default path
    final appDir = await getApplicationSupportDirectory();
    final comfyPath = '${appDir.path}/comfyui';
    
    setState(() {
      _comfyPathController.text = comfyPath;
    });
    
    _comfyUIService.setComfyUIPath(comfyPath);
  }
  
  Future<void> _installComfyUI() async {
    if (_selectedVenv == null || _selectedVenv!.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => ContentDialog(
          title: const Text('Error'),
          content: const Text('Please select a Python environment first.'),
          actions: [
            Button(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    
    if (_comfyPathController.text.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => ContentDialog(
          title: const Text('Error'),
          content: const Text('Please select a ComfyUI installation path.'),
          actions: [
            Button(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Installing ComfyUI'),
        content: const Text('This may take several minutes. Please wait...'),
        actions: [],
      ),
    );
    
    final result = await _comfyUIService.installComfyUI(_comfyPathController.text);
    
    if (!mounted) return;
    Navigator.of(context).pop(); // Close progress dialog
    
    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(result ? 'Success' : 'Error'),
        content: Text(result 
            ? 'ComfyUI installed successfully.' 
            : 'Failed to install ComfyUI: ${_comfyUIService.status}'),
        actions: [
          Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final comfyStatus = _comfyUIService.status;
    final isComfyRunning = _comfyUIService.isRunning;
    
    return ScaffoldPage(
      header: const PageHeader(
        title: Text('Settings'),
      ),
      content: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ComfyUI Integration',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),
                      
                      // Python Environment selection
                      InfoLabel(
                        label: 'Python Environment',
                        child: Row(
                          children: [
                            Expanded(
                              child: ComboBox<String>(
                                value: _selectedVenv,
                                placeholder: const Text('Select Python Environment'),
                                items: _availableVenvs.map((String venv) {
                                  return ComboBoxItem<String>(
                                    value: venv,
                                    child: Text(venv),
                                  );
                                }).toList(),
                                onChanged: (String? newValue) {
                                  setState(() {
                                    _selectedVenv = newValue;
                                  });
                                  
                                  if (newValue != null) {
                                    _comfyUIService.setPythonEnvironment(newValue);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              icon: const Icon(FluentIcons.refresh),
                              onPressed: _refreshVenvs,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      // ComfyUI path
                      InfoLabel(
                        label: 'ComfyUI Path',
                        child: Row(
                          children: [
                            Expanded(
                              child: TextBox(
                                controller: _comfyPathController,
                                placeholder: 'Select ComfyUI path',
                                readOnly: true,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Button(
                              onPressed: _selectComfyUIPath,
                              child: const Text('Browse'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      // Install/Start/Stop buttons
                      Row(
                        children: [
                          Button(
                            onPressed: _installComfyUI,
                            child: const Text('Install ComfyUI'),
                          ),
                          const SizedBox(width: 10),
                          Button(
                            onPressed: isComfyRunning 
                                ? () => _comfyUIService.stopComfyUI() 
                                : () => _comfyUIService.startComfyUI(),
                            child: Text(isComfyRunning ? 'Stop ComfyUI' : 'Start ComfyUI'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      
                      // Status
                      InfoBar(
                        title: const Text('Status'),
                        content: Text(comfyStatus),
                        severity: isComfyRunning 
                            ? InfoBarSeverity.success 
                            : InfoBarSeverity.info,
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Application Settings',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),
                      
                      // Theme toggle
                      ToggleSwitch(
                        checked: FluentTheme.of(context).brightness == Brightness.dark,
                        content: const Text('Dark Theme'),
                        onChanged: (value) {
                          // In a real app, this would update the app theme
                        },
                      ),
                      
                      const SizedBox(height: 10),
                      
                      // Auto-save toggle
                      ToggleSwitch(
                        checked: true,
                        content: const Text('Auto-save Projects'),
                        onChanged: (value) {
                          // In a real app, this would update auto-save settings
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
