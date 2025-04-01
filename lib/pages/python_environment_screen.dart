import 'package:flutter/material.dart';
import '../services/uv_manager.dart'; // Make sure to import your UvManager class
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

class PythonEnvironmentScreen extends StatefulWidget {
  @override
  _PythonEnvironmentScreenState createState() => _PythonEnvironmentScreenState();
}

class _PythonEnvironmentScreenState extends State<PythonEnvironmentScreen> {
  final UvManager _uvManager = UvManager();
  bool _isInitialized = false;
  String _statusMessage = "Initializing...";
  String _appDataDir = '';
  List<String> _installedPackages = [];
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  List<String> _availableVenvs = [];
  String? _selectedVenv;
  final _newVenvController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _initializeUv();
  }
  
  Future<void> _initializeUv() async {
    try {
      setState(() {
        _isDownloading = true;
        _statusMessage = "Downloading UV...";
      });
      
      await _uvManager.initialize();
      final appDir = await getApplicationSupportDirectory();
      
      setState(() {
        _isDownloading = false;
        _isInitialized = true;
        _statusMessage = "UV initialized successfully";
        _appDataDir = appDir.path;
      });
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _statusMessage = "Failed to initialize UV: $e";
      });
    }
  }
  
  Future<void> _refreshVenvs() async {
    if (!_isInitialized) return;
    final venvs = await _uvManager.listVenvs();
    setState(() {
      _availableVenvs = venvs;
      if (!venvs.contains(_selectedVenv)) {
        _selectedVenv = null;
      }
    });
  }
  
  Future<void> _createEnvironment() async {
    if (!_isInitialized || _newVenvController.text.isEmpty) return;
    
    setState(() {
      _statusMessage = "Creating virtual environment...";
    });
    
    try {
      final venvName = _newVenvController.text;
      final result = await _uvManager.createVenv(venvName);
      await _refreshVenvs();
      setState(() {
        _selectedVenv = venvName;
        _statusMessage = "Environment created: ${result.stdout}";
        _newVenvController.clear();
      });
    } catch (e) {
      setState(() {
        _statusMessage = "Failed to create environment: $e";
      });
    }
  }
  
  Future<void> _installPackage(String packageName) async {
    if (!_isInitialized || _selectedVenv == null) return;
    
    setState(() {
      _statusMessage = "Installing $packageName in $_selectedVenv...";
    });
    
    try {
      final result = await _uvManager.installPackage(packageName, _selectedVenv!);
      print("Installation stdout: ${result.stdout}");
      print("Installation stderr: ${result.stderr}");
      
      // Refresh installed packages list
      await _listPackages();
      
      setState(() {
        _statusMessage = "Successfully installed $packageName in $_selectedVenv";
      });
    } catch (e) {
      setState(() {
        _statusMessage = "Failed to install package: $e";
      });
      print("Failed to install package: $e");
    }
  }
  
  Future<void> _listPackages() async {
    if (!_isInitialized || _selectedVenv == null) return;
    
    try {
      // Check if environment exists first
      if (!await _uvManager.doesEnvExist(_selectedVenv!)) {
        setState(() {
          _statusMessage = "Virtual environment not found. Please create it first.";
        });
        return;
      }
      
      // Create a simple Python script to list packages using pip instead of pkg_resources
      const listPackagesScript = """
import json
import subprocess
result = subprocess.run(['pip', 'list', '--format=json'], capture_output=True, text=True)
print(result.stdout)
      """;
      
      // Save it to a temporary file
      final tempDir = await getTemporaryDirectory();
      final scriptPath = '${tempDir.path}/list_packages.py';
      await File(scriptPath).writeAsString(listPackagesScript);
      
      // Run it within the selected virtual environment
      final result = await _uvManager.runPythonScript(_selectedVenv!, scriptPath, []);
      
      if (result.exitCode != 0) {
        throw Exception("Failed to list packages: ${result.stderr}");
      }

      // Parse the JSON output from pip list
      final List<dynamic> packages = json.decode(result.stdout);
      setState(() {
        _installedPackages = packages
            .map((pkg) => "${pkg['name']}==${pkg['version']}")
            .toList();
        _statusMessage = "Successfully listed packages for $_selectedVenv";
      });
    } catch (e) {
      setState(() {
        _statusMessage = "Failed to list packages: $e";
        _installedPackages = [];
      });
      print("Failed to list packages: $e");
    }
  }
  
  @override
  Widget build(BuildContext context) {
    // Calculate the Python path based on selected environment
    String pythonPath = _selectedVenv != null 
        ? (Platform.isWindows 
            ? '${_appDataDir}/venvs/$_selectedVenv/Scripts/python.exe'
            : '${_appDataDir}/venvs/$_selectedVenv/bin/python')
        : 'No environment selected';

    return Scaffold(
      appBar: AppBar(
        title: Text('FlipEdit'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_statusMessage, style: TextStyle(fontWeight: FontWeight.bold)),
            if (_isDownloading) ...[
              SizedBox(height: 10),
              LinearProgressIndicator(value: _downloadProgress),
            ],
            SizedBox(height: 10),
            Text('Python Path:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(pythonPath, style: TextStyle(fontFamily: 'monospace')),
            SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newVenvController,
                    decoration: InputDecoration(
                      hintText: 'New environment name',
                    ),
                  ),
                ),
                SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isInitialized ? _createEnvironment : null,
                  child: Text('Create Environment'),
                ),
              ],
            ),
            SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedVenv,
                    hint: Text('Select Virtual Environment'),
                    isExpanded: true,
                    items: _availableVenvs.map((String venv) {
                      return DropdownMenuItem<String>(
                        value: venv,
                        child: Text(venv),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedVenv = newValue;
                        _listPackages();
                      });
                    },
                  ),
                ),
                SizedBox(width: 10),
                IconButton(
                  icon: Icon(Icons.refresh),
                  onPressed: _isInitialized ? _refreshVenvs : null,
                ),
              ],
            ),
            SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Package name (e.g., numpy)',
                    ),
                    onSubmitted: (value) {
                      if (value.isNotEmpty && _selectedVenv != null) {
                        _installPackage(value);
                      }
                    },
                    enabled: _selectedVenv != null,
                  ),
                ),
                SizedBox(width: 10),
                ElevatedButton(
                  onPressed: (_isInitialized && _selectedVenv != null) 
                    ? () => _listPackages() 
                    : null,
                  child: Text('Refresh List'),
                ),
              ],
            ),
            SizedBox(height: 20),
            Text('Installed Packages:', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView.builder(
                itemCount: _installedPackages.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(_installedPackages[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}