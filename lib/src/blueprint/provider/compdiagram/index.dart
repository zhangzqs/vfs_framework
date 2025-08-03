import 'dart:async';

import 'package:json_annotation/json_annotation.dart';

import '../../../logger/index.dart';
import '../../engine/core.dart';
import 'uml.dart';

part 'index.g.dart';

@JsonSerializable()
class Config {
  Config({
    this.logger,
    this.plantumlServer = 'https://www.plantuml.com/plantuml',
    this.outputSVGFile = 'component_diagram.svg',
    this.outputPUMLFile = 'component_diagram.puml',
  });
  factory Config.fromJson(Map<String, dynamic> json) => _$ConfigFromJson(json);

  final String? logger;
  final String plantumlServer;
  final String outputSVGFile;
  final String outputPUMLFile;
  Map<String, dynamic> toJson() => _$ConfigToJson(this);

  Runner build(BuildContext ctx) {
    final logger = this.logger == null
        ? Logger.defaultLogger
        : ctx.mustGetComponentByName<Logger>(this.logger!);
    return Runner(ctx: ctx, config: this, logger: logger);
  }
}

class Runner {
  Runner({required this.ctx, required this.config, required this.logger});
  final BuildContext ctx;
  final Config config;
  final Logger logger;

  Future<void> run() async {
    final engine = ctx.engine;
    // 获取组件依赖图
    final dependencies = engine.getDependencies();
    logger.info(
      '📊 组件依赖关系:',
      metadata: {
        'dependencies': dependencies.map((k, v) {
          return MapEntry(k, v.toList());
        }),
      },
    );
    // 生成PlantUML图
    await generateComponentDiagram(
      componentNames: [...engine.getComponentNames(), ctx.config.name],
      logger: logger,
      dependencies: dependencies,
      configGetter: (componentName) {
        if (componentName == ctx.config.name) {
          return ctx.config;
        }
        return engine.mustGetComponentEntryByName(componentName).config;
      },
      plantumlServer: config.plantumlServer,
      outputSVGFile: config.outputSVGFile,
      outputPUMLFile: config.outputPUMLFile,
    );
  }
}

class ComponentDiagramProvider extends ComponentProvider<Runner> {
  @override
  String get type => 'builtin.component_diagram_exporter';

  @override
  Future<Runner> createComponent(
    BuildContext ctx,
    Map<String, dynamic> config,
  ) async {
    final cfg = Config.fromJson(config);
    final runner = cfg.build(ctx);
    await runner.run();
    return runner;
  }
}
