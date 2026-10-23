/// The ONLY way chat touches the medication log.
/// Reads are free. Writes NEVER happen without a confirm step in the UI.
class Med {
  final String id, name, strength;
  final String timeSlot; // morning | night
  final String date; // yyyy-mm-dd
  final List<String> takenDates;
  final List<String> missedDates;
  const Med(
    this.id,
    this.name,
    this.strength,
    this.timeSlot,
    this.date, {
    this.takenDates = const [],
    this.missedDates = const [],
  });
}

class DoseProposal {
  final String id;
  final List<Med> meds;
  final String takenAt; // ISO time the patient says they took it
  const DoseProposal(this.id, this.meds, this.takenAt);
}

class AppTools {
  final List<Med> todaysMeds;
  final List<String> loggedMedIds; // med ids already logged today
  final void Function(Med med, String date)? onLogDose;
  final void Function(Med med, String date)? onMarkMissed;
  final List<String> missed = [];
  final List<String> logged = [];

  AppTools({
    required this.todaysMeds,
    required List<String> loggedMedIds,
    this.onLogDose,
    this.onMarkMissed,
  }) : loggedMedIds = List<String>.of(loggedMedIds);

  /// Read: today's schedule with taken/missed status.
  List<Med> getTodayMeds() => todaysMeds;

  List<Med> notYetLogged() =>
      todaysMeds.where((m) => !loggedMedIds.contains(m.id)).toList();

  /// Propose — writes NOTHING. UI shows this as a confirm card.
  DoseProposal proposeLogDose(List<Med> meds, String takenAt) => DoseProposal(
    'proposal-${DateTime.now().millisecondsSinceEpoch}',
    meds,
    takenAt,
  );

  /// Write — call ONLY after the patient taps Yes on the confirm card.
  void confirmLogDose(DoseProposal p, List<String> selectedMedIds) {
    final date = p.takenAt.length >= 10
        ? p.takenAt.substring(0, 10)
        : DateTime.now().toIso8601String().substring(0, 10);
    for (final med in p.meds.where((med) => selectedMedIds.contains(med.id))) {
      if (loggedMedIds.contains(med.id)) continue;
      loggedMedIds.add(med.id);
      logged.add(med.id);
      onLogDose?.call(med, date);
    }
  }

  /// Missed dose: records MISSED, never TAKEN. Flags caregiver alert.
  void markMissed(Med med, String date) {
    missed.add(med.id);
    onMarkMissed?.call(med, date);
  }
}
