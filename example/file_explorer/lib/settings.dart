import 'package:flutter/material.dart';
import 'package:vfs_framework/vfs_framework.dart' hide BuildContext;

class SettingPage extends StatefulWidget {
  const SettingPage({super.key, required this.initialConfigList});
  final List<ComponentConfig> initialConfigList;

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(child: Text('Settings Page')),
    );
  }
}
