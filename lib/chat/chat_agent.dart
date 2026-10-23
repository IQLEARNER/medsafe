import 'app_tools.dart';
import 'chat_repository.dart';
import 'meta_model_client.dart';

/// Scripted agent: rules first, confirm before every write.
/// Handles Kalyan's two example utterances exactly.
class ChatAgent {
  final AppTools tools;
  final ChatRepository memory;
  final LlmClient llm;
  DoseProposal? pendingProposal;
  List<Med> pendingMissedMeds = [];
  String? pendingMissedDate;
  List<String> suggestedMedIds = [];

  ChatAgent({required this.tools, required this.memory, required this.llm});

  /// Returns the assistant reply text. UI renders confirm cards when
  /// [pendingProposal] / [pendingMissed] is set.
  String handle(String text) {
    memory.add('user', text);
    final lower = text.toLowerCase();
    pendingProposal = null;
    pendingMissedMeds = [];
    pendingMissedDate = null;
    suggestedMedIds = [];
    late final String reply;

    if (lower.contains('dizzy') ||
        lower.contains('nausea') ||
        lower.contains('nauseous') ||
        lower.contains('rash') ||
        lower.contains('side effect') ||
        lower.contains('chest pain') ||
        lower.contains('breathing')) {
      reply =
          'I\'m sorry you\'re feeling unwell. I won\'t change or log a '
          'dose from this message. Please contact your doctor or pharmacist; '
          'seek urgent help for severe or rapidly worsening symptoms.';
    } else if (lower.contains('don\'t remember') ||
        lower.contains('not sure') ||
        lower.contains('did i take') ||
        lower.contains('did i miss')) {
      final taken = tools.loggedMedIds;
      reply =
          'Today, checked as taken: '
          '${taken.isEmpty ? "none yet" : _medicationNames(taken)}. '
          'Not checked yet: ${_medicationNames(tools.notYetLogged().map((med) => med.id).toList())}.';
    } else if (lower.contains('forgot') ||
        lower.contains('missed') ||
        lower.contains('skipped') ||
        lower.contains("didn't take")) {
      reply = _handleMissed(lower);
    } else if (_isTakenPhrase(lower)) {
      reply = _handleTook(lower);
    } else if (lower.contains('next') || lower.contains('what')) {
      final next = tools.notYetLogged();
      reply = next.isEmpty
          ? 'Nothing left due today.'
          : 'Not checked yet today: ${next.map(_displayMed).join(", ")}. '
                'Please use the medication schedule for exact reminder times.';
    } else {
      reply =
          'I can help with: "I took my medicines", "Did I take them?", '
          '"What is next?", or "I missed a dose". Which one?';
    }
    memory.add('assistant', reply);
    return reply;
  }

  /// Uses the configured LLM for general, non-rule-based questions while
  /// preserving the app's confirm-before-write safety rules.
  Future<String> handleAsync(String text) async {
    final lower = text.toLowerCase();
    if (lower.contains('dizzy') ||
        lower.contains('nausea') ||
        lower.contains('nauseous') ||
        lower.contains('rash') ||
        lower.contains('side effect') ||
        lower.contains('chest pain') ||
        lower.contains('breathing')) {
      return handle(text);
    }
    if (lower.contains('don\'t remember') ||
        lower.contains('not sure') ||
        lower.contains('did i take') ||
        lower.contains('did i miss') ||
        lower.contains('forgot') ||
        lower.contains('missed') ||
        lower.contains('skipped') ||
        lower.contains("didn't take") ||
        _isTakenPhrase(lower) ||
        lower.contains('next') ||
        lower.contains('what')) {
      return handle(text);
    }

    final context = _factsContext();
    try {
      final llmReply = await llm.reply(text, context);
      final safeReply = llmReply.trim();
      if (safeReply.isEmpty) {
        throw StateError('AI response was empty.');
      }
      memory.add('assistant', safeReply);
      return safeReply;
    } catch (error) {
      final fallback =
          'I’m having trouble reaching the AI service right now. '
          'This is usually caused by an invalid or blocked API key, model issue, or quota problem. '
          'The app will not record a dose until you confirm it. '
          'Details: $error';
      memory.add('assistant', fallback);
      return fallback;
    }
  }

  String _factsContext() {
    final medSummary = tools.todaysMeds.isEmpty
        ? 'No medications scheduled.'
        : tools.todaysMeds
            .map((med) => '${med.name} ${med.strength}'.trim())
            .join('; ');

    final takenSummary = tools.loggedMedIds.isEmpty
        ? 'No medications logged yet.'
        : 'Logged today: ${_medicationNames(tools.loggedMedIds)}.';

    return 'Medication list: $medSummary. $takenSummary';
  }

  String _handleTook(String lower) {
    final candidates = tools.notYetLogged();
    if (candidates.isEmpty) {
      return 'Every medication on today\'s list is already checked as taken.';
    }
    final named = candidates.where((med) {
      final name = med.name.toLowerCase();
      return name.length >= 3 && lower.contains(name);
    }).toList();
    final explicitCount = lower.contains('two') || lower.contains('both');
    final suggested = named.isNotEmpty
        ? named
        : explicitCount && candidates.length == 2
        ? candidates
        : candidates.length == 1
        ? candidates
        : <Med>[];
    suggestedMedIds = suggested.map((med) => med.id).toList();
    pendingProposal = tools.proposeLogDose(
      candidates,
      DateTime.now().toIso8601String(),
    );
    if (suggested.isEmpty) {
      return 'Which medication did you take? Select only the medicine(s) '
          'you took below, then confirm.';
    }
    return 'Please confirm that you took ${suggested.map(_displayMed).join(' and ')}. '
        'Nothing is recorded until you confirm below.';
  }

  String _handleMissed(String lower) {
    final date = lower.contains('yesterday')
        ? DateTime.now().subtract(const Duration(days: 1))
        : DateTime.now();
    final dateKey = date.toIso8601String().substring(0, 10);
    var candidates = tools
        .getTodayMeds()
        .where(
          (med) =>
              !med.takenDates.contains(dateKey) &&
              !med.missedDates.contains(dateKey),
        )
        .toList();
    if (lower.contains('night') || lower.contains('evening')) {
      candidates = candidates.where((med) => med.timeSlot == 'night').toList();
    }
    final named = candidates.where((med) {
      final name = med.name.toLowerCase();
      return name.length >= 3 && lower.contains(name);
    }).toList();
    if (named.isNotEmpty) candidates = named;
    if (candidates.isEmpty) {
      return 'I don\'t see a matching medication on your list. Choose the '
          'medication and date from your schedule; I won\'t record a guess.';
    }
    pendingMissedMeds = candidates;
    pendingMissedDate = dateKey;
    suggestedMedIds = named.length == 1
        ? [named.single.id]
        : candidates.length == 1
        ? [candidates.single.id]
        : [];
    final dateLabel = lower.contains('yesterday') ? 'yesterday' : 'today';
    return 'I can mark this as missed for $dateLabel. Select the medication(s) '
        'below and confirm. This will not mark them as taken. For advice about '
        'a missed dose, ask your doctor or pharmacist; I can\'t advise doubling up.';
  }

  /// Call ONLY from the Yes button on the confirm card.
  String confirmPending({required List<String> selectedMedIds}) {
    if (pendingProposal != null) {
      final p = pendingProposal!;
      if (selectedMedIds.isEmpty) {
        return 'Select at least one medication first.';
      }
      tools.confirmLogDose(p, selectedMedIds);
      pendingProposal = null;
      const done = 'Your selected medication(s) are checked as taken.';
      memory.add('assistant', done);
      return done;
    }
    if (pendingMissedMeds.isNotEmpty && pendingMissedDate != null) {
      if (selectedMedIds.isEmpty) {
        return 'Select at least one medication first.';
      }
      for (final med in pendingMissedMeds.where(
        (med) => selectedMedIds.contains(med.id),
      )) {
        tools.markMissed(med, pendingMissedDate!);
      }
      pendingMissedMeds = [];
      pendingMissedDate = null;
      const done =
          'Marked as missed. Ask your doctor or pharmacist what to do next.';
      memory.add('assistant', done);
      return done;
    }
    return 'Nothing to confirm.';
  }

  bool get hasPendingConfirmation =>
      pendingProposal != null || pendingMissedMeds.isNotEmpty;

  List<Med> get pendingMeds => pendingProposal?.meds ?? pendingMissedMeds;

  static bool _isTakenPhrase(String text) =>
      text.contains('took') ||
      text.contains('taken') ||
      text.contains('swallowed') ||
      text.contains('had my') ||
      text.contains('had the');

  String _medicationNames(List<String> ids) {
    if (ids.isEmpty) return 'none';
    return tools.todaysMeds
        .where((med) => ids.contains(med.id))
        .map(_displayMed)
        .join(', ');
  }

  static String _displayMed(Med med) =>
      '${med.name}${med.strength.isEmpty ? '' : ' ${med.strength}'}';
}
