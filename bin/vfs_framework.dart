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
  final cfg = loadConfig('config.yaml');
  final engine = newDefaultEngine();

  // 加载组件
  for (final entry in cfg) {
    final config = ComponentConfig.fromJson(entry);
    await engine.loadComponent<Object>(config);
  }

  // 获取组件依赖图
  final dependencies = engine.getDependencies();
  print('Component Dependencies:');
  dependencies.forEach((key, value) {
    print('$key depends on: ${value.join(', ')}');
  });

  // 运行runnable组件
  await engine.runAllRunnableAndWait();
}
