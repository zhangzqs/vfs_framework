import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';

/// 认证类型
enum AuthType {
  /// 无认证
  none,

  /// Basic认证
  basic,

  /// Bearer Token认证
  bearer,

  /// Digest认证
  digest,
}

/// WebDAV认证配置
abstract class WebDAVAuthConfig {
  const WebDAVAuthConfig({required this.type, required this.realm});

  final AuthType type;
  final String realm;

  /// 无认证配置
  static const none = _NoAuthConfig();
}

/// 无认证配置实现
class _NoAuthConfig extends WebDAVAuthConfig {
  const _NoAuthConfig() : super(type: AuthType.none, realm: '');
}

/// Basic认证配置
class WebDAVBasicAuthConfig extends WebDAVAuthConfig {
  const WebDAVBasicAuthConfig({required super.realm, required this.credentials})
    : super(type: AuthType.basic);

  /// 用户名密码映射
  final Map<String, String> credentials;
}

/// Bearer Token认证配置
class WebDAVBearerAuthConfig extends WebDAVAuthConfig {
  const WebDAVBearerAuthConfig({
    required super.realm,
    required this.tokenValidator,
  }) : super(type: AuthType.bearer);

  /// Bearer Token验证器
  final Future<bool> Function(String token) tokenValidator;
}

/// Digest认证配置
class WebDAVDigestAuthConfig extends WebDAVAuthConfig {
  const WebDAVDigestAuthConfig({
    required super.realm,
    required this.digestValidator,
    this.nonceGenerator,
  }) : super(type: AuthType.digest);

  /// Digest认证验证器
  /// (username, realm, nonce, uri, response, method, nc, cnonce, qop) -> bool
  final Future<bool> Function(
    String username,
    String realm,
    String nonce,
    String uri,
    String response,
    String method,
    String? nc,
    String? cnonce,
    String? qop,
  )
  digestValidator;

  /// Nonce生成器，用于Digest认证
  final String Function()? nonceGenerator;
}

/// 存储Digest认证的nonce信息
class _DigestNonce {
  _DigestNonce({required this.value, required this.timestamp}) : stale = false;

  final String value;
  final DateTime timestamp;
  bool stale;

  bool isExpired() {
    return DateTime.now().difference(timestamp).inMinutes > 30; // 30分钟过期
  }
}

/// Digest认证管理器
class _DigestAuthManager {
  factory _DigestAuthManager() => _instance;
  _DigestAuthManager._();
  static final _instance = _DigestAuthManager._();

  final Map<String, _DigestNonce> _nonces = {};

  /// 生成新的nonce
  String generateNonce() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final random = math.Random().nextInt(1000000).toString();
    final nonce = md5.convert(utf8.encode('$timestamp:$random')).toString();

    _nonces[nonce] = _DigestNonce(value: nonce, timestamp: DateTime.now());

    _cleanupExpiredNonces();
    return nonce;
  }

  /// 验证nonce是否有效
  bool validateNonce(String nonce) {
    final nonceInfo = _nonces[nonce];
    if (nonceInfo == null) return false;

    if (nonceInfo.isExpired()) {
      _nonces.remove(nonce);
      return false;
    }

    return true;
  }

  /// 标记nonce为过期
  void markStale(String nonce) {
    final nonceInfo = _nonces[nonce];
    if (nonceInfo != null) {
      nonceInfo.stale = true;
    }
  }

  /// 清理过期的nonce
  void _cleanupExpiredNonces() {
    _nonces.removeWhere((key, value) => value.isExpired());
  }
}

/// WebDAV认证中间件
Middleware webdavAuthMiddleware(WebDAVAuthConfig config) {
  return (Handler innerHandler) {
    return (Request request) async {
      // 无认证直接通过
      if (config.type == AuthType.none) {
        return await innerHandler(request);
      }

      final authHeader = request.headers['Authorization'];

      // 缺少认证头
      if (authHeader == null || authHeader.isEmpty) {
        return _createUnauthorizedResponse(config, request);
      }

      // 根据认证类型验证
      bool isAuthenticated = false;

      switch (config.type) {
        case AuthType.basic:
          isAuthenticated = await _validateBasicAuth(authHeader, config);
          break;
        case AuthType.bearer:
          isAuthenticated = await _validateBearerAuth(authHeader, config);
          break;
        case AuthType.digest:
          isAuthenticated = await _validateDigestAuth(
            authHeader,
            config,
            request,
          );
          break;
        case AuthType.none:
          isAuthenticated = true;
          break;
      }

      if (!isAuthenticated) {
        return _createUnauthorizedResponse(config, request);
      }

      return await innerHandler(request);
    };
  };
}

/// 验证Basic认证
Future<bool> _validateBasicAuth(
  String authHeader,
  WebDAVAuthConfig config,
) async {
  if (!authHeader.startsWith('Basic ')) {
    return false;
  }

  if (config is! WebDAVBasicAuthConfig) {
    return false;
  }

  try {
    final credentials = authHeader.substring(6);
    final decoded = utf8.decode(base64Decode(credentials));
    final parts = decoded.split(':');

    if (parts.length != 2) return false;

    final username = parts[0];
    final password = parts[1];

    return config.credentials[username] == password;
  } catch (e) {
    return false;
  }
}

/// 验证Bearer Token认证
Future<bool> _validateBearerAuth(
  String authHeader,
  WebDAVAuthConfig config,
) async {
  if (!authHeader.startsWith('Bearer ')) {
    return false;
  }

  if (config is! WebDAVBearerAuthConfig) {
    return false;
  }

  final token = authHeader.substring(7);

  try {
    return await config.tokenValidator(token);
  } catch (e) {
    return false;
  }
}

/// 验证Digest认证
Future<bool> _validateDigestAuth(
  String authHeader,
  WebDAVAuthConfig config,
  Request request,
) async {
  if (!authHeader.startsWith('Digest ')) {
    return false;
  }

  if (config is! WebDAVDigestAuthConfig) {
    return false;
  }

  try {
    final authData = _parseDigestAuthHeader(authHeader);
    final authManager = _DigestAuthManager();

    // 验证nonce
    if (!authManager.validateNonce(authData['nonce'] ?? '')) {
      authManager.markStale(authData['nonce'] ?? '');
      return false;
    }

    // 调用验证器
    return await config.digestValidator(
      authData['username'] ?? '',
      authData['realm'] ?? '',
      authData['nonce'] ?? '',
      authData['uri'] ?? '',
      authData['response'] ?? '',
      request.method,
      authData['nc'],
      authData['cnonce'],
      authData['qop'],
    );
  } catch (e) {
    return false;
  }
}

/// 解析Digest认证头
Map<String, String> _parseDigestAuthHeader(String authHeader) {
  final authData = <String, String>{};
  final params = authHeader.substring(7).split(',');

  for (final param in params) {
    final trimmed = param.trim();
    final equalIndex = trimmed.indexOf('=');

    if (equalIndex > 0) {
      final key = trimmed.substring(0, equalIndex).trim();
      var value = trimmed.substring(equalIndex + 1).trim();

      // 移除引号
      if (value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }

      authData[key] = value;
    }
  }

  return authData;
}

/// 创建401未授权响应
Response _createUnauthorizedResponse(WebDAVAuthConfig config, Request request) {
  final headers = <String, String>{};

  switch (config.type) {
    case AuthType.basic:
      headers['WWW-Authenticate'] = 'Basic realm="${config.realm}"';
      break;
    case AuthType.bearer:
      headers['WWW-Authenticate'] = 'Bearer realm="${config.realm}"';
      break;
    case AuthType.digest:
      final authManager = _DigestAuthManager();
      final digestConfig = config as WebDAVDigestAuthConfig;
      final nonce =
          digestConfig.nonceGenerator?.call() ?? authManager.generateNonce();
      headers['WWW-Authenticate'] =
          'Digest realm="${config.realm}", '
          'nonce="$nonce", '
          'algorithm="MD5", '
          'qop="auth,auth-int"';
      break;
    case AuthType.none:
      break;
  }

  return Response.unauthorized('Authentication required', headers: headers);
}
