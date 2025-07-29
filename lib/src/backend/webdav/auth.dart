import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// WebDAV认证拦截器基类
abstract class WebDAVAuthInterceptor extends Interceptor {
  const WebDAVAuthInterceptor();

  /// 生成Authorization头部值
  String generateAuthHeader(RequestOptions options);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    try {
      final authHeader = generateAuthHeader(options);
      options.headers['Authorization'] = authHeader;
      handler.next(options);
    } catch (e) {
      handler.reject(
        DioException(
          requestOptions: options,
          error: 'Failed to generate auth header: $e',
          type: DioExceptionType.unknown,
        ),
      );
    }
  }
}

/// Bearer Token 认证拦截器
class WebDAVBearerTokenInterceptor extends WebDAVAuthInterceptor {
  const WebDAVBearerTokenInterceptor({required this.token});

  final String token;

  @override
  String generateAuthHeader(RequestOptions options) {
    if (token.isEmpty) {
      throw ArgumentError('Token cannot be empty');
    }
    return 'Bearer $token';
  }
}

/// Basic Auth 认证拦截器
class WebDAVBasicAuthInterceptor extends WebDAVAuthInterceptor {
  const WebDAVBasicAuthInterceptor({
    required this.username,
    required this.password,
  });

  final String username;
  final String password;

  @override
  String generateAuthHeader(RequestOptions options) {
    if (username.isEmpty) {
      throw ArgumentError('Username cannot be empty');
    }

    final credentials = base64Encode(utf8.encode('$username:$password'));
    return 'Basic $credentials';
  }
}

/// Digest Auth 认证拦截器
class WebDAVDigestAuthInterceptor extends Interceptor {
  WebDAVDigestAuthInterceptor({
    required this.dio,
    required this.username,
    required this.password,
  });

  final Dio dio;
  final String username;
  final String password;

  // 缓存 Digest Auth 的认证信息
  _DigestAuthInfo? _authInfo;

  // nonce计数器，每次认证时递增
  int _nonceCount = 0;
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // 如果有缓存的认证信息，直接使用
    if (_authInfo != null) {
      try {
        // 获取请求体数据（用于auth-int模式）
        String? requestBody;
        if (_authInfo!.qop == 'auth-int' && options.data != null) {
          if (options.data is String) {
            requestBody = options.data as String;
          } else if (options.data is Map || options.data is List) {
            requestBody = jsonEncode(options.data);
          } else {
            requestBody = options.data.toString();
          }
        }

        final digestResponse = _calculateDigestResponse(
          method: options.method,
          uri: options.path,
          authInfo: _authInfo!,
          requestBody: requestBody,
        );
        options.headers['Authorization'] = digestResponse;
      } catch (e) {
        // 如果计算失败，清除缓存的认证信息，让服务器重新发送挑战
        _authInfo = null;
      }
    }

    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // 处理 401 认证挑战
    if (err.response?.statusCode == 401) {
      final authHeader = err.response?.headers.value('WWW-Authenticate');

      if (authHeader?.startsWith('Digest ') == true) {
        try {
          // 解析认证挑战
          _authInfo = _DigestAuthInfo.parseDigestChallenge(authHeader!);
          // 重置nonce计数器，因为有了新的nonce
          _nonceCount = 0;

          // 克隆原请求并重新发送
          final clonedOptions = err.requestOptions.copyWith();
          final response = await dio.fetch<dynamic>(clonedOptions);
          return handler.resolve(response);
        } catch (e) {
          // 解析或重试失败，返回原错误
          return handler.reject(err);
        }
      }
    }

    handler.next(err);
  }

  /// 计算 Digest Auth 的响应
  String _calculateDigestResponse({
    required String method,
    required String uri,
    required _DigestAuthInfo authInfo,
    String? requestBody, // 添加请求体参数用于auth-int
  }) {
    if (username.isEmpty) {
      throw ArgumentError('Username cannot be empty');
    }

    if (authInfo.nonce.isEmpty) {
      throw StateError('Nonce is required for digest authentication');
    }

    // 计算 HA2 - 根据qop值决定是否包含请求体
    final ha2 = _calculateHA2(
      method,
      uri,
      qop: authInfo.qop,
      entityBody: requestBody,
    );

    // 计算响应
    final String response;
    int currentNonceCount = _nonceCount;
    String? cnonce;

    if (authInfo.qop == null || authInfo.qop!.isEmpty) {
      // RFC 2069 compatibility
      // 对于MD5-SESS，即使在RFC 2069模式下也需要cnonce
      if (authInfo.algorithm.toUpperCase() == 'MD5-SESS') {
        cnonce = _generateCnonce();
      }
      
      final ha1 = _calculateHA1(authInfo, cnonce: cnonce);
      response = md5
          .convert(utf8.encode('$ha1:${authInfo.nonce}:$ha2'))
          .toString();
    } else {
      // RFC 2617 with qop (支持 auth 和 auth-int)
      _nonceCount++; // 递增nonce计数器
      currentNonceCount = _nonceCount;
      final nc = _nonceCount.toString().padLeft(8, '0'); // 格式化为8位数字
      cnonce = _generateCnonce(); // 生成一次并复用

      final ha1 = _calculateHA1(authInfo, cnonce: cnonce);
      response = md5
          .convert(
            utf8.encode(
              '$ha1:${authInfo.nonce}:$nc:$cnonce:${authInfo.qop}:$ha2',
            ),
          )
          .toString();
    }

    return authInfo.buildAuthorizationHeader(
      uri: uri,
      response: response,
      username: username,
      nonceCount: currentNonceCount,
      cnonce: cnonce ?? '', // 使用相同的cnonce或空字符串（RFC 2069）
    );
  }

  /// 计算 HA1
  String _calculateHA1(_DigestAuthInfo authInfo, {String? cnonce}) {
    switch (authInfo.algorithm.toUpperCase()) {
      case 'MD5':
        // 标准MD5算法: HA1 = MD5(username:realm:password)
        return md5
            .convert(utf8.encode('$username:${authInfo.realm}:$password'))
            .toString();
      case 'MD5-SESS':
        // MD5-SESS算法: HA1 = MD5(MD5(username:realm:password):nonce:cnonce)
        if (cnonce == null || cnonce.isEmpty) {
          throw StateError('cnonce is required for MD5-SESS algorithm');
        }
        final ha1Base = md5
            .convert(utf8.encode('$username:${authInfo.realm}:$password'))
            .toString();
        return md5
            .convert(utf8.encode('$ha1Base:${authInfo.nonce}:$cnonce'))
            .toString();
      default:
        throw UnsupportedError(
          'Unsupported digest algorithm: ${authInfo.algorithm}',
        );
    }
  }

  /// 计算 HA2
  String _calculateHA2(
    String method,
    String uri, {
    String? qop,
    String? entityBody,
  }) {
    if (qop == 'auth-int') {
      // RFC 2617 auth-int: 包含请求体的完整性保护
      final bodyHash = entityBody != null
          ? md5.convert(utf8.encode(entityBody)).toString()
          : md5.convert(utf8.encode('')).toString(); // 空请求体的hash
      return md5.convert(utf8.encode('$method:$uri:$bodyHash')).toString();
    } else {
      // RFC 2617 auth 或 RFC 2069: 仅包含方法和URI
      return md5.convert(utf8.encode('$method:$uri')).toString();
    }
  }

  /// 生成客户端随机数
  String _generateCnonce() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    return md5.convert(utf8.encode(timestamp)).toString().substring(0, 8);
  }
}

/// Digest认证信息数据类
class _DigestAuthInfo {
  const _DigestAuthInfo({
    required this.realm,
    required this.nonce,
    required this.algorithm,
    this.qop,
    this.opaque,
  });

  /// 解析 Digest Auth 的挑战信息
  factory _DigestAuthInfo.parseDigestChallenge(String header) {
    final challengeData = <String, String>{};

    // 移除 "Digest " 前缀并解析参数
    final params = header.substring(7).split(',');

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

        challengeData[key] = value;
      }
    }

    // 处理qop - 如果服务器提供多个选项，优先选择auth-int，然后是auth
    String? selectedQop;
    final qopValue = challengeData['qop'];
    if (qopValue != null) {
      final qopOptions = qopValue.split(',').map((e) => e.trim()).toList();
      if (qopOptions.contains('auth-int')) {
        selectedQop = 'auth-int'; // 优先选择更安全的auth-int
      } else if (qopOptions.contains('auth')) {
        selectedQop = 'auth';
      } else {
        selectedQop = qopOptions.first; // 选择第一个可用选项
      }
    }

    return _DigestAuthInfo(
      realm: challengeData['realm'] ?? '',
      nonce: challengeData['nonce'] ?? '',
      algorithm: challengeData['algorithm'] ?? 'MD5',
      qop: selectedQop,
      opaque: challengeData['opaque'],
    );
  }

  final String realm;
  final String nonce;
  final String algorithm;
  final String? qop;
  final String? opaque;

  @override
  String toString() {
    return '_DigestAuthInfo('
        'realm: $realm, '
        'nonce: $nonce, '
        'algorithm: $algorithm, '
        'qop: $qop, '
        'opaque: $opaque)';
  }

  /// 构建Authorization头部
  String buildAuthorizationHeader({
    required String uri,
    required String response,
    required String username,
    required int nonceCount,
    required String cnonce,
  }) {
    final buffer = StringBuffer('Digest ');
    buffer.write('username="$username", ');
    buffer.write('realm="$realm", ');
    buffer.write('nonce="$nonce", ');
    buffer.write('uri="$uri", ');
    buffer.write('response="$response"');

    if (algorithm.isNotEmpty) {
      buffer.write(', algorithm="$algorithm"');
    }

    if (opaque?.isNotEmpty == true) {
      buffer.write(', opaque="$opaque"');
    }

    if (qop?.isNotEmpty == true) {
      buffer.write(', qop=$qop');
      final nc = nonceCount.toString().padLeft(8, '0');
      buffer.write(', nc=$nc');
      buffer.write(', cnonce="$cnonce"');
    }

    return buffer.toString();
  }
}
