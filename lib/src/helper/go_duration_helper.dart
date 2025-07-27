import 'package:json_annotation/json_annotation.dart';

/// 兼容 Golang Duration 字符串的 JsonConverter
class GoDurationStringConverter implements JsonConverter<Duration, String> {
  const GoDurationStringConverter();

  @override
  Duration fromJson(String json) {
    if (json.isEmpty) {
      throw const FormatException('Duration string cannot be empty');
    }

    // Golang 的 Duration 字符串格式如： "300ms", "-1.5h", "2h45m"
    // 参考：https://pkg.go.dev/time#ParseDuration

    try {
      // 检查是否为数字（表示纳秒）
      if (RegExp(r'^-?\d+$').hasMatch(json)) {
        return Duration(microseconds: int.parse(json) ~/ 1000);
      }

      // 解析带单位的字符串（支持浮点数）
      final pattern = RegExp(r'^(-?\d+(?:\.\d+)?)(ns|us|µs|ms|s|m|h)$');
      final match = pattern.firstMatch(json);
      if (match != null) {
        final valStr = match.group(1);
        if (valStr == null) {
          throw FormatException('Invalid duration format: $json');
        }
        final value = double.parse(valStr);
        final unit = match.group(2);
        switch (unit) {
          case 'ns':
            return Duration(microseconds: (value / 1000).round());
          case 'us':
          case 'µs':
            return Duration(microseconds: value.round());
          case 'ms':
            return Duration(microseconds: (value * 1000).round());
          case 's':
            return Duration(microseconds: (value * 1000 * 1000).round());
          case 'm':
            return Duration(microseconds: (value * 60 * 1000 * 1000).round());
          case 'h':
            return Duration(
              microseconds: (value * 60 * 60 * 1000 * 1000).round(),
            );
          default:
            throw FormatException('Invalid duration unit: $unit');
        }
      }

      // 解析复合格式如 "1h2m3.5s"
      final parts = RegExp(
        r'(-?\d+(?:\.\d+)?)(ns|us|µs|ms|s|m|h)',
      ).allMatches(json).toList();
      if (parts.isNotEmpty) {
        // 检查是否整个字符串都被匹配（避免如"1h2x3s"这样的无效格式）
        final matchedLength = parts.fold<int>(
          0,
          (sum, match) => sum + match.group(0)!.length,
        );
        if (matchedLength != json.length) {
          throw FormatException('Invalid duration format: $json');
        }

        Duration total = Duration.zero;
        for (final part in parts) {
          final valueStr = part.group(1);
          if (valueStr == null) {
            throw FormatException('Invalid duration format: $json');
          }
          final value = double.parse(valueStr);
          final unit = part.group(2);
          switch (unit) {
            case 'ns':
              total += Duration(microseconds: (value / 1000).round());
              break;
            case 'us':
            case 'µs':
              total += Duration(microseconds: value.round());
              break;
            case 'ms':
              total += Duration(microseconds: (value * 1000).round());
              break;
            case 's':
              total += Duration(microseconds: (value * 1000 * 1000).round());
              break;
            case 'm':
              total += Duration(
                microseconds: (value * 60 * 1000 * 1000).round(),
              );
              break;
            case 'h':
              total += Duration(
                microseconds: (value * 60 * 60 * 1000 * 1000).round(),
              );
              break;
            default:
              throw FormatException('Invalid duration unit: $unit');
          }
        }
        return total;
      }

      throw FormatException('Invalid duration format: $json');
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Failed to parse duration: $json, error: $e');
    }
  }

  @override
  String toJson(Duration duration) {
    // 转换为 Golang 风格的字符串表示（如 "1h2m3s"）
    if (duration == Duration.zero) return '0s';

    // 处理负数
    final isNegative = duration.isNegative;
    final absoluteDuration = duration.abs();

    final hours = absoluteDuration.inHours;
    final minutes = absoluteDuration.inMinutes % 60;
    final seconds = absoluteDuration.inSeconds % 60;
    final milliseconds = absoluteDuration.inMilliseconds % 1000;
    final microseconds = absoluteDuration.inMicroseconds % 1000;

    final buffer = StringBuffer();
    if (isNegative) buffer.write('-');

    if (hours != 0) buffer.write('${hours}h');
    if (minutes != 0) buffer.write('${minutes}m');
    if (seconds != 0) buffer.write('${seconds}s');
    if (milliseconds != 0) buffer.write('${milliseconds}ms');
    if (microseconds != 0) buffer.write('${microseconds}us');

    // 如果所有单位都是0（除了可能的负号），返回0s
    if (buffer.length <= (isNegative ? 1 : 0)) return '0s';

    return buffer.toString();
  }
}
