import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medsafe/chat/app_tools.dart';
import 'package:medsafe/chat/chat_agent.dart';
import 'package:medsafe/chat/chat_repository.dart';
import 'package:medsafe/chat/meta_model_client.dart';

class FakeLlmClient implements LlmClient {
  String? lastUserText;
  String? lastFactsContext;
  final List<String> contexts = [];
  final List<String> replies;

  FakeLlmClient({this.replies = const []});

  @override
  Future<String> reply(String userText, String factsContext) async {
    lastUserText = userText;
    lastFactsContext = factsContext;
    contexts.add(factsContext);
    return replies.isEmpty
        ? 'LLM guidance: follow the medication schedule and ask your clinician before changing anything.'
        : replies[contexts.length - 1];
  }
}

ChatAgent agent() {
  final tools = AppTools(
    todaysMeds: const [
      Med('1', 'Metformin', '500 mg', 'morning', '2026-10-18'),
      Med('2', 'Atorvastatin', '10 mg', 'night', '2026-10-18'),
    ],
    loggedMedIds: const [],
  );
  return ChatAgent(
    tools: tools,
    memory: ChatRepository(),
    llm: ScriptedClient(),
  );
}

void main() {
  test('"I took the two medications today" asks for confirm, logs nothing', () {
    final a = agent();
    final reply = a.handle('I took the two medications today');
    expect(a.tools.logged, isEmpty);
    expect(reply, contains('Metformin'));
    expect(
      a.confirmPending(selectedMedIds: ['1', '2']),
      contains('checked as taken'),
    );
    expect(a.tools.logged, ['1', '2']);
  });

  test('"I forgot yesterday night\'s dose" marks missed, never taken', () {
    final a = agent();
    final reply = a.handle("I forgot yesterday night's dose");
    expect(reply, contains('mark'));
    expect(reply, contains('missed'));
    expect(
      a.confirmPending(selectedMedIds: ['2']),
      contains('Marked as missed'),
    );
    expect(a.tools.missed, ['2']);
    expect(a.tools.logged, isEmpty);
  });

  test('confirmation writes only the medication selected by the patient', () {
    final a = agent();
    a.handle('I took my medicines');
    expect(
      a.confirmPending(selectedMedIds: ['1']),
      contains('checked as taken'),
    );
    expect(a.tools.logged, ['1']);
  });

  test('symptom reports never create a dose proposal', () {
    final a = agent();
    final reply = a.handle('I feel dizzy after taking my medicine');
    expect(reply, contains('doctor or pharmacist'));
    expect(a.pendingProposal, isNull);
    expect(a.tools.logged, isEmpty);
  });

  test('generic questions route through the configured LLM client', () async {
    final llm = FakeLlmClient();
    final a = ChatAgent(
      tools: AppTools(
        todaysMeds: const [
          Med('1', 'Metformin', '500 mg', 'morning', '2026-10-18'),
        ],
        loggedMedIds: const [],
      ),
      memory: ChatRepository(),
      llm: llm,
    );

    final reply = await a.handleAsync('Can you explain my schedule?');

    expect(reply, contains('LLM guidance'));
    expect(llm.lastUserText, 'Can you explain my schedule?');
    expect(llm.lastFactsContext, isNotEmpty);
  });

  test('scripted fallback does not expose internal conversation context', () async {
    final a = ChatAgent(
      tools: AppTools(todaysMeds: const [], loggedMedIds: const []),
      memory: ChatRepository(),
      llm: ScriptedClient(),
    );

    final reply = await a.handleAsync('hi');

    expect(reply, contains('medication schedule'));
    expect(reply, isNot(contains('user:')));
    expect(reply, isNot(contains('Recent conversation')));
  });

  test('follow-up dosage messages retain the prior medication conversation', () async {
    final llm = FakeLlmClient(
      replies: const [
        'What dosage amount and schedule should I use for prednisone?',
        'Thanks. I have the prednisone dosage details for you to review.',
      ],
    );
    final a = ChatAgent(
      tools: AppTools(todaysMeds: const [], loggedMedIds: const []),
      memory: ChatRepository(),
      llm: llm,
    );

    await a.handleAsync('I want to add prednisone.');
    final reply = await a.handleAsync('20 mg once daily');

    expect(reply, contains('prednisone dosage details'));
    expect(llm.contexts[1], contains('user: I want to add prednisone.'));
    expect(
      llm.contexts[1],
      contains('assistant: What dosage amount and schedule should I use for prednisone?'),
    );
    expect(llm.contexts[1], contains('user: 20 mg once daily'));
  });

  test('Google AI Studio response is parsed from Gemini candidate text', () {
    final parsed = GoogleAiStudioClient.parseResponseBody({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': 'Take medications as scheduled.'},
            ],
          },
        },
      ],
    });

    expect(parsed, 'Take medications as scheduled.');
  });

  test('Google AI Studio retries temporary 503 overload responses', () async {
    var requestCount = 0;
    final client = GoogleAiStudioClient(
      apiKey: 'test-key',
      httpClient: MockClient((request) async {
        requestCount++;
        if (requestCount < 2) {
          return http.Response('Service unavailable', 503);
        }
        return http.Response(
          '{"candidates":[{"content":{"parts":[{"text":"Try again shortly."}]}}]}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final response = await client.reply('Question?', 'Medication facts.');

    expect(response, 'Try again shortly.');
    expect(requestCount, 2);
  });
}
