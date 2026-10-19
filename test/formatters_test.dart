import 'package:flutter_test/flutter_test.dart';
import 'package:nova_craft/core/formatters.dart';
import 'package:nova_craft/core/models.dart';
import 'package:nova_craft/core/strings.dart';

void main() {
  setUp(() => L10n.lang = 'en');

  group('Fmt', () {
    test('bytes scales units', () {
      expect(Fmt.bytes(0), contains('0'));
      expect(Fmt.bytes(512), contains('B'));
      expect(Fmt.bytes(2048), contains('KB'));
      expect(Fmt.bytes(5 * 1024 * 1024), contains('MB'));
      expect(Fmt.bytes(null), '—');
    });

    test('duration is compact', () {
      expect(Fmt.duration(const Duration(seconds: 30)), '30s');
      expect(Fmt.duration(const Duration(minutes: 5, seconds: 2)), '5m');
      expect(Fmt.duration(const Duration(hours: 2, minutes: 4)), '2h 4m');
      expect(Fmt.duration(const Duration(days: 1, hours: 3)), contains('d'));
      expect(Fmt.duration(null), '—');
    });

    test('relative labels stay human readable', () {
      final DateTime now = DateTime.now();
      expect(Fmt.relative(now.subtract(const Duration(seconds: 5))), L10n.t('justNow'));
      expect(Fmt.relative(now.subtract(const Duration(minutes: 6))), contains('6'));
      expect(Fmt.relative(null), L10n.t('unknown'));
    });

    test('compact numbers and short shas', () {
      expect(Fmt.compactNumber(950), '950');
      expect(Fmt.compactNumber(15000), contains('K'));
      expect(Fmt.compactNumber(2500000), contains('M'));
      expect(Fmt.shortSha('0123456789abcdef'), '0123456');
      expect(Fmt.shortSha('abc'), 'abc');
    });

    test('Playit API failures map to honest localized diagnostics', () {
      expect(Fmt.playitError('http-403'), L10n.t('playitPermissionDenied'));
      expect(Fmt.playitError('invalid-rundata-schema'), L10n.t('playitInvalidResponse'));
      expect(Fmt.playitError('timeout'), L10n.t('playitTimeout'));
      expect(Fmt.playitError('InvalidAgentKey'), L10n.t('playitKeyRejected'));
      expect(Fmt.playitError('missing-secret'), L10n.t('playitSecretMissing'));
      L10n.lang = 'ar';
      expect(Fmt.playitError('http-403'), L10n.t('playitPermissionDenied'));
      expect(Fmt.playitError('http-403'), isNot(contains('InvalidAgentKey')));
    });

    test('titleCase and phase labels', () {
      expect(Fmt.titleCase('PAPER'), 'Paper');
      expect(Fmt.titleCase(''), '');
      expect(Fmt.phaseLabel(ServerPhase.online), isNotEmpty);
    });
  });
}
