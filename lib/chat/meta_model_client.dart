import 'dart:convert';
import 'package:http/http.dart' as http;

/// LLM is for PHRASING ONLY. It never writes to the log.
/// It must return either a clarifying question or a tool proposal.
/// The app validates the proposal, shows a confirm card, and only
/// writes after the patient taps Yes.
abstract class LlmClient {
  Future<String> reply(String userText, String factsContext);
}

/// Ship this first. No key, no network, no hallucinated logs.
class ScriptedClient implements LlmClient {
  @override
  Future<String> reply(String userText, String factsContext) async =>
  'I can help you review your medication schedule, doses, and reminders. '
  'Tell me what you need help with, and I will not record changes without '
  'your confirmation.';
}

class UnavailableLlmClient implements LlmClient {
  final String provider;

  const UnavailableLlmClient(this.provider);

  @override
  Future<String> reply(String userText, String factsContext) async =>
      '$provider AI is not configured in this phone build. Reinstall or run '
      'the app with the provider API key; no medication changes were recorded.';
}

class GoogleAiStudioClient implements LlmClient {
  final String apiKey;
  final String model;
  final http.Client _httpClient;

  GoogleAiStudioClient({
    required this.apiKey,
    this.model = 'gemini-2.0-flash',
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  static String parseResponseBody(Map<String, dynamic> body) {
    final candidates = body['candidates'] as List<dynamic>? ?? const [];
    if (candidates.isEmpty) {
      throw Exception('Google AI Studio returned no candidates.');
    }
    final parts = candidates.first['content']?['parts'] as List<dynamic>? ?? const [];
    if (parts.isEmpty) {
      throw Exception('Google AI Studio returned no text in the response.');
    }
    final text = parts.first['text'];
    if (text is! String || text.trim().isEmpty) {
      throw Exception('Google AI Studio returned empty text.');
    }
    return text;
  }

  @override
  Future<String> reply(String userText, String factsContext) async {
    final systemPrompt =
        'You are a medication-tracking assistant inside an app. '
        'Only use the medication facts provided. Never invent a '
        'dose, time, or medication. Never advise changing a dose. '
        'For a missed dose, say to ask their doctor or pharmacist. '
        'Return either a clarifying question or a concise safety-first answer; '
        'never claim you logged anything.';

    final payload = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': systemPrompt},
        ],
      },
      'contents': [
        {
          'parts': [
            {'text': 'Facts:\n$factsContext\n\nPatient: $userText'},
          ],
        },
      ],
    });

    final uri = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$model:generateContent',
      {'key': apiKey},
    );
    late http.Response res;
    for (var attempt = 0; ; attempt++) {
      res = await _httpClient.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: payload,
      );
      if (res.statusCode != 503 || attempt >= 2) break;
      await Future<void>.delayed(Duration(seconds: attempt + 1));
    }

    if (res.statusCode != 200) {
      final bodyText = res.body.trim();
      final summary = bodyText.isEmpty ? 'No response body.' : bodyText;
      throw Exception(
        'Google AI Studio call failed with status ${res.statusCode}. '
        'Check the API key, model, and quota. Details: $summary',
      );
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return parseResponseBody(body);
  }
}

/// Optional second brain: Meta Model API (dev.meta.ai) or another LLM API.
/// DO NOT hardcode an endpoint / model name from a tutorial — read the
/// current dev.meta.ai docs for the live endpoint, model name, and auth,
/// and pass them in via build config / secure storage.
class HttpLlmClient implements LlmClient {
  final String baseUrl; // e.g. from build config — verify in dev.meta.ai docs
  final String model;
  final String apiKey;
  HttpLlmClient({required this.baseUrl, required this.model, required this.apiKey});

  @override
  Future<String> reply(String userText, String factsContext) async {
    final res = await http.post(
      Uri.parse('$baseUrl/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'messages': [
          {
            'role': 'system',
            'content':
                'You are a medication-tracking assistant inside an app. '
                'Only use the medication facts provided. Never invent a '
                'dose, time, or medication. Never advise changing a dose. '
                'For a missed dose, say to ask their doctor or pharmacist. '
                'Return either a clarifying question or a JSON tool '
                'proposal; never claim you logged anything.'
          },
          {'role': 'user', 'content': 'Facts:\n$factsContext\n\nPatient: $userText'},
        ],
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('LLM call failed: ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['choices'] as List).first['message']['content'] as String;
  }
}
