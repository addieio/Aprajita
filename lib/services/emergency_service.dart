// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../models/contact_model.dart';
import '../models/location_model.dart';
import '../models/sos_event_model.dart';
import 'storage_service.dart';
import 'twilio_service.dart';
import 'location_service.dart';
import 'hardware_service.dart';
import 'nearby_community_service.dart';
import 'hindsight_service.dart';

class EmergencyService {
  final StorageService _storageService;
  final TwilioService _twilioService;
  final LocationService _locationService;
  final HardwareService _hardwareService;
  final NearbyCommunityService _nearbyService;
  final HindsightService? _hindsightService;

  SosAlertEvent? _activeEvent;
  final StreamController<SosAlertEvent?> _activeEventController =
      StreamController<SosAlertEvent?>.broadcast();

  // Countdown timer for SOS cancellation window (prevents accidental dispatch)
  Timer? _countdownTimer;
  int _countdownSecondsRemaining = 0;
  final StreamController<int> _countdownStreamController =
      StreamController<int>.broadcast();

  Stream<SosAlertEvent?> get activeEventStream =>
      _activeEventController.stream;
  Stream<int> get countdownStream => _countdownStreamController.stream;
  SosAlertEvent? get activeEvent => _activeEvent;
  bool get isSosActive => _activeEvent != null && _activeEvent!.status == 'ACTIVE';
  bool get isCountingDown => _countdownTimer != null && _countdownTimer!.isActive;

  StreamSubscription? _hwSub;

  EmergencyService({
    required StorageService storageService,
    required TwilioService twilioService,
    required LocationService locationService,
    required HardwareService hardwareService,
    required NearbyCommunityService nearbyService,
    HindsightService? hindsightService,
  })  : _storageService = storageService,
        _twilioService = twilioService,
        _locationService = locationService,
        _hardwareService = hardwareService,
        _nearbyService = nearbyService,
        _hindsightService = hindsightService {
    // When app is opened, ensure it does NOT directly open a stale SOS panel
    final pastSos = _storageService.loadActiveSos();
    if (pastSos != null) {
      final archived = pastSos.copyWith(
        status: 'RESOLVED',
        resolvedAt: DateTime.now(),
      );
      _storageService.addHistoryItem(archived);
      _storageService.saveActiveSos(null);
    }
    _activeEvent = null;

    // Listen to physical 3-press button events and hardware alerts from ESP32
    _hwSub = _hardwareService.hardwareSosStream.listen((event) {
      if (event.contains('SOS') || event.contains('TRIGGER') || event.contains('FALL')) {
        if (!isSosActive && !isCountingDown) {
          startSosCountdown(source: 'PHYSICAL_BUTTON_3PRESS');
        }
      }
    });
  }

  /// Initiates the SOS Countdown window (e.g. 5 seconds to abort accidental triggers)
  void startSosCountdown({
    String source = 'APP_SOS_BUTTON',
    bool broadcastToNearby = true,
  }) {
    if (isSosActive || isCountingDown) return;

    // Haptic burst when SOS sequence starts
    HapticFeedback.heavyImpact();

    _countdownSecondsRemaining = _storageService.getSosCountdownSeconds();
    _countdownStreamController.add(_countdownSecondsRemaining);

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _countdownSecondsRemaining--;
      _countdownStreamController.add(_countdownSecondsRemaining);

      // Distinct haptic pulse on each countdown second
      HapticFeedback.selectionClick();

      if (_countdownSecondsRemaining <= 0) {
        timer.cancel();
        _countdownTimer = null;
        // Dispatch the actual SOS alert!
        _dispatchSos(source: source, broadcastToNearby: broadcastToNearby);
      }
    });
  }

  /// Cancels the SOS before countdown completes (Accidental trigger prevention!)
  void cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _countdownSecondsRemaining = 0;
    _countdownStreamController.add(0);
    HapticFeedback.mediumImpact();
    _hardwareService.logTerminal('🛡️ SOS Countdown Aborted by User. No SMS dispatched.');
  }

  /// Dispatches all 3 emergency channels (SMS, Call, WhatsApp) immediately with 0-second delay
  Future<void> triggerInstantSos({String source = 'APP_SOS_BUTTON'}) async {
    cancelCountdown();
    await _dispatchSos(source: source, broadcastToNearby: true);
  }

  /// Dispatches the SOS immediately without waiting for countdown
  void dispatchImmediately({String source = 'IMMEDIATE_USER_TRIGGER'}) {
    triggerInstantSos(source: source);
  }

  /// Dispatches the emergency alert to contacts, Twilio SMS, WhatsApp, Phone Call, ESP32, and Nearby Community
  Future<void> _dispatchSos({
    required String source,
    required bool broadcastToNearby,
  }) async {
    // Continuous heavy haptic alert to confirm dispatch
    HapticFeedback.vibrate();

    final now = DateTime.now();

    // 1. Resolve Location instantly from cache (0 delay) or fallback
    GpsLocation loc = _locationService.currentLocation ??
        GpsLocation(
          lat: LocationService.defaultLat,
          lng: LocationService.defaultLng,
          accuracy: 12.0,
          timestamp: now,
          source: GpsSource.phoneGps,
        );
    final mapUrl = loc.googleMapsUrl;

    // Refresh phone GPS in background without blocking dispatch
    _locationService.getCurrentLocation().then((fresh) {
      _hardwareService.sendPhoneGpsToEsp32(fresh.lat, fresh.lng, fresh.accuracy);
    }).catchError((_) {});

    // 2. Select Recipient Contacts: Alert ALL contacts marked as emergency recipients
    final allContacts = _storageService.loadContacts();
    final primaryId = _storageService.getPrimaryContactId();

    List<TrustedContact> targetContacts = [];
    final emergencyContacts =
        allContacts.where((c) => c.isEmergencyRecipient).toList();

    if (emergencyContacts.isNotEmpty) {
      // Put primary contact first in dispatch queue
      if (primaryId != null && primaryId.isNotEmpty) {
        emergencyContacts.sort((a, b) {
          if (a.id == primaryId) return -1;
          if (b.id == primaryId) return 1;
          return 0;
        });
      }
      targetContacts = emergencyContacts;
    } else if (allContacts.isNotEmpty) {
      targetContacts = [allContacts.first];
    } else {
      targetContacts = [];
    }

    // Initialize recipient statuses
    final recipients = targetContacts.map((c) {
      return RecipientSmsStatus(
        contactId: c.id,
        name: c.name,
        phone: c.phone,
        status: SmsDeliveryState.pending,
        timestamp: now,
      );
    }).toList();

    // 3. Create active event
    final eventId = const Uuid().v4();
    final event = SosAlertEvent(
      id: eventId,
      timestamp: now,
      source: source,
      status: 'ACTIVE',
      location: loc,
      mapUrl: mapUrl,
      recipients: recipients,
      isBroadcastToNearby: broadcastToNearby,
      notes: 'Emergency SOS activated via $source',
    );

    _activeEvent = event;
    await _storageService.saveActiveSos(event);
    _activeEventController.add(_activeEvent);

    final formattedTime =
        DateFormat('dd MMM yyyy, hh:mm:ss a').format(now.toLocal());

    _hardwareService.logTerminal(
        '🚨 EMERGENCY SOS DISPATCH STARTED (ID: $eventId) at $formattedTime');

    // 4. Send GPS to ESP32 hardware
    _hardwareService.sendPhoneGpsToEsp32(loc.lat, loc.lng, loc.accuracy);

    // 5. CHANNEL 1: Dispatch via Emergency SMS Gateway with full metadata
    final updatedRecipients = <RecipientSmsStatus>[];
    bool anyFailed = false;
    String failureDetail = '';

    for (final recipient in recipients) {
      _hardwareService.logTerminal(
          '📲 Emergency Gateway sending SMS with location and timestamp to ${recipient.name} (${recipient.phone})...');

      final result = await _twilioService.sendEmergencySms(
        recipientPhone: recipient.phone,
        senderName: 'Aprajita User',
        locationUrl: mapUrl,
        latitude: loc.lat,
        longitude: loc.lng,
        accuracy: loc.accuracy,
        batteryLevel: _hardwareService.telemetry.batteryLevel,
        triggerSource: source,
        timestamp: now,
        customNote: 'Distress alarm active',
      );

      if (!result.success) {
        anyFailed = true;
        failureDetail = result.message;
      }

      final updatedStatus = recipient.copyWith(
        status: result.deliveryState,
        messageSid: result.sid,
        errorDetail: result.message,
      );
      updatedRecipients.add(updatedStatus);

      _hardwareService.logTerminal(
          '   └─ Result: ${result.deliveryState.name.toUpperCase()} | ${result.message}');
    }

    // Update event with delivery outcomes
    final finalEvent = _activeEvent!.copyWith(recipients: updatedRecipients);
    _activeEvent = finalEvent;
    await _storageService.saveActiveSos(finalEvent);
    await _storageService.addHistoryItem(finalEvent);
    _activeEventController.add(_activeEvent);

    // Retain factual incident summary into Vectorize Hindsight Memory Bank
    try {
      final incidentSummary = 'EMERGENCY INCIDENT ($formattedTime): SOS triggered via $source. '
          'Location Fix: ${loc.lat.toStringAsFixed(4)}, ${loc.lng.toStringAsFixed(4)} ($mapUrl). '
          'Recipients: ${updatedRecipients.map((r) => "${r.name}: ${r.status.name}").join(", ")}. '
          'Battery: ${_hardwareService.telemetry.batteryLevel}%.';
      _hindsightService?.retain(incidentSummary, tag: 'sos_incident');
    } catch (_) {}

    // Automatic native carrier SMS fallback if cloud dispatch encounters unverified number or failure
    if (anyFailed) {
      _hardwareService.logTerminal(
          '⚠️ Cloud gateway delivery failure ($failureDetail). Triggering direct carrier SMS fallback on device...');
      await sendNativeSmsFallback();
    }

    // 6. Broadcast to Nearby Community
    if (broadcastToNearby) {
      _hardwareService.logTerminal(
          '📡 Broadcasting distress signal with Google Maps link to nearby community...');
      await _nearbyService.broadcastMyAlert(
        userName: 'Aprajita Member (Distress)',
        userPhone: targetContacts.isNotEmpty ? targetContacts.first.phone : '',
        location: loc,
        message:
            'Active emergency SOS triggered at $formattedTime! Live location: $mapUrl',
        radiusKm: 3.0,
      );
    }

    final targetPhone =
        targetContacts.isNotEmpty ? targetContacts.first.phone : (allContacts.isNotEmpty ? allContacts.first.phone : '');

    // 7. CHANNEL 2: Dispatched via Twilio Voice Call (Automated spoken distress alert)
    _hardwareService.logTerminal(
        '📞 CHANNEL 2: Placing emergency voice call via Twilio to $targetPhone...');
    final voiceResult = await _twilioService.placeEmergencyVoiceCall(
      recipientPhone: targetPhone,
      locationUrl: mapUrl,
      timestamp: now,
    );
    _hardwareService.logTerminal(
        '   └─ Voice Call: ${voiceResult.success ? "DIALING" : "FAILED"} | ${voiceResult.message}');

    // Fallback to phone dialer if gateway voice encounters network failure
    if (!voiceResult.success) {
      _hardwareService.logTerminal(
          '⚠️ Twilio voice call issue. Triggering device dialer fallback...');
      Future.delayed(const Duration(milliseconds: 600), () {
        makeEmergencyPhoneCall(phoneNumber: targetPhone);
      });
    }

    // 8. CHANNEL 3: Dispatched via Twilio WhatsApp API
    _hardwareService.logTerminal(
        '💬 CHANNEL 3: Sending emergency distress message via Twilio WhatsApp to $targetPhone...');
    final waResult = await _twilioService.sendEmergencyWhatsApp(
      recipientPhone: targetPhone,
      locationUrl: mapUrl,
      timestamp: now,
      batteryLevel: _hardwareService.telemetry.batteryLevel,
    );
    _hardwareService.logTerminal(
        '   └─ WhatsApp: ${waResult.success ? "SUBMITTED" : "FAILED"} | ${waResult.message}');

    // Fallback to device WhatsApp if Twilio WhatsApp sandbox restriction occurs
    if (!waResult.success) {
      _hardwareService.logTerminal(
          '⚠️ Twilio WhatsApp issue. Triggering device WhatsApp fallback...');
      await sendWhatsAppDistressMessage(recipientPhone: targetPhone);
    }

    // Update active event with Voice & WhatsApp gateway statuses
    if (_activeEvent != null) {
      final updatedEvent = _activeEvent!.copyWith(
        voiceCallSid: voiceResult.sid,
        voiceCallStatus: voiceResult.success ? 'QUEUED' : 'FAILED',
        whatsappMessageSid: waResult.sid,
        whatsappStatus: waResult.success ? 'SUBMITTED' : 'FAILED',
      );
      _activeEvent = updatedEvent;
      await _storageService.saveActiveSos(updatedEvent);
      await _storageService.addHistoryItem(updatedEvent);
      _activeEventController.add(_activeEvent);
    }
  }

  /// Sends emergency SMS using phone's native SMS application (Guaranteed SIM carrier fallback)
  Future<void> sendNativeSmsFallback() async {
    final loc = _locationService.currentLocation;
    final mapUrl = loc?.googleMapsUrl ?? 'Location Unavailable';
    final nowFormatted =
        DateFormat('hh:mm a, dd MMM yyyy').format(DateTime.now().toLocal());

    final contacts = _storageService.loadContacts();
    final emergencyContacts =
        contacts.where((c) => c.isEmergencyRecipient).toList();
    if (emergencyContacts.isEmpty && contacts.isNotEmpty) {
      emergencyContacts.add(contacts.first);
    }
    if (emergencyContacts.isEmpty) return;

    final phoneNumbers = emergencyContacts
        .map((c) => c.phone.replaceAll(RegExp(r'[\s\-]'), ''))
        .join(';');

    final primaryPhone = emergencyContacts.first.phone.replaceAll(RegExp(r'[\s\-]'), '');

    final body = Uri.encodeComponent(
      'EMERGENCY SOS: I need help!\n'
      'Location: $mapUrl\n'
      'Time: $nowFormatted\n'
      'Sent via Aprajita Safety App',
    );

    try {
      final uri = Uri.parse('sms:$phoneNumbers?body=$body');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}

    try {
      final singleUri = Uri.parse('sms:$primaryPhone?body=$body');
      await launchUrl(singleUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      _hardwareService.logTerminal('❌ Could not launch native SMS app: $e');
    }
  }

  /// Places an emergency phone call to primary contact or emergency helpline
  Future<void> makeEmergencyPhoneCall({String? phoneNumber}) async {
    String? target = phoneNumber;
    if (target == null || target.isEmpty) {
      final contacts = _storageService.loadContacts();
      final primaryId = _storageService.getPrimaryContactId();
      if (contacts.isNotEmpty) {
        TrustedContact? primary;
        if (primaryId != null && primaryId.isNotEmpty) {
          primary = contacts.cast<TrustedContact?>().firstWhere(
            (c) => c?.id == primaryId,
            orElse: () => contacts.cast<TrustedContact?>().firstWhere(
              (c) => c?.isEmergencyRecipient == true,
              orElse: () => contacts.first,
            ),
          );
        } else {
          final em = contacts.where((c) => c.isEmergencyRecipient).toList();
          primary = em.isNotEmpty ? em.first : contacts.first;
        }
        target = primary?.phone;
      }
    }

    if (target == null || target.isEmpty) {
      target = '112'; // Default National Emergency Helpline
    }

    final cleaned = target.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleaned');
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (launched) {
        _hardwareService.logTerminal('📞 Initiated emergency call to $target');
        return;
      }
    } catch (_) {}

    try {
      await launchUrl(uri);
      _hardwareService.logTerminal('📞 Initiated emergency call to $target');
    } catch (e) {
      _hardwareService.logTerminal('❌ Could not place phone call to $target: $e');
    }
  }

  /// Sends emergency distress alert via WhatsApp with live Google Maps link & battery telemetry
  Future<void> sendWhatsAppDistressMessage({String? recipientPhone}) async {
    final loc = _locationService.currentLocation;
    final mapUrl = loc?.googleMapsUrl ?? 'Location Unavailable';
    final nowFormatted =
        DateFormat('hh:mm a, dd MMM yyyy').format(DateTime.now().toLocal());
    final battery = _hardwareService.telemetry.batteryLevel;

    final messageText =
        '🚨 *EMERGENCY SOS ALERT!* 🚨\n'
        'I am in distress and need immediate help!\n\n'
        '📍 *Live Location:* $mapUrl\n'
        '⏰ *Timestamp:* $nowFormatted\n'
        '🔋 *Battery:* $battery%\n\n'
        '_(Sent via Aprajita Safety App)_';

    final encodedMsg = Uri.encodeComponent(messageText);

    String? targetPhone = recipientPhone;
    if (targetPhone == null || targetPhone.isEmpty) {
      final contacts = _storageService.loadContacts();
      final primaryId = _storageService.getPrimaryContactId();
      if (contacts.isNotEmpty) {
        TrustedContact? primary;
        if (primaryId != null && primaryId.isNotEmpty) {
          primary = contacts.cast<TrustedContact?>().firstWhere(
            (c) => c?.id == primaryId,
            orElse: () => contacts.cast<TrustedContact?>().firstWhere(
              (c) => c?.isEmergencyRecipient == true,
              orElse: () => contacts.first,
            ),
          );
        } else {
          final em = contacts.where((c) => c.isEmergencyRecipient).toList();
          primary = em.isNotEmpty ? em.first : contacts.first;
        }
        targetPhone = primary?.phone;
      }
    }

    targetPhone ??= '';

    String rawDigits = '';
    if (targetPhone.isNotEmpty) {
      rawDigits = targetPhone.replaceAll(RegExp(r'\D'), '');
      if (rawDigits.length == 10) {
        rawDigits = '91$rawDigits';
      } else if (rawDigits.length == 11 && rawDigits.startsWith('0')) {
        rawDigits = '91${rawDigits.substring(1)}';
      }
    }

    // 1. Direct chat with primary contact
    if (rawDigits.isNotEmpty) {
      final whatsappNativeUri =
          Uri.parse('whatsapp://send?phone=$rawDigits&text=$encodedMsg');
      try {
        final launched = await launchUrl(whatsappNativeUri,
            mode: LaunchMode.externalApplication);
        if (launched) {
          _hardwareService.logTerminal(
              '💬 Opened WhatsApp emergency message to +$rawDigits');
          return;
        }
      } catch (_) {}

      final waWebUri = Uri.parse(
          'https://api.whatsapp.com/send?phone=$rawDigits&text=$encodedMsg');
      try {
        final launched = await launchUrl(waWebUri,
            mode: LaunchMode.externalApplication);
        if (launched) {
          _hardwareService.logTerminal(
              '💬 Opened WhatsApp Web API emergency message to +$rawDigits');
          return;
        }
      } catch (_) {}
    }

    // 2. Fallback to WhatsApp contact/group picker
    final generalWaUri = Uri.parse('whatsapp://send?text=$encodedMsg');
    try {
      final launched = await launchUrl(generalWaUri,
          mode: LaunchMode.externalApplication);
      if (launched) {
        _hardwareService.logTerminal(
            '💬 Opened WhatsApp contact picker for emergency dispatch');
        return;
      }
    } catch (e) {
      _hardwareService.logTerminal('❌ Could not launch WhatsApp: $e');
    }
  }

  /// Resolves the active SOS event
  Future<void> resolveActiveSos() async {
    if (_activeEvent == null) return;

    final resolved = _activeEvent!.copyWith(
      status: 'RESOLVED',
      resolvedAt: DateTime.now(),
    );

    await _storageService.saveActiveSos(null);
    await _storageService.addHistoryItem(resolved);
    await _nearbyService.resolveMyAlert();

    _activeEvent = null;
    _activeEventController.add(null);

    HapticFeedback.lightImpact();
    _hardwareService.logTerminal('✅ Emergency SOS Status: RESOLVED by user.');
  }

  void dispose() {
    _hwSub?.cancel();
    _countdownTimer?.cancel();
    _activeEventController.close();
    _countdownStreamController.close();
  }
}
