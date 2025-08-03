import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vfs_framework/src/blueprint/index.dart';
import 'package:yaml/yaml.dart';

List<Map<String, dynamic>> loadConfig(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw FileSystemException('Configuration file not found: $path');
  }
  final content = file.readAsStringSync();
  // json或yaml
  if (path.endsWith('.json')) {
    return List<Map<String, dynamic>>.from(jsonDecode(content) as List);
  } else if (path.endsWith('.yaml') || path.endsWith('.yml')) {
    // 转换成json格式
    final yamlDoc = loadYaml(content);
    final jsonDoc = json.encode(yamlDoc);
    return List<Map<String, dynamic>>.from(jsonDecode(jsonDoc) as List);
  } else {
    throw UnsupportedError('Unsupported configuration file format: $path');
  }
}

Future<void> main(List<String> arguments) async {
  // 检查配置文件
  const configFile = 'config.yaml';
  if (!File(configFile).existsSync()) {
    print('❌ 配置文件不存在: $configFile');
    print('请创建配置文件或使用 -c 参数指定配置文件路径');
    return;
  }

  final cfg = loadConfig(configFile);
  print('✅ 加载配置文件: $configFile (${cfg.length} 个组件)');

  final engine = newDefaultEngine();

  // 加载组件
  for (final entry in cfg) {
    final config = ComponentConfig.fromJson(entry);
    await engine.loadComponent<Object>(config);
  }

  // 运行runnable组件
  print('🚀 启动所有可运行组件...');
  await ProcessSignal.sigint.watch().firstWhere((signal) {
    final shouldExit = [
      ProcessSignal.sigint,
      ProcessSignal.sigterm,
      ProcessSignal.sigabrt,
      ProcessSignal.sigsegv,
    ].contains(signal);
    if (shouldExit) {
      print('\n收到终止信号...');
    }
    return shouldExit;
  });

  print('🛑 停止所有组件...');
  await engine.close();
  print('✅ 所有组件已停止');
  exit(0);
}
