import 'config.dart';

class BlueprintException implements Exception {
  BlueprintException(this.message, {this.context});
  final String message;
  final BuildContext? context;

  @override
  String toString() {
    var ret = 'BlueprintException: $message';
    if (context != null) {
      ret += ' (ComponentConfig: ${context!.config})';
    }
    return ret;
  }
}

class ComponentEntry<T extends Object> {
  ComponentEntry({
    required this.config,
    required this.component,
    required this.provider,
  });
  final ComponentConfig config;
  final T component;
  final ComponentProvider<Object> provider;

  @override
  String toString() {
    return {
      'ComponentEntry': {
        'config': config,
        'component': component.toString(),
        'provider': provider.type,
      },
    }.toString();
  }
}

/// 蓝图编排引擎
class BlueprintEngine {
  BlueprintEngine({List<ComponentProvider<Object>> providers = const []})
    : _providerRegistry = Map.fromEntries(
        providers.map((p) => MapEntry(p.type, p)),
      );

  /// provider 注册表
  final Map<String, ComponentProvider<Object>> _providerRegistry;

  /// 已构造好的组件集合
  final Map<String, ComponentEntry> _components = {};

  /// 组件依赖关系图
  final Map<String, Set<String>> _dependencies = {};

  void registerProvider(ComponentProvider<Object> provider) {
    if (_providerRegistry.containsKey(provider.type)) {
      throw BlueprintException(
        'Provider of type ${provider.type} is already registered',
      );
    }
    _providerRegistry[provider.type] = provider;
  }

  Future<T> loadComponent<T>(ComponentConfig cfg) async {
    if (_components.containsKey(cfg.name)) {
      throw BlueprintException('Component ${cfg.name} is already loaded');
    }
    final provider = _providerRegistry[cfg.type];
    if (provider == null) {
      throw BlueprintException('No provider registered for type ${cfg.type}');
    }
    final ctx = BuildContext(engine: this, config: cfg);
    final component = await provider.createComponent(ctx, cfg.config);
    if (component is! T) {
      throw BlueprintException(
        'Component ${cfg.name} is not of type ${T.toString()}',
      );
    }
    _components[cfg.name] = ComponentEntry(
      config: cfg,
      component: component,
      provider: provider,
    );
    return component as T;
  }

  T? getComponentByName<T>(String name, {String? requiredBy}) {
    // 记录组件依赖关系
    if (requiredBy != null) {
      _dependencies.putIfAbsent(requiredBy, () => <String>{}).add(name);
    }
    final entry = _components[name];
    if (entry != null) {
      if (entry.component is T) {
        return entry.component as T;
      } else {
        throw BlueprintException(
          'Component $name is not of type ${T.toString()}',
        );
      }
    }
    return null;
  }

  T mustGetComponentByName<T>(String name, {String? requiredBy}) {
    final component = getComponentByName<T>(name, requiredBy: requiredBy);
    if (component == null) {
      throw BlueprintException('Component $name not found');
    }
    return component as T;
  }

  Map<String, dynamic> mustGetComponentConfigByName(String name) {
    if (_components.containsKey(name)) {
      return _components[name]!.config.config;
    }
    throw BlueprintException('Component $name not found');
  }

  ComponentEntry<Object> mustGetComponentEntryByName(String name) {
    final entry = _components[name];
    if (entry == null) {
      throw BlueprintException('Component $name not found');
    }
    return entry;
  }

  List<String> getComponentNames() {
    return List.unmodifiable(_components.keys);
  }

  /// 获取组件依赖图
  Map<String, Set<String>> getDependencies() {
    return Map.unmodifiable(
      _dependencies.map((key, value) => MapEntry(key, Set.unmodifiable(value))),
    );
  }

  Future<void> close() async {
    for (final entry in _components.values) {
      try {
        await entry.provider.close(
          BuildContext(engine: this, config: entry.config),
          entry.component,
        );
      } catch (e) {
        print('Error closing component ${entry.config.name}: $e');
      }
    }
    _components.clear();
  }
}

class BuildContext {
  BuildContext({required this.engine, required this.config});
  final BlueprintEngine engine;
  final ComponentConfig config;

  T mustGetComponentByName<T>(String name) {
    return engine.mustGetComponentByName<T>(name, requiredBy: config.name);
  }
}

abstract class ComponentProvider<T extends Object> {
  String get type;
  Future<T> createComponent(BuildContext ctx, Map<String, dynamic> config);
  Future<void> close(BuildContext ctx, T component) async {}
}
