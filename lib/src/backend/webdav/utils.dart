import 'dart:convert';
import 'dart:math' as math;

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// Month name to number mapping for date parsing
const Map<String, String> months = {
  'jan': '01',
  'feb': '02',
  'mar': '03',
  'apr': '04',
  'may': '05',
  'jun': '06',
  'jul': '07',
  'aug': '08',
  'sep': '09',
  'oct': '10',
  'nov': '11',
  'dec': '12',
};

/// Generate MD5 hash of input string
String md5Hash(String data) {
  final bytes = utf8.encode(data);
  final digest = md5.convert(bytes);
  return digest.toString();
}

/// Parse GMT string to local DateTime
DateTime? str2LocalTime(String? str) {
  if (str == null) {
    return null;
  }

  final s = str.toLowerCase();
  if (!s.endsWith('gmt')) {
    return null;
  }

  final list = s.split(' ');
  if (list.length != 6) {
    return null;
  }

  final month = months[list[2]];
  if (month == null) {
    return null;
  }

  return DateTime.parse(
    '${list[3]}-$month-${list[1].padLeft(2, '0')}T${list[4]}Z',
  ).toLocal();
}

/// Create a DioException from HTTP response
DioException newResponseError(Response<dynamic> resp) {
  return DioException(
    requestOptions: resp.requestOptions,
    response: resp,
    type: DioExceptionType.badResponse,
    error: resp.statusMessage,
  );
}

/// Create a DioException for XML parsing errors
DioException newXmlError(dynamic err) {
  return DioException(
    requestOptions: RequestOptions(path: '/'),
    type: DioExceptionType.unknown,
    error: err,
  );
}

/// Generate secure random hex string for nonce
String computeNonce() {
  final rnd = math.Random.secure();
  final values = List<int>.generate(16, (i) => rnd.nextInt(256));
  return hex.encode(values).substring(0, 16);
}

/// Trim characters from both ends of string
String trim(String str, [String? chars]) {
  final pattern = chars != null
      ? RegExp('^[$chars]+|[$chars]+\$')
      : RegExp(r'^\s+|\s+$');
  return str.replaceAll(pattern, '');
}

/// Trim characters from left end of string
String ltrim(String str, [String? chars]) {
  final pattern = chars != null ? RegExp('^[$chars]+') : RegExp(r'^\s+');
  return str.replaceAll(pattern, '');
}

/// Trim characters from right end of string
String rtrim(String str, [String? chars]) {
  final pattern = chars != null ? RegExp('[$chars]+\$') : RegExp(r'\s+$');
  return str.replaceAll(pattern, '');
}

/// Add trailing slash if not present
String fixSlash(String s) {
  return s.endsWith('/') ? s : '$s/';
}

/// Add leading and trailing slashes if not present
String fixSlashes(String s) {
  var result = s.startsWith('/') ? s : '/$s';
  return fixSlash(result);
}

/// Join two path segments with '/'
String join(String path0, String path1) {
  return '${rtrim(path0, '/')}/${ltrim(path1, '/')}';
}

/// Extract filename from path
String path2Name(String path) {
  final str = rtrim(path, '/');
  final index = str.lastIndexOf('/');

  if (index > -1) {
    final result = str.substring(index + 1);
    return result.isEmpty ? '/' : result;
  }

  return str.isEmpty ? '/' : str;
}
