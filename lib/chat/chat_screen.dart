import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app_tools.dart';
import 'chat_agent.dart';
import 'chat_repository.dart';
import 'meta_model_client.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FlutterTts _tts = FlutterTts();
  final Set<String> _selectedMedIds = {};
  final List<Map<String, dynamic>> _messages = [];
  late final String _patientName;
  late final ChatAgent _agent;

  Box get _medications => Hive.box('medications');
  Box get _chatMessages => Hive.box('chat_messages');

  @override
  void initState() {
    super.initState();
    _patientName = Hive.box(
      'profile',
    ).get('accountName', defaultValue: '').toString();
    _loadConversation();
    _agent = _createAgent();
    if (_messages.isEmpty) {
      _storeMessage(
        'assistant',
        'I can check your medication list and record a dose after you confirm it.',
      );
    }
  }

  ChatAgent _createAgent() {
    final today = _dateKey(DateTime.now());
    final meds = <Med>[];
    final loggedIds = <String>[];
    final rows = _medications.toMap().entries;
    for (final entry in rows) {
      final data = Map<String, String>.from(entry.value as Map);
      final assignedPatient = data['patientName'];
      if (assignedPatient != null &&
          assignedPatient.isNotEmpty &&
          assignedPatient != _patientName) {
        continue;
      }
      final id = entry.key.toString();
      final amount = int.tryParse(data['doseAmount'] ?? '') ?? 1;
      final checked = data['checkedDate'] == today
          ? (data['checkedDoses'] ?? '')
                .split(',')
                .where((value) => value.isNotEmpty)
                .toSet()
          : <String>{};
      if (List.generate(amount, (index) => '$index').every(checked.contains)) {
        loggedIds.add(id);
      }
      final history = _decodeMap(data['doseHistory']);
      final takenDates = <String>{
        for (final item in history.entries)
          if ((item.value as num?)?.toInt() == amount) item.key,
      };
      if (data['checkedDate'] != null &&
          data['checkedDate']!.isNotEmpty &&
          checked.length >= amount) {
        takenDates.add(data['checkedDate']!);
      }
      final missedHistory = _decodeMap(data['missedDoses']);
      final missedDates = missedHistory.entries
          .where(
            (item) => item.value is List && (item.value as List).isNotEmpty,
          )
          .map((item) => item.key)
          .toList();
      final reminderHour = int.tryParse(data['reminderHour'] ?? '') ?? 8;
      meds.add(
        Med(
          id,
          data['name'] ?? 'Medication',
          data['strength']?.isNotEmpty == true
              ? data['strength']!
              : data['dosage'] ?? '',
          reminderHour >= 17 ? 'night' : 'morning',
          today,
          takenDates: takenDates.toList(),
          missedDates: missedDates,
        ),
      );
    }

    const llmProvider = String.fromEnvironment(
      'MEDSAFE_AI_PROVIDER',
      defaultValue: 'nvidia',
    );
    const llmBaseUrl = String.fromEnvironment(
      'MEDSAFE_AI_BASE_URL',
      defaultValue: 'https://integrate.api.nvidia.com/v1',
    );
    const llmModel = String.fromEnvironment(
      'MEDSAFE_AI_MODEL',
      defaultValue: 'nvidia/nemotron-3.5-lightning-30b-a3b',
    );
    const llmApiKey = String.fromEnvironment(
      'MEDSAFE_AI_API_KEY',
      defaultValue: '',
    );

    final llm = switch (llmProvider.toLowerCase()) {
      'google' || 'googleai' || 'gemini' =>
        llmApiKey.isEmpty
            ? const UnavailableLlmClient('Google')
            : GoogleAiStudioClient(apiKey: llmApiKey, model: llmModel),
      'nvidia' || 'nim' =>
        llmApiKey.isEmpty
            ? const UnavailableLlmClient('NVIDIA')
            : HttpLlmClient(
                baseUrl: llmBaseUrl,
                model: llmModel,
                apiKey: llmApiKey,
              ),
      _ => const UnavailableLlmClient('Configured'),
    };

    return ChatAgent(
      tools: AppTools(
        todaysMeds: meds,
        loggedMedIds: loggedIds,
        onLogDose: _recordTaken,
        onMarkMissed: _recordMissed,
      ),
      memory: ChatRepository(),
      llm: llm,
    );
  }

  static Map<String, dynamic> _decodeMap(String? value) {
    if (value == null || value.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(value) as Map);
    } catch (_) {
      return {};
    }
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  void _loadConversation() {
    final rows =
        _chatMessages.values
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .where((row) => row['patientName'] == _patientName)
            .toList()
          ..sort(
            (a, b) => (a['createdAt'] ?? '').compareTo(b['createdAt'] ?? ''),
          );
    _messages.addAll(rows);
  }

  void _storeMessage(String role, String text) {
    final row = <String, dynamic>{
      'patientName': _patientName,
      'role': role,
      'text': text,
      'createdAt': DateTime.now().toIso8601String(),
    };
    _chatMessages.add(row);
    _messages.add(row);
  }

  dynamic _keyForMed(String id) => _medications.keys.firstWhere(
    (key) => key.toString() == id,
    orElse: () => null,
  );

  void _recordTaken(Med med, String date) {
    final key = _keyForMed(med.id);
    if (key == null) return;
    final data = Map<String, String>.from(_medications.get(key) as Map);
    final amount = int.tryParse(data['doseAmount'] ?? '') ?? 1;
    final checked = data['checkedDate'] == date
        ? (data['checkedDoses'] ?? '')
              .split(',')
              .where((value) => value.isNotEmpty)
              .toSet()
        : <String>{};
    checked.addAll(List.generate(amount, (index) => '$index'));
    data['checkedDate'] = date;
    data['checkedDoses'] = checked.join(',');
    final history = _decodeMap(data['doseHistory']);
    history[date] = checked.length;
    data['doseHistory'] = jsonEncode(history);
    _medications.put(key, data);
  }

  void _recordMissed(Med med, String date) {
    final key = _keyForMed(med.id);
    if (key == null) return;
    final data = Map<String, String>.from(_medications.get(key) as Map);
    final amount = int.tryParse(data['doseAmount'] ?? '') ?? 1;
    final missed = _decodeMap(data['missedDoses']);
    final dates = List<String>.from(missed[date] ?? const <String>[]);
    dates.addAll(List.generate(amount, (index) => '$index'));
    missed[date] = dates.toSet().toList();
    data['missedDoses'] = jsonEncode(missed);
    _medications.put(key, data);
  }

  Future<void> _handleSend([String? overrideText]) async {
    final text = (overrideText ?? _controller.text).trim();
    if (text.isEmpty) return;

    try {
      final reply = await _agent.handleAsync(text);
      setState(() {
        _selectedMedIds
          ..clear()
          ..addAll(_agent.suggestedMedIds);
        _storeMessage('user', text);
        _storeMessage('assistant', reply);
      });
    } catch (_) {
      setState(() {
        _storeMessage('user', text);
        _storeMessage(
          'assistant',
          'I’m having trouble reaching the AI service right now. Please try again in a moment.',
        );
      });
    }

    _controller.clear();
    _scrollToLatest();
  }

  void _confirmSelection() {
    final reply = _agent.confirmPending(
      selectedMedIds: _selectedMedIds.toList(),
    );
    setState(() {
      _storeMessage('assistant', reply);
      _selectedMedIds.clear();
    });
    _scrollToLatest();
  }

  void _cancelProposal() {
    setState(() {
      _agent.pendingProposal = null;
      _agent.pendingMissedMeds = [];
      _agent.pendingMissedDate = null;
      _selectedMedIds.clear();
      _storeMessage('assistant', 'Okay. Nothing was recorded.');
    });
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _speak(String text) async {
    if (Hive.box('profile').get('ttsEnabled', defaultValue: false) != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enable read-aloud in your profile first.'),
        ),
      );
      return;
    }
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.speak(text);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendingMeds = _agent.pendingMeds;
    return Scaffold(
      appBar: AppBar(title: const Text('Medication chat')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  final isUser = message['role'] == 'user';
                  return Align(
                    alignment: isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.82,
                      ),
                      decoration: BoxDecoration(
                        color: isUser
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible(
                            child: Text(
                              message['text']?.toString() ?? '',
                              style: TextStyle(
                                color: isUser
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : null,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          if (!isUser) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Read aloud',
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(
                                width: 36,
                                height: 36,
                              ),
                              onPressed: () =>
                                  _speak(message['text']?.toString() ?? ''),
                              icon: const Icon(
                                Icons.volume_up_outlined,
                                size: 19,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_agent.hasPendingConfirmation)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _agent.pendingProposal != null
                          ? 'Confirm medicines taken'
                          : 'Confirm missed medicines',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    ...pendingMeds.map(
                      (med) => CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text('${med.name} ${med.strength}'.trim()),
                        value: _selectedMedIds.contains(med.id),
                        onChanged: (selected) => setState(() {
                          if (selected == true) {
                            _selectedMedIds.add(med.id);
                          } else {
                            _selectedMedIds.remove(med.id);
                          }
                        }),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _cancelProposal,
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _selectedMedIds.isEmpty
                                ? null
                                : _confirmSelection,
                            icon: const Icon(Icons.check),
                            label: const Text('Confirm'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      decoration: const InputDecoration(
                        hintText: 'Ask about your medication list',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _handleSend(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send message',
                    onPressed: _agent.hasPendingConfirmation
                        ? null
                        : () => _handleSend(),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
