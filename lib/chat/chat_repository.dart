/// Local memory — the "memory in the app itself".
/// In the real app, back this with Room (chat_messages, memory_facts).
/// This in-memory version has the same API so the agent code is identical.
class ChatMessage {
  final String role; // user | assistant
  final String text;
  final DateTime at;
  ChatMessage(this.role, this.text) : at = DateTime.now();
}

class ChatRepository {
  final List<ChatMessage> messages = [];
  final Map<String, String> facts = {}; // confirmed facts only

  void add(String role, String text) => messages.add(ChatMessage(role, text));

  /// Rolling summary rebuilt from DB facts, not from chat vibes.
  String summary(List<String> takenToday, List<String> missed) =>
      'Taken today: ${takenToday.isEmpty ? "none yet" : takenToday.join(", ")}; '
      'Missed: ${missed.isEmpty ? "none" : missed.join(", ")};';
}
