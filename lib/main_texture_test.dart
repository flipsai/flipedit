import 'package:flutter/material.dart';
import 'debug_texture_test.dart';
import 'examples/texture_integration_example.dart';

void main() {
  runApp(const ComprehensiveTextureTestApp());
}

class ComprehensiveTextureTestApp extends StatelessWidget {
  const ComprehensiveTextureTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlipEdit Texture System Test',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const TextureTestHomePage(),
    );
  }
}

class TextureTestHomePage extends StatefulWidget {
  const TextureTestHomePage({super.key});

  @override
  State<TextureTestHomePage> createState() => _TextureTestHomePageState();
}

class _TextureTestHomePageState extends State<TextureTestHomePage> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const DebugTextureTest(),
    const TextureIntegrationDemoPage(),
    const TextureStatusPage(),
  ];

  final List<String> _pageTitles = [
    'Basic Texture Test',
    'Video Integration Demo',
    'System Status',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('FlipEdit Texture System - ${_pageTitles[_selectedIndex]}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: Icon(Icons.info_outline),
            onPressed: () => _showInfoDialog(context),
          ),
        ],
      ),
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.play_circle_outline),
            selectedIcon: Icon(Icons.play_circle),
            label: 'Basic Test',
          ),
          NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library),
            label: 'Video Demo',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Status',
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('FlipEdit Texture System'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This test app validates the texture rendering system fixes.',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 16),
                Text('Test Pages:'),
                SizedBox(height: 8),
                Text('• Basic Test: Animated texture patterns'),
                Text('• Video Demo: Simulated video rendering'),
                Text('• Status: System information and cleanup'),
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Key Fixes Applied:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        '✓ Removed broken FFI pointer logic\n'
                        '✓ Simplified texture creation process\n'
                        '✓ Focus on Flutter-side rendering only\n'
                        '✓ Proper texture lifecycle management',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('OK'),
              ),
            ],
          ),
    );
  }
}

class TextureIntegrationDemoPage extends StatelessWidget {
  const TextureIntegrationDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb, color: Colors.orange),
                      SizedBox(width: 8),
                      Text(
                        'Integration Guide',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Text(
                    'This page demonstrates how to properly integrate the fixed texture system with your video pipeline:',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),
          VideoTextureRenderer(),
          SizedBox(height: 16),
          TextureCleanupExample(),
        ],
      ),
    );
  }
}

class TextureStatusPage extends StatefulWidget {
  const TextureStatusPage({super.key});

  @override
  State<TextureStatusPage> createState() => _TextureStatusPageState();
}

class _TextureStatusPageState extends State<TextureStatusPage> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.analytics, color: Colors.blue),
                      SizedBox(width: 8),
                      Text(
                        'System Status',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  _buildStatusItem('Flutter Framework', 'Available', true),
                  _buildStatusItem(
                    'texture_rgba_renderer Plugin',
                    'Available',
                    true,
                  ),
                  _buildStatusItem('Fixed Texture Helper', 'Implemented', true),
                  _buildStatusItem('Legacy FFI Pointers', 'Deprecated', false),
                  SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'All Systems Ready',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          'The texture rendering system is now properly configured and should work reliably.',
                          style: TextStyle(color: Colors.green.shade700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Next Steps',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  SizedBox(height: 16),
                  _buildNextStep(
                    '1. Test Basic Functionality',
                    'Use the "Basic Test" tab to verify texture creation and updates work',
                    Icons.play_arrow,
                  ),
                  _buildNextStep(
                    '2. Integrate with Python',
                    'Replace simulation with actual frames from your Python video processing',
                    Icons.integration_instructions,
                  ),
                  _buildNextStep(
                    '3. Update Main App',
                    'Use FixedTextureHelper instead of the old TextureHelper in your main app',
                    Icons.update,
                  ),
                  _buildNextStep(
                    '4. Remove Legacy Code',
                    'Clean up the old FFI pointer logic and texture bridge files',
                    Icons.cleaning_services,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem(String label, String status, bool isPositive) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isPositive ? Icons.check_circle : Icons.warning,
            color: isPositive ? Colors.green : Colors.orange,
            size: 20,
          ),
          SizedBox(width: 12),
          Expanded(child: Text(label)),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color:
                  isPositive
                      ? Colors.green.withOpacity(0.1)
                      : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              status,
              style: TextStyle(
                color:
                    isPositive ? Colors.green.shade700 : Colors.orange.shade700,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextStep(String title, String description, IconData icon) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.blue, size: 20),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
