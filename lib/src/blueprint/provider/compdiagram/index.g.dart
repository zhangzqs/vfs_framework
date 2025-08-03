// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'index.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Config _$ConfigFromJson(Map<String, dynamic> json) => Config(
  logger: json['logger'] as String?,
  plantumlServer:
      json['plantumlServer'] as String? ?? 'https://www.plantuml.com/plantuml',
  outputSVGFile: json['outputSVGFile'] as String? ?? 'component_diagram.svg',
  outputPUMLFile: json['outputPUMLFile'] as String? ?? 'component_diagram.puml',
);

Map<String, dynamic> _$ConfigToJson(Config instance) => <String, dynamic>{
  'logger': instance.logger,
  'plantumlServer': instance.plantumlServer,
  'outputSVGFile': instance.outputSVGFile,
  'outputPUMLFile': instance.outputPUMLFile,
};
