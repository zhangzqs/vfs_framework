class ComponentConfig {
  const ComponentConfig({
    required this.name,
    required this.type,
    this.config = const {},
  });

  factory ComponentConfig.fromJson(Map<String, dynamic> json) {
    return ComponentConfig(
      name: json['name'] as String,
      type: json['type'] as String,
      config: json['config'] as Map<String, dynamic>? ?? {},
    );
  }

  final String name;
  final String type;
  final Map<String, dynamic> config;

  Map<String, dynamic> toJson() {
    return {'name': name, 'type': type, 'config': config};
  }

  @override
  String toString() {
    return toJson().toString();
  }
}
