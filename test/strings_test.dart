import 'package:flutter_test/flutter_test.dart';
import 'package:nova_craft/core/strings.dart';

void main() {
  group('L10n tables', () {
    test('Arabic and English key sets stay in sync', () {
      final Set<String> arKeys = ar.keys.toSet();
      final Set<String> enKeys = en.keys.toSet();
      expect(arKeys.difference(enKeys), isEmpty, reason: 'keys only in Arabic');
      expect(enKeys.difference(arKeys), isEmpty, reason: 'keys only in English');
      expect(arKeys.length, greaterThan(500));
    });

    test('every translated value is non-empty', () {
      for (final MapEntry<String, String> entry in ar.entries) {
        expect(entry.value.trim(), isNotEmpty, reason: 'empty Arabic value for ${entry.key}');
      }
      for (final MapEntry<String, String> entry in en.entries) {
        expect(entry.value.trim(), isNotEmpty, reason: 'empty English value for ${entry.key}');
      }
    });

    test('placeholders match between languages', () {
      final RegExp placeholder = RegExp(r'\{([a-zA-Z0-9_]+)\}');
      for (final String key in ar.keys) {
        final Set<String> arNames = placeholder.allMatches(ar[key]!).map((RegExpMatch m) => m.group(1)!).toSet();
        final Set<String> enNames = placeholder.allMatches(en[key]!).map((RegExpMatch m) => m.group(1)!).toSet();
        expect(arNames, enNames, reason: 'placeholder mismatch for $key');
      }
    });

    test('L10n.t follows the selected language and falls back to the key', () {
      L10n.lang = 'ar';
      expect(L10n.t('serverAddress'), ar['serverAddress']);
      L10n.lang = 'en';
      expect(L10n.t('serverAddress'), en['serverAddress']);
      expect(L10n.t('__missing_key__'), '__missing_key__');
      L10n.lang = 'ar';
    });

    test('L10n.f replaces every named placeholder', () {
      L10n.lang = 'en';
      final String value = L10n.f('wizardStepOf', <String, String>{'current': '2', 'total': '4'});
      expect(value, contains('2'));
      expect(value, contains('4'));
      expect(value, isNot(contains('{current}')));
      L10n.lang = 'ar';
    });
  });
}
