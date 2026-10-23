// Voice commands for elderly patients: many ways to say the same thing.
// Design rule: synonyms EXPAND what the app understands, they NEVER
// lower the bar for writing to the log. Every write still needs the
// confirm card + Yes tap, and low-confidence parses must ask, not guess.
import 'app_tools.dart';

enum VoiceIntent { logTaken, reportMissed, uncertain, checkTaken, checkDue, problemReport, unknown }

class ParsedVoice {
  final VoiceIntent intent;
  final List<Med> meds; // empty = not identified yet
  final double confidence; // 0.0 - 1.0
  final String? clarification; // question to ask when confidence is low
  const ParsedVoice(this.intent, this.meds, this.confidence, this.clarification);
}

class VoiceSynonyms {
  // --- Intent synonyms: elderly patients say these for the same thing ---
  static const tookPhrases = [
    'took', 'taken', 'had my', 'had the', 'swallowed', 'drank', 'ate',
    'consumed', 'finished my', 'took them', 'took it', 'i did', 'already took',
    'i have taken', 'done', 'took my pills', 'took my medicines',
    'took my medicine', 'had my pills', 'had my medicines',
  ];
  static const missedPhrases = [
    'forgot', 'missed', 'skipped', "didn't take", 'did not take',
    'didnt take', 'forgot to take', 'missed my', 'left it', 'did not have',
    "didn't have", 'never took', 'forgot my',
  ];
  static const uncertainPhrases = [
    "don't remember", 'do not remember', 'not sure', "can't remember",
    'cannot remember', 'did i', 'have i', 'maybe i', 'think i did',
    'not sure if', 'unsure',
  ];
  static const problemPhrases = [
    'dizzy', 'dizziness', 'nauseous', 'nausea', 'vomit', 'sick', 'headache',
    'chest pain', 'fell', 'fall', 'rash', 'swelling', 'breathing',
    'feel bad', 'feel sick', 'side effect',
  ];

  /// Normalize ASR output before matching: lowercase, fix common
  /// homophone / number confusions. "to / too / two" is the classic one:
  /// "I took to" usually means "I took two" — but NEVER trust that alone.
  /// Number words are kept as a hint; the confirm card shows the count.
  static String normalize(String raw) {
    var s = ' ${raw.toLowerCase()} ';
    s = s.replaceAll(RegExp(r"[^a-z0-9 ']+"), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  /// Resolve a medication from what the patient CALLS it.
  /// [aliases] is caregiver-entered, per patient, confirmed once:
  /// e.g. {"water pill": Med(...furosemide...), "sugar pill": Med(...)}.
  /// Colour / shape alone ("white pill", "blue pill") is NEVER enough
  /// unless it maps to exactly ONE registered med AND the caregiver
  /// confirmed that alias. Otherwise return empty -> ask.
  static List<Med> resolveMeds(
    String normalized,
    List<Med> todaysMeds,
    Map<String, Med> aliases,
  ) {
    // 1. Exact registered name in the transcript.
    final byName = todaysMeds
        .where((m) => normalized.contains(m.name.toLowerCase()))
        .toList();
    if (byName.isNotEmpty) return byName;

    // 2. Confirmed alias ("water pill", "night pill", "morning pill").
    for (final e in aliases.entries) {
      if (normalized.contains(e.key)) return [e.value];
    }

    // 3. Time-slot hint only ("morning pills", "night dose") -> all meds
    // in that slot. Still needs the confirm card to name them.
    if (normalized.contains('morning')) {
      return todaysMeds.where((m) => m.timeSlot == 'morning').toList();
    }
    if (normalized.contains('night') || normalized.contains('evening')) {
      return todaysMeds.where((m) => m.timeSlot == 'night').toList();
    }
    return [];
  }

  static ParsedVoice parse(
    String raw,
    List<Med> todaysMeds,
    Map<String, Med> aliases,
  ) {
    final text = normalize(raw);

    // Problem / side-effect reports are NEVER a dose log.
    if (problemPhrases.any(text.contains)) {
      return const ParsedVoice(
          VoiceIntent.problemReport, [], 0.9,
          'That sounds like a problem, not a dose. Flag caregiver?');
    }
    // "I don't remember if I took it" — do NOT log, show the log status.
    if (uncertainPhrases.any(text.contains)) {
      return const ParsedVoice(VoiceIntent.uncertain, [], 0.9, null);
    }
    if (missedPhrases.any(text.contains)) {
      final meds = resolveMeds(text, todaysMeds, aliases);
      if (meds.isEmpty) {
        return const ParsedVoice(VoiceIntent.reportMissed, [], 0.4,
            'Which medication did you miss? Tap it here:');
      }
      return ParsedVoice(VoiceIntent.reportMissed, meds, 0.8, null);
    }
    if (tookPhrases.any(text.contains)) {
      final meds = resolveMeds(text, todaysMeds, aliases);
      if (meds.isEmpty) {
        // "I took my pills" with no name/time: ask, never guess.
        return const ParsedVoice(VoiceIntent.logTaken, [], 0.4,
            'Which ones did you take? Tap them here:');
      }
      // Meds identified, but voice is still only MEDIUM confidence:
      // the confirm card + read-aloud is what makes it accurate.
      return ParsedVoice(VoiceIntent.logTaken, meds, 0.75, null);
    }
    if (text.contains('did i take') || text.contains('have i taken')) {
      return const ParsedVoice(VoiceIntent.checkTaken, [], 0.9, null);
    }
    if (text.contains('next') || text.contains('what is') && text.contains('due')) {
      return const ParsedVoice(VoiceIntent.checkDue, [], 0.9, null);
    }
    return const ParsedVoice(VoiceIntent.unknown, [], 0.2,
        'Sorry, I didn\'t catch that. Tap one: Took / Missed / Did I take?');
  }
}
