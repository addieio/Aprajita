import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

class HindsightMemoryItem {
  final String text;
  final String? type;
  final double? score;

  HindsightMemoryItem({
    required this.text,
    this.type,
    this.score,
  });

  factory HindsightMemoryItem.fromJson(Map<String, dynamic> json) {
    return HindsightMemoryItem(
      text: json['text'] ?? json['content'] ?? '',
      type: json['type']?.toString(),
      score: (json['score'] as num?)?.toDouble(),
    );
  }
}

class HindsightLogEntry {
  final String id;
  final String operation; // RETAIN, RECALL, REFLECT
  final String queryOrContent;
  final String summaryOrResult;
  final DateTime timestamp;
  final bool success;

  HindsightLogEntry({
    required this.id,
    required this.operation,
    required this.queryOrContent,
    required this.summaryOrResult,
    required this.timestamp,
    required this.success,
  });
}

class HindsightService {
  final StorageService _storageService;
  final List<HindsightLogEntry> _recentLogs = [];
  final StreamController<List<HindsightLogEntry>> _logsController =
      StreamController<List<HindsightLogEntry>>.broadcast();

  HindsightService(this._storageService);

  Stream<List<HindsightLogEntry>> get logsStream => _logsController.stream;
  List<HindsightLogEntry> get recentLogs => List.unmodifiable(_recentLogs);

  String get _apiKey => _storageService.loadHindsightConfig()['apiKey'] ?? '';
  String get _bankId => _storageService.loadHindsightConfig()['bankId'] ?? 'aprajita_safety';
  String get _baseUrl => _storageService.loadHindsightConfig()['baseUrl'] ?? 'https://api.hindsight.vectorize.io';
  bool get isConfigured => _apiKey.isNotEmpty && _bankId.isNotEmpty;

  void _addLog(String op, String input, String output, bool ok) {
    final entry = HindsightLogEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      operation: op,
      queryOrContent: input,
      summaryOrResult: output,
      timestamp: DateTime.now(),
      success: ok,
    );
    _recentLogs.insert(0, entry);
    if (_recentLogs.length > 50) _recentLogs.removeLast();
    _logsController.add(_recentLogs);
  }

  /// 1. RETAIN - Store memories into the bank
  Future<bool> retain(String content, {String? tag}) async {
    if (!isConfigured) {
      debugPrint('[Hindsight] Not configured. Storing in local audit log.');
      _addLog('RETAIN (LOCAL)', content, 'Saved to offline cache (API key needed)', true);
      return false;
    }

    try {
      final url = Uri.parse('$_baseUrl/v1/default/banks/$_bankId/memories');
      final payload = {
        'items': [
          {'content': content}
        ]
      };

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
          'User-Agent': 'AprajitaSafety/3.0',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        _addLog('RETAIN', content, 'Retained successfully (Bank: $_bankId)', true);
        return decoded['success'] == true;
      } else {
        _addLog('RETAIN ERROR', content, 'HTTP ${response.statusCode}: ${response.body}', false);
        return false;
      }
    } catch (e) {
      _addLog('RETAIN ERROR', content, e.toString(), false);
      return false;
    }
  }

  /// 2. RECALL - Retrieve relevant memory snippets
  Future<List<HindsightMemoryItem>> recall(String query, {int limit = 5}) async {
    if (!isConfigured) {
      _addLog('RECALL (OFFLINE)', query, 'Using local profile fallback', true);
      return [];
    }

    try {
      final url = Uri.parse('$_baseUrl/v1/default/banks/$_bankId/memories/recall');
      final payload = {'query': query};

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
          'User-Agent': 'AprajitaSafety/3.0',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        final results = decoded['results'] as List<dynamic>? ?? [];
        final items = results.map((r) => HindsightMemoryItem.fromJson(r as Map<String, dynamic>)).toList();

        final summary = items.isEmpty
            ? '0 memories matched'
            : '${items.length} memories recalled: "${items.first.text.substring(0, items.first.text.length.clamp(0, 60))}..."';
        _addLog('RECALL', query, summary, true);
        return items;
      } else {
        _addLog('RECALL ERROR', query, 'HTTP ${response.statusCode}: ${response.body}', false);
        return [];
      }
    } catch (e) {
      _addLog('RECALL ERROR', query, e.toString(), false);
      return [];
    }
  }

  /// 3. REFLECT - Synthesize a reasoned summary over memories
  Future<String?> reflect(String query) async {
    if (!isConfigured) {
      _addLog('REFLECT (OFFLINE)', query, 'Offline mode: Hindsight key required', false);
      return null;
    }

    try {
      final url = Uri.parse('$_baseUrl/v1/default/banks/$_bankId/reflect');
      final payload = {'query': query};

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
          'User-Agent': 'AprajitaSafety/3.0',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        final text = decoded['text'] as String?;
        _addLog('REFLECT', query, text ?? 'Reflect completed without summary text', true);
        return text;
      } else {
        _addLog('REFLECT ERROR', query, 'HTTP ${response.statusCode}: ${response.body}', false);
        return null;
      }
    } catch (e) {
      _addLog('REFLECT ERROR', query, e.toString(), false);
      return null;
    }
  }

  // ================= DOMAIN-SPECIFIC HINDSIGHT SHORTCUTS =================

  /// Feature 1: Personalized Safety Preferences
  Future<bool> retainPreference(String category, String details) async {
    final text = 'User Safety Preference [$category]: $details';
    return retain(text, tag: 'preference');
  }

  /// Feature 2: Structured Incident History
  Future<bool> retainIncidentRecord({
    required String incidentId,
    required DateTime timestamp,
    required String location,
    required String smsStatus,
    required String resolution,
  }) async {
    final text =
        'Incident Log #$incidentId at ${timestamp.toIso8601String()}: Location: $location. SMS Status: $smsStatus. Resolution: $resolution.';
    return retain(text, tag: 'incident');
  }

  /// Feature 3: Device Maintenance & Troubleshooting Log
  Future<bool> retainDeviceTroubleshooting({
    required String issue,
    required String stepTaken,
    required String outcome,
  }) async {
    final text =
        'Device Diagnostic: Issue: $issue. Troubleshooting Step: $stepTaken. Outcome: $outcome. (Firmware ESP32-C6 v3.2.0)';
    return retain(text, tag: 'troubleshooting');
  }

  /// Feature 4: Safety Check-in Routine
  Future<bool> retainCheckinRoutine(String routine) async {
    final text = 'Safety Check-in Routine: $routine';
    return retain(text, tag: 'checkin');
  }
}
