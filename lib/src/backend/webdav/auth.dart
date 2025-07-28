import 'dart:convert';
import 'utils.dart';

/// Authentication type enumeration
enum AuthType { noAuth, basicAuth, digestAuth }

/// Base authentication class
class Auth {
  /// Creates an Auth instance with the provided credentials.
  ///
  /// [user] - Username for authentication
  /// [pwd] - Password for authentication
  const Auth({required this.user, required this.pwd});

  /// Username
  final String user;

  /// Password
  final String pwd;

  /// Get authentication type
  AuthType get type => AuthType.noAuth;

  /// Generate authorization header value
  String? authorize(String method, String path) => null;
}

/// Basic authentication implementation
class BasicAuth extends Auth {
  const BasicAuth({required super.user, required super.pwd});

  @override
  AuthType get type => AuthType.basicAuth;

  @override
  String authorize(String method, String path) {
    final bytes = utf8.encode('$user:$pwd');
    return 'Basic ${base64Encode(bytes)}';
  }
}

/// Digest authentication implementation
class DigestAuth extends Auth {
  final DigestParts dParts;

  DigestAuth({required super.user, required super.pwd, required this.dParts});

  String? get nonce => dParts.parts['nonce'];
  String? get realm => dParts.parts['realm'];
  String? get qop => dParts.parts['qop'];
  String? get opaque => dParts.parts['opaque'];
  String? get algorithm => dParts.parts['algorithm'];
  String? get entityBody => dParts.parts['entityBody'];

  @override
  AuthType get type => AuthType.digestAuth;

  @override
  String authorize(String method, String path) {
    dParts.uri = Uri.encodeFull(path);
    dParts.method = method;
    return _getDigestAuthorization();
  }

  String _getDigestAuthorization() {
    const nonceCount = 1;
    final cnonce = computeNonce();
    final ha1 = _computeHA1(nonceCount, cnonce);
    final ha2 = _computeHA2();
    final response = _computeResponse(ha1, ha2, nonceCount, cnonce);

    var authorization =
        'Digest username="$user", realm="$realm", nonce="$nonce", '
        'uri="${dParts.uri}", nc=$nonceCount, cnonce="$cnonce", '
        'response="$response"';

    if (qop?.isNotEmpty == true) {
      authorization += ', qop=$qop';
    }

    if (opaque?.isNotEmpty == true) {
      authorization += ', opaque=$opaque';
    }

    return authorization;
  }

  String _computeHA1(int nonceCount, String cnonce) {
    final alg = algorithm;

    if (alg == 'MD5' || alg?.isEmpty != false) {
      return md5Hash('$user:$realm:$pwd');
    } else if (alg == 'MD5-sess') {
      final md5Str = md5Hash('$user:$realm:$pwd');
      return md5Hash('$md5Str:$nonceCount:$cnonce');
    }

    return '';
  }

  String _computeHA2() {
    final qopValue = qop;

    if (qopValue == 'auth' || qopValue?.isEmpty != false) {
      return md5Hash('${dParts.method}:${dParts.uri}');
    } else if (qopValue == 'auth-int' && entityBody?.isNotEmpty == true) {
      return md5Hash('${dParts.method}:${dParts.uri}:${md5Hash(entityBody!)}');
    }

    return '';
  }

  String _computeResponse(
    String ha1,
    String ha2,
    int nonceCount,
    String cnonce,
  ) {
    final qopValue = qop;

    if (qopValue?.isEmpty != false) {
      return md5Hash('$ha1:$nonce:$ha2');
    } else if (qopValue == 'auth' || qopValue == 'auth-int') {
      return md5Hash('$ha1:$nonce:$nonceCount:$cnonce:$qopValue:$ha2');
    }

    return '';
  }
}

/// Digest authentication parts parser
class DigestParts {
  /// Creates a DigestParts instance and parses the auth header.
  ///
  /// [authHeader] - The WWW-Authenticate header value to parse
  DigestParts(String? authHeader) {
    if (authHeader != null) {
      final keys = parts.keys;
      final list = authHeader.split(',');

      for (final kv in list) {
        for (final k in keys) {
          if (kv.contains(k)) {
            final index = kv.indexOf('=');
            if (kv.length - 1 > index) {
              parts[k] = trim(kv.substring(index + 1), '"');
            }
          }
        }
      }
    }
  }

  String uri = '';
  String method = '';

  final Map<String, String> parts = {
    'nonce': '',
    'realm': '',
    'qop': '',
    'opaque': '',
    'algorithm': '',
    'entityBody': '',
  };
}
