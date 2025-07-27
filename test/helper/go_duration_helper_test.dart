import 'package:test/test.dart';
import 'package:vfs_framework/src/helper/go_duration_helper.dart';

void main() {
  group('GoDurationStringConverter', () {
    late GoDurationStringConverter converter;

    setUp(() {
      converter = const GoDurationStringConverter();
    });

    group('fromJson', () {
      test('should parse integer nanoseconds', () {
        expect(
          converter.fromJson('1000000'),
          equals(const Duration(milliseconds: 1)),
        );
      });

      test('should parse simple units', () {
        expect(
          converter.fromJson('5ns'),
          equals(const Duration(microseconds: 0)),
        ); // 5ns < 1us
        expect(
          converter.fromJson('1000ns'),
          equals(const Duration(microseconds: 1)),
        );
        expect(
          converter.fromJson('500us'),
          equals(const Duration(microseconds: 500)),
        );
        expect(
          converter.fromJson('500µs'),
          equals(const Duration(microseconds: 500)),
        );
        expect(
          converter.fromJson('250ms'),
          equals(const Duration(milliseconds: 250)),
        );
        expect(converter.fromJson('30s'), equals(const Duration(seconds: 30)));
        expect(converter.fromJson('5m'), equals(const Duration(minutes: 5)));
        expect(converter.fromJson('2h'), equals(const Duration(hours: 2)));
      });

      test('should parse floating point durations', () {
        expect(
          converter.fromJson('1.5s'),
          equals(const Duration(milliseconds: 1500)),
        );
        expect(
          converter.fromJson('2.5h'),
          equals(const Duration(hours: 2, minutes: 30)),
        );
        expect(converter.fromJson('0.5m'), equals(const Duration(seconds: 30)));
      });

      test('should parse compound durations', () {
        expect(
          converter.fromJson('1h2m3s'),
          equals(const Duration(hours: 1, minutes: 2, seconds: 3)),
        );
        expect(
          converter.fromJson('2h45m'),
          equals(const Duration(hours: 2, minutes: 45)),
        );
        expect(
          converter.fromJson('1s500ms'),
          equals(const Duration(milliseconds: 1500)),
        );
      });

      test('should parse negative durations', () {
        expect(converter.fromJson('-1h'), equals(const Duration(hours: -1)));
        expect(
          converter.fromJson('-30s'),
          equals(const Duration(seconds: -30)),
        );
      });

      test('should handle zero duration', () {
        expect(converter.fromJson('0s'), equals(Duration.zero));
        expect(converter.fromJson('0'), equals(Duration.zero));
      });

      test('should throw on invalid formats', () {
        expect(() => converter.fromJson(''), throwsA(isA<FormatException>()));
        expect(() => converter.fromJson('1x'), throwsA(isA<FormatException>()));
        expect(
          () => converter.fromJson('1h2x3s'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => converter.fromJson('invalid'),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('toJson', () {
      test('should format zero duration', () {
        expect(converter.toJson(Duration.zero), equals('0s'));
      });

      test('should format simple durations', () {
        expect(converter.toJson(const Duration(hours: 2)), equals('2h'));
        expect(converter.toJson(const Duration(minutes: 30)), equals('30m'));
        expect(converter.toJson(const Duration(seconds: 45)), equals('45s'));
        expect(
          converter.toJson(const Duration(milliseconds: 500)),
          equals('500ms'),
        );
        expect(
          converter.toJson(const Duration(microseconds: 250)),
          equals('250us'),
        );
      });

      test('should format compound durations', () {
        expect(
          converter.toJson(const Duration(hours: 1, minutes: 2, seconds: 3)),
          equals('1h2m3s'),
        );
        expect(
          converter.toJson(const Duration(minutes: 5, milliseconds: 500)),
          equals('5m500ms'),
        );
      });

      test('should format negative durations', () {
        expect(converter.toJson(const Duration(hours: -1)), equals('-1h'));
        expect(converter.toJson(const Duration(seconds: -30)), equals('-30s'));
      });
    });

    group('round trip', () {
      test('should preserve values through round trip', () {
        final testCases = [
          '1h',
          '30m',
          '45s',
          '500ms',
          '1h30m45s',
          '-2h',
          '0s',
        ];

        for (final testCase in testCases) {
          final duration = converter.fromJson(testCase);
          final backToString = converter.toJson(duration);
          final backToDuration = converter.fromJson(backToString);

          expect(
            backToDuration,
            equals(duration),
            reason:
                '$testCase -> $duration -> $backToString -> $backToDuration',
          );
        }
      });
    });
  });
}
