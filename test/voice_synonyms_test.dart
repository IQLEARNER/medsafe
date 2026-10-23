import 'package:flutter_test/flutter_test.dart';
import 'package:medsafe/chat/app_tools.dart';
import 'package:medsafe/chat/voice_synonyms.dart';

final meds = const [
  Med('1', 'Metformin', '500 mg', 'morning', '2026-10-18'),
  Med('2', 'Atorvastatin', '10 mg', 'night', '2026-10-18'),
];

void main() {
  test('many ways to say took -> same intent, still needs confirm', () {
    for (final phrase in [
      'I took my pills',
      'I had my medicines',
      'I swallowed my morning pills',
      'I already took them',
    ]) {
      final p = VoiceSynonyms.parse(phrase, meds, {});
      expect(p.intent, VoiceIntent.logTaken, reason: phrase);
      if (!phrase.contains('morning')) {
        expect(p.clarification, isNotNull, reason: phrase);
      }
    }
  });

  test('many ways to say missed -> missed intent, never taken', () {
    for (final phrase in [
      'I forgot my night dose',
      'I missed my Atorvastatin',
      "I didn't take my night pill",
      'I skipped my medicine',
    ]) {
      final p = VoiceSynonyms.parse(phrase, meds, {});
      expect(p.intent, VoiceIntent.reportMissed, reason: phrase);
    }
  });

  test('"I don\'t remember if I took it" is uncertain, not a log', () {
    final p = VoiceSynonyms.parse(
      "I don't remember if I took my pills",
      meds,
      {},
    );
    expect(p.intent, VoiceIntent.uncertain);
    expect(p.meds, isEmpty);
  });

  test('side-effect words are a problem report, never a dose log', () {
    final p = VoiceSynonyms.parse('I feel dizzy after my pill', meds, {});
    expect(p.intent, VoiceIntent.problemReport);
  });

  test('caregiver-confirmed alias resolves; colour alone does not', () {
    final alias = {'water pill': meds[0]};
    expect(
      VoiceSynonyms.parse('I took my water pill', meds, alias).meds,
      [meds[0]],
    );
    final p = VoiceSynonyms.parse('I took the white pill', meds, {});
    expect(p.clarification, isNotNull);
  });
}
