import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/contact_model.dart';
import '../models/sos_event_model.dart';

class StorageService {
  static const String _keyContacts = 'aprajita_contacts';
  static const String _keyHistory = 'aprajita_sos_history';
  static const String _keyActiveSos = 'aprajita_active_sos';
  static const String _keyTwilioConfig = 'aprajita_twilio_config';
  static const String _keySupabaseConfig = 'aprajita_supabase_config';
  static const String _keyOfflineQueue = 'aprajita_offline_queue';
  static const String _keySosCountdown = 'aprajita_sos_countdown_sec';
  static const String _keyPrimaryContactId = 'aprajita_primary_contact_id';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  // --- CONTACTS ---
  List<TrustedContact> loadContacts() {
    final raw = _prefs.getString(_keyContacts);
    final defaultContact = TrustedContact(
      id: 'contact-primary-default',
      name: 'Primary Contact',
      phone: '+91 98765 43210',
      isEmergencyRecipient: true,
      isPrimary: true,
      syncedToKeychain: false,
    );

    if (raw == null || raw.isEmpty) {
      return [defaultContact];
    }
    try {
      final List<dynamic> list = jsonDecode(raw);
      final contacts = list.map((e) => TrustedContact.fromJson(e)).toList();
      if (contacts.isEmpty) {
        return [defaultContact];
      }
      return contacts;
    } catch (_) {
      return [defaultContact];
    }
  }

  Future<void> saveContacts(List<TrustedContact> contacts) async {
    final raw = jsonEncode(contacts.map((c) => c.toJson()).toList());
    await _prefs.setString(_keyContacts, raw);
  }

  // --- PRIMARY CONTACT SELECTOR ---
  String? getPrimaryContactId() {
    return _prefs.getString(_keyPrimaryContactId);
  }

  Future<void> setPrimaryContactId(String id) async {
    await _prefs.setString(_keyPrimaryContactId, id);
  }

  // --- SOS HISTORY ---
  List<SosAlertEvent> loadHistory() {
    final raw = _prefs.getString(_keyHistory);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List<dynamic> list = jsonDecode(raw);
      return list.map((e) => SosAlertEvent.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveHistory(List<SosAlertEvent> history) async {
    final raw = jsonEncode(history.map((h) => h.toJson()).toList());
    await _prefs.setString(_keyHistory, raw);
  }

  Future<void> addHistoryItem(SosAlertEvent event) async {
    final list = loadHistory();
    list.insert(0, event);
    if (list.length > 50) list.removeLast(); // Keep latest 50
    await saveHistory(list);
  }

  // --- ACTIVE SOS ---
  SosAlertEvent? loadActiveSos() {
    final raw = _prefs.getString(_keyActiveSos);
    if (raw == null || raw.isEmpty) return null;
    try {
      return SosAlertEvent.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveActiveSos(SosAlertEvent? event) async {
    if (event == null) {
      await _prefs.remove(_keyActiveSos);
    } else {
      await _prefs.setString(_keyActiveSos, jsonEncode(event.toJson()));
    }
  }

  // --- TWILIO CONFIG ---
  Map<String, String> loadTwilioConfig() {
    final raw = _prefs.getString(_keyTwilioConfig);
    if (raw == null || raw.isEmpty) {
      return {
        'phoneNo': '',
        'accountSid': '',
        'authToken': '',
        'whatsappFrom': '+14155238886',
        'enabled': 'false',
      };
    }
    try {
      final map = Map<String, String>.from(jsonDecode(raw));
      map.putIfAbsent('whatsappFrom', () => '+14155238886');
      return map;
    } catch (_) {
      return {
        'phoneNo': '',
        'accountSid': '',
        'authToken': '',
        'whatsappFrom': '+14155238886',
        'enabled': 'false',
      };
    }
  }

  Future<void> saveTwilioConfig({
    required String phoneNo,
    required String accountSid,
    required String authToken,
    bool enabled = true,
  }) async {
    final map = {
      'phoneNo': phoneNo.trim(),
      'accountSid': accountSid.trim(),
      'authToken': authToken.trim(),
      'enabled': enabled.toString(),
    };
    await _prefs.setString(_keyTwilioConfig, jsonEncode(map));
  }

  // --- SUPABASE CONFIG ---
  Map<String, String> loadSupabaseConfig() {
    final raw = _prefs.getString(_keySupabaseConfig);
    if (raw == null || raw.isEmpty) {
      return {
        'url': '',
        'anonKey': '',
        'enabled': 'false',
      };
    }
    try {
      return Map<String, String>.from(jsonDecode(raw));
    } catch (_) {
      return {'url': '', 'anonKey': '', 'enabled': 'false'};
    }
  }

  Future<void> saveSupabaseConfig({
    required String url,
    required String anonKey,
    bool enabled = true,
  }) async {
    final map = {
      'url': url.trim(),
      'anonKey': anonKey.trim(),
      'enabled': enabled.toString(),
    };
    await _prefs.setString(_keySupabaseConfig, jsonEncode(map));
  }

  // --- OFFLINE QUEUE (For alerts triggered when offline) ---
  List<Map<String, dynamic>> loadOfflineQueue() {
    final raw = _prefs.getString(_keyOfflineQueue);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List<dynamic> list = jsonDecode(raw);
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> enqueueOfflineAlert(Map<String, dynamic> item) async {
    final queue = loadOfflineQueue();
    queue.add(item);
    await _prefs.setString(_keyOfflineQueue, jsonEncode(queue));
  }

  Future<void> clearOfflineQueue() async {
    await _prefs.remove(_keyOfflineQueue);
  }

  // --- COUNTDOWN DURATION ---
  int getSosCountdownSeconds() {
    return _prefs.getInt(_keySosCountdown) ?? 5; // Default 5 seconds
  }

  Future<void> setSosCountdownSeconds(int seconds) async {
    await _prefs.setInt(_keySosCountdown, seconds);
  }

  // --- VOLUME UP 4-PRESS SOS TRIGGER ---
  bool isVolumeSosEnabled() {
    return _prefs.getBool('aprajita_volume_sos_enabled') ?? true;
  }

  Future<void> setVolumeSosEnabled(bool enabled) async {
    await _prefs.setBool('aprajita_volume_sos_enabled', enabled);
  }
}
