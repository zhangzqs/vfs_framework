import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pumli/pumli.dart';
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

/// 生成PlantUML组件图
String generatePlantUMLDiagram(
  List<Map<String, dynamic>> configs,
  Map<String, Set<String>> dependencies,
) {
  final buffer = StringBuffer();

  // 开始UML图，明确指定为组件图
  buffer.writeln('@startuml');
  buffer.writeln('!define COMPONENT_DIAGRAM');
  buffer.writeln('!theme plain');
  buffer.writeln('');
  buffer.writeln('skinparam backgroundColor White');
  buffer.writeln('skinparam componentBackgroundColor LightBlue');
  buffer.writeln('skinparam componentBorderColor DarkBlue');
  buffer.writeln('skinparam componentFontSize 12');
  buffer.writeln('skinparam componentStyle uml2');
  buffer.writeln('');

  // 添加组件节点和详细信息
  for (final config in configs) {
    final name = config['name'] as String;
    final type = config['type'] as String;
    final componentConfig = config['config'] as Map<String, dynamic>? ?? {};
    final sanitizedId = _sanitizeId(name);

    // 使用标准的component语法
    buffer.writeln('component [$name] as $sanitizedId');

    // 添加note来显示详细信息
    buffer.writeln('note top of $sanitizedId');
    buffer.writeln('  **Type**: $type');

    // 添加关键配置信息
    final configStr = _formatConfigForDisplay(componentConfig);
    if (configStr.isNotEmpty) {
      buffer.writeln('  --');
      buffer.writeln('  **Config**:');
      final configLines = configStr
          .split('\n')
          .where((line) => line.trim().isNotEmpty);
      for (final line in configLines.take(4)) {
        // 显示前4行配置
        buffer.writeln('  • ${line.trim()}');
      }
      if (configLines.length > 4) {
        buffer.writeln('  • ... and ${configLines.length - 4} more');
      }
    }
    buffer.writeln('end note');
    buffer.writeln('');
  }

  // 添加依赖关系箭头
  buffer.writeln('\' Dependencies');
  dependencies.forEach((dependent, deps) {
    for (final dependency in deps) {
      buffer.writeln(
        '${_sanitizeId(dependency)} --> ${_sanitizeId(dependent)} : uses',
      );
    }
  });

  // 结束UML图
  buffer.writeln('');
  buffer.writeln('@enduml');

  return buffer.toString();
}

/// 格式化配置信息用于显示
String _formatConfigForDisplay(Map<String, dynamic> config) {
  if (config.isEmpty) return '';

  final buffer = StringBuffer();
  var count = 0;
  const maxItems = 5; // 最多显示5个配置项

  config.forEach((key, value) {
    if (count >= maxItems) return;

    String valueStr;
    if (value is String) {
      valueStr = value.length > 30 ? '${value.substring(0, 30)}...' : value;
    } else if (value is List) {
      valueStr = '[${value.length} items]';
    } else if (value is Map) {
      valueStr = '{${value.length} keys}';
    } else {
      valueStr = value.toString();
    }

    if (valueStr.length > 40) {
      valueStr = '${valueStr.substring(0, 40)}...';
    }

    buffer.writeln('$key: $valueStr');
    count++;
  });

  if (config.length > maxItems) {
    buffer.writeln('... and ${config.length - maxItems} more');
  }

  return buffer.toString();
}

/// 清理ID使其符合PlantUML标识符规范
String _sanitizeId(String id) {
  return id.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
}

/// 使用PlantUML服务器生成图片
Future<void> generateComponentDiagram(
  List<Map<String, dynamic>> configs,
  Map<String, Set<String>> dependencies, {
  String plantumlServer = 'https://www.plantuml.com/plantuml',
  String outputFile = 'component_diagram.svg',
}) async {
  print('🎨 生成组件依赖图...');

  // 生成PlantUML源码
  final plantUmlSource = generatePlantUMLDiagram(configs, dependencies);

  // 保存PlantUML源码到文件
  final sourceFile = File('component_diagram.puml');
  await sourceFile.writeAsString(plantUmlSource);
  print('📝 PlantUML源码已保存到: ${sourceFile.absolute.path}');

  // 渲染PlantUML源码为图片
  final pumliREST = PumliREST(serviceURL: PumliREST.plantUmlUrl);
  final svg = await pumliREST.getSVG(plantUmlSource);
  await File(outputFile).writeAsString(svg);
  print('📸 组件依赖图已保存为: ${File(outputFile)}');
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

  // 获取组件依赖图
  final dependencies = engine.getDependencies();
  print('📊 组件依赖关系:');
  if (dependencies.isEmpty) {
    print('  (无依赖关系)');
  } else {
    dependencies.forEach((key, value) {
      if (value.isNotEmpty) {
        print('  $key 依赖于: ${value.join(', ')}');
      }
    });
  }

  // 生成组件依赖图
  await generateComponentDiagram(
    cfg,
    dependencies,
    plantumlServer: 'http://www.plantuml.com/plantuml',
    outputFile: 'component_diagram.svg',
  );

  // 运行runnable组件
  print('🚀 启动所有可运行组件...');
  await engine.runAllRunnableAndWait();
}
