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
  bool _initialRefreshDone = false;
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
      
      await _refreshVenvs();
      setState(() {
        _initialRefreshDone = true;
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
    
    setState(() {
      _statusMessage = "Refreshing environments...";
    });
    
    try {
      final venvs = await _uvManager.listVenvs();
      
      setState(() {
        _availableVenvs = venvs;
        if (!venvs.contains(_selectedVenv)) {
          _selectedVenv = null;
        }
        _statusMessage = "Found ${venvs.length} environments";
      });
      
      if (venvs.isEmpty) {
        print("Warning: No environments found during refresh");
        setState(() {
          _statusMessage = "No environments found. Try creating one.";
        });
      }
    } catch (e) {
      print("Error refreshing environments: $e");
      setState(() {
        _statusMessage = "Error refreshing environments: $e";
      });
    }
  }
  
  Future<void> _createEnvironment() async {
    if (!_isInitialized || _newVenvController.text.isEmpty) return;
    
    final venvName = _newVenvController.text;
    print("Creating new environment: $venvName");
    
    setState(() {
      _statusMessage = "Creating virtual environment '$venvName'...";
    });
    
    try {
      await _uvManager.createVenv(venvName);
      print("Environment created, now refreshing venv list");
      
      await Future.delayed(const Duration(seconds: 1));
      final venvs = await _uvManager.listVenvs();
      
      setState(() {
        _availableVenvs = venvs;
        
        if (venvs.contains(venvName)) {
          _selectedVenv = venvName;
          _statusMessage = "Environment '$venvName' created and selected";
        } else {
          _statusMessage = "Environment created but not found in list. Try refreshing manually.";
        }
        _newVenvController.clear();
      });
      
      if (_selectedVenv == venvName) {
        await _listPackages();
      }
    } catch (e) {
      print("Error creating environment: $e");
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
    
    setState(() {
      _statusMessage = "Listing packages for $_selectedVenv...";
    });
    
    try {
      if (!await _uvManager.doesEnvExist(_selectedVenv!)) {
        setState(() {
          _statusMessage = "Virtual environment not found. Please create it first.";
        });
        return;
      }
      
      const listPackagesScript = """
import json
import subprocess
result = subprocess.run(['pip', 'list', '--format=json'], capture_output=True, text=True)
print(result.stdout)
      """;
      
      final tempDir = await getTemporaryDirectory();
      final scriptPath = '${tempDir.path}/list_packages.py';
      await File(scriptPath).writeAsString(listPackagesScript);
      
      final result = await _uvManager.runPythonScript(_selectedVenv!, scriptPath, []);
      
      if (result.exitCode != 0) {
        throw Exception("Failed to list packages: ${result.stderr}");
      }

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
    String pythonPath = _selectedVenv != null 
        ? (Platform.isWindows 
            ? '${_appDataDir}\\venvs\\$_selectedVenv\\Scripts\\python.exe'
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
            
            // Add a test button for UV installation
            ElevatedButton(
              onPressed: _isInitialized ? _testUvInstallation : null,
              child: Text('Test UV Installation'),
            ),
            SizedBox(height: 20),
            
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newVenvController,
                    decoration: InputDecoration(
                      hintText: 'New environment name',
                    ),
                    enabled: _isInitialized,
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

  // Add a new method to test UV installation
  Future<void> _testUvInstallation() async {
    if (!_isInitialized) return;
    
    setState(() {
      _statusMessage = "Testing UV installation...";
    });
    
    try {
      // Get the UV path from the UvManager
      final uvPath = _uvManager.uvPath;
      
      // Test if the UV file exists
      final uvFile = File(uvPath);
      final exists = await uvFile.exists();
      
      print('UV path: $uvPath');
      print('UV file exists: $exists');
      
      if (!exists) {
        setState(() {
          _statusMessage = "UV executable not found at: $uvPath";
        });
        return;
      }
      
      // Try running the UV version command
      try {
        final result = await Process.run(uvPath, ['--version'], runInShell: true);
        print('UV version stdout: ${result.stdout}');
        print('UV version stderr: ${result.stderr}');
        
        if (result.exitCode == 0) {
          setState(() {
            _statusMessage = "UV is working: ${result.stdout}";
          });
        } else {
          setState(() {
            _statusMessage = "UV command failed: ${result.stderr}";
          });
        }
      } catch (e) {
        print('Error running UV command: $e');
        setState(() {
          _statusMessage = "Error running UV command: $e";
        });
      }
    } catch (e) {
      print('Error testing UV installation: $e');
      setState(() {
        _statusMessage = "Error testing UV installation: $e";
      });
    }
  }
}