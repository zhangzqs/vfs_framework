import 'dart:io';

import 'package:pumli/pumli.dart';
import 'package:vfs_framework/src/blueprint/index.dart';

import '../../../logger/index.dart';

/// 生成PlantUML组件图
String generatePlantUMLDiagram(
  List<String> componentNames,
  ComponentConfig Function(String componentName) configGetter,
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
  for (final name in componentNames) {
    final config = configGetter(name);
    final type = config.type;
    final componentConfig = config.config;
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
      const showMaxLines = 8;
      for (final line in configLines.take(showMaxLines)) {
        // 显示前4行配置
        buffer.writeln('  • ${line.trim()}');
      }
      if (configLines.length > showMaxLines) {
        buffer.writeln('  • ... and ${configLines.length - showMaxLines} more');
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
    if (const ['password', 'secret', 'token'].contains(key)) {
      buffer.writeln('$key: [REDACTED]');
      return;
    }
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
Future<void> generateComponentDiagram({
  required List<String> componentNames,
  required Logger logger,
  required Map<String, Set<String>> dependencies,
  required ComponentConfig Function(String componentName) configGetter,
  String plantumlServer = 'https://www.plantuml.com/plantuml',
  String? outputSVGFile,
  String? outputPUMLFile,
}) async {
  logger.info('🎨 生成组件依赖图...');

  // 生成PlantUML源码
  final plantUmlSource = generatePlantUMLDiagram(
    componentNames,
    configGetter,
    dependencies,
  );
  logger.info('📜 PlantUML源码:\n$plantUmlSource');

  if (outputPUMLFile != null) {
    await File(outputPUMLFile).writeAsString(plantUmlSource);
    logger.info('📄 PlantUML源码已保存为: $outputPUMLFile');
  }

  // 渲染PlantUML源码为图片
  if (outputSVGFile != null) {
    final pumliREST = PumliREST(serviceURL: PumliREST.plantUmlUrl);
    final svg = await pumliREST.getSVG(plantUmlSource);
    await File(outputSVGFile).writeAsString(svg);
    logger.info('📸 组件依赖图已保存为: ${File(outputSVGFile)}');
  }
}
