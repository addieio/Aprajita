import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'hindsight_service.dart';
import 'storage_service.dart';

class GroqService {
  final StorageService _storageService;
  final HindsightService _hindsightService;

  GroqService(this._storageService, this._hindsightService);

  String get _apiKey => _storageService.loadGroqConfig()['apiKey'] ?? '';
  String get _model => _storageService.loadGroqConfig()['model'] ?? 'openai/gpt-oss-120b';
  bool get isConfigured => _apiKey.isNotEmpty;

  /// General completion with injected memory context
  Future<String> chat({
    required String systemPrompt,
    required String userMessage,
    List<HindsightMemoryItem>? recalledMemories,
    String? reflectedSummary,
  }) async {
    if (!isConfigured) {
      return 'Groq API Key not configured. Please enter your key in Settings.';
    }

    try {
      final url = Uri.parse('https://api.groq.com/openai/v1/chat/completions');

      final memoryBuffer = StringBuffer();
      if (reflectedSummary != null && reflectedSummary.isNotEmpty) {
        memoryBuffer.writeln('\n[HINDSIGHT REFLECTED MEMORY SUMMARY]:');
        memoryBuffer.writeln(reflectedSummary);
      }
      if (recalledMemories != null && recalledMemories.isNotEmpty) {
        memoryBuffer.writeln('\n[HINDSIGHT RECALLED MEMORIES]:');
        for (var i = 0; i < recalledMemories.length; i++) {
          memoryBuffer.writeln('${i + 1}. ${recalledMemories[i].text}');
        }
      }

      final fullSystemPrompt = '''
$systemPrompt

$memoryBuffer

Strict Memory Grounding & Safety Watch Instructions:
- You are strictly grounded in the Hindsight vector memories provided above.
- If the user asks about check-in intervals, contacts, or escalation rules, quote the exact values from their saved memory bank.
- If the user recently changed or updated a preference (e.g. 20 minutes, 10 seconds), always use the updated value.
- If the user asks who to call if they do not respond to a check-in, state clearly: "According to your Hindsight safety protocol, if you do not respond to a check-in, I will immediately escalate and contact your designated emergency contact with your live GPS location."
- SAFETY WATCH / CHECK-IN INSTRUCTION: If the user asks you to check on them, remind them, or set a check-in timer (e.g. "check on me in 10 seconds", "check in after 5 mins", "remind me in 20 mins"), NEVER say you cannot set timers. The mobile app has already armed the live Safety Watch timer. Confirm that their Safety Watch is armed, and reassure them that when the time arrives, an urgent full-screen check-in modal will flash across their screen asking: "ARE YOU OKAY? Any troubles?". If they don't confirm safety within 15 seconds, explain that you will automatically escalate to their designated emergency contacts with their live GPS location.
- Be concise, direct, supportive, and professional. Always cite: "According to your Hindsight memory bank..." or "Per your saved safety protocol...".
''';

      final payload = {
        'model': _model,
        'messages': [
          {'role': 'system', 'content': fullSystemPrompt},
          {'role': 'user', 'content': userMessage},
        ],
        'temperature': 0.3,
        'max_tokens': 600,
      };

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        return decoded['choices'][0]['message']['content']?.toString().trim() ?? 'No response received.';
      } else {
        debugPrint('[Groq] Error ${response.statusCode}: ${response.body}');
        return 'AI Error (${response.statusCode}): ${response.body}';
      }
    } catch (e) {
      debugPrint('[Groq] Request failed: $e');
      return 'Failed to reach AI service: $e';
    }
  }

  // ================= 5 HACKATHON FEATURE HANDLERS =================

  /// FEATURE 1: Personalized AI Safety Companion
  Future<String> askSafetyCompanion(String question) async {
    final memories = await _hindsightService.recall(question, limit: 4);

    return chat(
      systemPrompt:
          'You are Aprajita, an intelligent personal safety companion for Aditya. You remember the user\'s safety preferences, check-in intervals, and solo travel habits. '
          'If the user tells you to check on them in any time interval, acknowledge that their Safety Watch is active and an urgent "ARE YOU OKAY? Any troubles?" alert will flash on their screen.',
      userMessage: question,
      recalledMemories: memories,
    );
  }

  /// FEATURE 2: AI-Powered Incident History Explainer
  Future<String> explainIncidentHistory(String question) async {
    final memories = await _hindsightService.recall('Incident log SOS alert GPS status $question', limit: 5);

    return chat(
      systemPrompt:
          'You are an Incident Review Analyst for personal safety alerts. Synthesize factual incident timelines from verified Hindsight memory logs.',
      userMessage: question,
      recalledMemories: memories,
    );
  }

  /// FEATURE 3: Device Troubleshooting Assistant (Using Retain + Recall + Reflect)
  Future<String> troubleshootDevice(String issueDescription) async {
    // 1. Reflect on past troubleshooting to avoid repeating identical suggestions
    final reflection = await _hindsightService.reflect('Troubleshooting and diagnostic history for $issueDescription');
    // 2. Recall specific error snippets
    final memories = await _hindsightService.recall('Device Diagnostic $issueDescription', limit: 4);

    final answer = await chat(
      systemPrompt:
          'You are a Hardware Support Specialist for the Aprajita ESP32-C6 Emotion Keychain and Aprajita Companion app. '
          'Use the reflected past maintenance history to avoid recommending troubleshooting steps that already failed or were previously completed.',
      userMessage: issueDescription,
      recalledMemories: memories,
      reflectedSummary: reflection,
    );

    // Save this troubleshooting interaction for future learning
    await _hindsightService.retainDeviceTroubleshooting(
      issue: issueDescription,
      stepTaken: 'Analyzed with AI support assistant',
      outcome: 'Guided user with memory-grounded steps',
    );

    return answer;
  }

  /// FEATURE 4: Smarter Safety Check-ins
  Future<String> evaluateCheckinStatus({required String routine, required bool isMissed}) async {
    final memories = await _hindsightService.recall('Safety Check-in Routine preference $routine', limit: 3);

    final prompt = isMissed
        ? 'The user missed their scheduled safety check-in for "$routine". Formulate a respectful, urgent, tailored notification asking them to confirm arrival, citing their preferred grace period.'
        : 'The user just confirmed safe arrival for "$routine". Acknowledge cleanly and update their safety streak.';

    return chat(
      systemPrompt:
          'You are an intelligent safety check-in coordinator that adapts reminders to user habits.',
      userMessage: prompt,
      recalledMemories: memories,
    );
  }

  /// FEATURE 5: Responder Incident Briefing
  Future<String> generateResponderBriefing({
    required String activeLocation,
    required String timestamp,
    required String hardwareBattery,
    required String contactStatus,
  }) async {
    // Context from Hindsight
    final memories = await _hindsightService.recall('User medical profile emergency contacts allergies', limit: 4);

    final message = '''
GENERATE RESPONDER BRIEFING:
- Current Location: $activeLocation
- Alert Timestamp: $timestamp
- Hardware Telemetry: Battery $hardwareBattery, MPU-6050 fall confirmed
- Communication Status: $contactStatus
''';

    return chat(
      systemPrompt:
          'You are a Certified Emergency Dispatcher. Generate a high-priority, strictly structured incident briefing for authorized responders (Police / Campus Security / Paramedics). Include critical medical hazards, location history, and immediate tactical recommendations.',
      userMessage: message,
      recalledMemories: memories,
    );
  }
}
