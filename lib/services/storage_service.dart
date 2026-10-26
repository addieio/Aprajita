import 'dart:async';
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
  final StreamController<List<TrustedContact>> _contactsStreamController =
      StreamController<List<TrustedContact>>.broadcast();

  StorageService(this._prefs);

  Stream<List<TrustedContact>> get contactsStream => _contactsStreamController.stream;

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  // --- CONTACTS ---
  List<TrustedContact> loadContacts() {
    final raw = _prefs.getString(_keyContacts);
    if (raw == null) {
      // First launch: pre-load clean default emergency contacts
      return [
        TrustedContact(
          id: 'contact-primary-default',
          name: 'Primary Contact',
          phone: '+919876543210',
          isEmergencyRecipient: true,
          isPrimary: true,
          syncedToKeychain: true,
        ),
        TrustedContact(
          id: 'contact-secondary-default',
          name: 'Secondary Contact',
          phone: '+919876543211',
          isEmergencyRecipient: true,
          isPrimary: false,
          syncedToKeychain: true,
        ),
      ];
    }

    if (raw.trim().isEmpty || raw.trim() == '[]') {
      return [];
    }

    try {
      final List<dynamic> list = jsonDecode(raw);
      return list.map((e) => TrustedContact.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveContacts(List<TrustedContact> contacts) async {
    final raw = jsonEncode(contacts.map((c) => c.toJson()).toList());
    await _prefs.setString(_keyContacts, raw);

    // Keep primary contact ID valid
    final currentPrimaryId = getPrimaryContactId();
    if (contacts.isEmpty) {
      await _prefs.setString(_keyPrimaryContactId, '');
    } else if (currentPrimaryId != null &&
        currentPrimaryId.isNotEmpty &&
        !contacts.any((c) => c.id == currentPrimaryId)) {
      // Current primary was deleted, pick the first remaining contact
      await _prefs.setString(_keyPrimaryContactId, contacts.first.id);
    } else if (currentPrimaryId == null || currentPrimaryId.isEmpty) {
      final primary = contacts.firstWhere(
        (c) => c.isPrimary,
        orElse: () => contacts.first,
      );
      await _prefs.setString(_keyPrimaryContactId, primary.id);
    }

    _contactsStreamController.add(contacts);
  }

  Future<void> addContact(TrustedContact contact) async {
    final list = loadContacts();
    final index = list.indexWhere((c) => c.id == contact.id);
    if (index >= 0) {
      list[index] = contact;
    } else {
      list.add(contact);
    }
    await saveContacts(list);
  }

  Future<void> updateContact(TrustedContact contact) async {
    final list = loadContacts();
    final index = list.indexWhere((c) => c.id == contact.id);
    if (index >= 0) {
      list[index] = contact;
    } else {
      list.add(contact);
    }
    await saveContacts(list);
  }

  Future<void> deleteContact(String contactId) async {
    final list = loadContacts();
    final updated = list.where((c) => c.id != contactId).toList();
    await saveContacts(updated);
  }

  // --- PRIMARY CONTACT SELECTOR ---
  String? getPrimaryContactId() {
    return _prefs.getString(_keyPrimaryContactId);
  }

  Future<void> setPrimaryContactId(String id) async {
    await _prefs.setString(_keyPrimaryContactId, id);
    _contactsStreamController.add(loadContacts());
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
        'whatsappFrom': '',
        'enabled': 'false',
      };
    }
    try {
      final map = Map<String, String>.from(jsonDecode(raw));
      return map;
    } catch (_) {
      return {
        'phoneNo': '',
        'accountSid': '',
        'authToken': '',
        'whatsappFrom': '',
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
      return {
        'url': '',
        'anonKey': '',
        'enabled': 'false',
      };
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

  // --- HINDSIGHT CONFIG ---
  static const String _keyHindsightConfig = 'aprajita_hindsight_config_v2';
  Map<String, String> loadHindsightConfig() {
    final raw = _prefs.getString(_keyHindsightConfig);
    if (raw == null || raw.isEmpty) {
      return {
        'apiKey': '',
        'bankId': 'aprajita_safety',
        'baseUrl': 'https://api.hindsight.vectorize.io',
        'enabled': 'false',
      };
    }
    try {
      return Map<String, String>.from(jsonDecode(raw));
    } catch (_) {
      return {
        'apiKey': '',
        'bankId': 'aprajita_safety',
        'baseUrl': 'https://api.hindsight.vectorize.io',
        'enabled': 'false',
      };
    }
  }

  Future<void> saveHindsightConfig({
    required String apiKey,
    required String bankId,
    String baseUrl = 'https://api.hindsight.vectorize.io',
    bool enabled = true,
  }) async {
    final map = {
      'apiKey': apiKey.trim(),
      'bankId': bankId.trim(),
      'baseUrl': baseUrl.trim(),
      'enabled': enabled.toString(),
    };
    await _prefs.setString(_keyHindsightConfig, jsonEncode(map));
  }

  // --- GROQ CONFIG ---
  static const String _keyGroqConfig = 'aprajita_groq_config';
  Map<String, String> loadGroqConfig() {
    final raw = _prefs.getString(_keyGroqConfig);
    if (raw == null || raw.isEmpty) {
      return {
        'apiKey': '',
        'model': 'openai/gpt-oss-120b',
        'enabled': 'false',
      };
    }
    try {
      return Map<String, String>.from(jsonDecode(raw));
    } catch (_) {
      return {
        'apiKey': '',
        'model': 'openai/gpt-oss-120b',
        'enabled': 'false',
      };
    }
  }

  Future<void> saveGroqConfig({
    required String apiKey,
    String model = 'openai/gpt-oss-120b',
    bool enabled = true,
  }) async {
    final map = {
      'apiKey': apiKey.trim(),
      'model': model.trim(),
      'enabled': enabled.toString(),
    };
    await _prefs.setString(_keyGroqConfig, jsonEncode(map));
  }

  // --- CUSTOM GIF / ANIMATION CONFIG ---
  static const String _keyGifPreset = 'aprajita_gif_preset';
  static const String _keyGifFps = 'aprajita_gif_fps';
  static const String _keyGifClockFormat24 = 'aprajita_gif_clock24';
  static const String _keyGifShowBattery = 'aprajita_gif_show_battery';

  String getCustomGifPreset() {
    return _prefs.getString(_keyGifPreset) ?? 'aprajita_happy';
  }

  Future<void> setCustomGifPreset(String preset) async {
    await _prefs.setString(_keyGifPreset, preset);
  }

  int getCustomGifFps() {
    return _prefs.getInt(_keyGifFps) ?? 10;
  }

  Future<void> setCustomGifFps(int fps) async {
    await _prefs.setInt(_keyGifFps, fps);
  }

  bool getCustomGifClock24() {
    return _prefs.getBool(_keyGifClockFormat24) ?? true;
  }

  Future<void> setCustomGifClock24(bool is24) async {
    await _prefs.setBool(_keyGifClockFormat24, is24);
  }

  bool getCustomGifShowBattery() {
    return _prefs.getBool(_keyGifShowBattery) ?? true;
  }

  Future<void> setCustomGifShowBattery(bool show) async {
    await _prefs.setBool(_keyGifShowBattery, show);
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
