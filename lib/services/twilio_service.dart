import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../models/sos_event_model.dart';
import 'storage_service.dart';

class TwilioResult {
  final bool success;
  final String? sid;
  final SmsDeliveryState deliveryState;
  final String message;
  final int? statusCode;

  TwilioResult({
    required this.success,
    this.sid,
    required this.deliveryState,
    required this.message,
    this.statusCode,
  });
}

class TwilioService {
  final StorageService _storageService;

  TwilioService(this._storageService);

  String get _accountSid =>
      _storageService.loadTwilioConfig()['accountSid'] ?? '';

  String get _authToken =>
      _storageService.loadTwilioConfig()['authToken'] ?? '';

  String get _fromNumber =>
      _storageService.loadTwilioConfig()['phoneNo'] ?? '';

  String get _whatsappFrom =>
      _storageService.loadTwilioConfig()['whatsappFrom'] ?? '+14155238886';

  bool get isEnabled =>
      _storageService.loadTwilioConfig()['enabled'] == 'true' &&
      _accountSid.isNotEmpty &&
      _authToken.isNotEmpty;

  /// Normalizes any phone number to E.164 format (+91...)
  String normalizePhone(String to) {
    final rawDigits = to.replaceAll(RegExp(r'\D'), '');
    if (to.trim().startsWith('+')) {
      return '+$rawDigits';
    } else if (rawDigits.length == 10) {
      return '+91$rawDigits';
    } else if (rawDigits.length == 11 && rawDigits.startsWith('0')) {
      return '+91${rawDigits.substring(1)}';
    } else if (rawDigits.length == 12 && rawDigits.startsWith('91')) {
      return '+$rawDigits';
    } else {
      return '+$rawDigits';
    }
  }

  /// Sends emergency SOS SMS with Google Maps location and exact timestamp via Twilio
  Future<TwilioResult> sendEmergencySms({
    required String recipientPhone,
    required String senderName,
    required String locationUrl,
    double? latitude,
    double? longitude,
    double? accuracy,
    int? batteryLevel,
    String? triggerSource,
    DateTime? timestamp,
    String? customNote,
  }) async {
    final effectiveTime = timestamp ?? DateTime.now();
    final timeFormatted =
        DateFormat('hh:mm a, dd MMM').format(effectiveTime.toLocal());

    final messageBody =
        'EMERGENCY SOS: I need help!\n'
        'Location: $locationUrl\n'
        'Time: $timeFormatted\n'
        'Sent via Aprajita Safety App';

    return _sendSms(to: recipientPhone, body: messageBody);
  }

  /// Places an automated emergency phone call via Twilio Programmable Voice (/Calls.json)
  /// Speaks an urgent distress alert with live location details via TwiML.
  Future<TwilioResult> placeEmergencyVoiceCall({
    required String recipientPhone,
    required String locationUrl,
    String? senderName,
    DateTime? timestamp,
  }) async {
    if (!isEnabled) {
      return TwilioResult(
        success: false,
        deliveryState: SmsDeliveryState.failed,
        message: 'Emergency gateway is disabled in settings.',
      );
    }

    final sid = _accountSid.trim();
    final token = _authToken.trim();
    final from = _fromNumber.trim();

    if (sid.isEmpty || token.isEmpty || from.isEmpty) {
      return TwilioResult(
        success: false,
        deliveryState: SmsDeliveryState.failed,
        message: 'Gateway credentials missing in app settings.',
      );
    }

    final normalizedTo = normalizePhone(recipientPhone);
    final uri = Uri.parse('https://api.twilio.com/2010-04-01/Accounts/$sid/Calls.json');
    final authHeader = 'Basic ${base64Encode(utf8.encode('$sid:$token'))}';

    const twiml =
        '<Response>'
        '<Say voice="alice" language="en-IN">'
        'Emergency SOS Alert! Aprajita Safety User needs immediate assistance. '
        'A live Google Maps location link has been sent to your phone via SMS. '
        'Please check your messages immediately and provide help.'
        '</Say>'
        '</Response>';

    try {
      final response = await http
          .post(
            uri,
            headers: {
              'Authorization': authHeader,
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {
              'To': normalizedTo,
              'From': from,
              'Twiml': twiml,
            },
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final callSid = data['sid'] as String?;
        final status = data['status'] as String? ?? 'queued';
        return TwilioResult(
          success: true,
          sid: callSid,
          deliveryState: SmsDeliveryState.delivered,
          message: 'Voice call initiated via gateway ($status). Ref: $callSid',
          statusCode: response.statusCode,
        );
      } else {
        final errorMsg = data['message'] ?? 'Voice Call Gateway Error';
        final errorCode = data['code']?.toString() ?? '${response.statusCode}';
        return TwilioResult(
          success: false,
          deliveryState: SmsDeliveryState.failed,
          message: 'Voice Error ($errorCode): $errorMsg',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return TwilioResult(
        success: false,
        deliveryState: SmsDeliveryState.failed,
        message: 'Network error placing emergency voice call: $e',
      );
    }
  }

  /// Dispatches an emergency distress alert via Twilio WhatsApp API (/Messages.json with whatsapp:)
  Future<TwilioResult> sendEmergencyWhatsApp({
    required String recipientPhone,
    required String locationUrl,
    DateTime? timestamp,
    int? batteryLevel,
  }) async {
    if (!isEnabled) {
      return TwilioResult(
        success: false,
        deliveryState: SmsDeliveryState.failed,
        message: 'Emergency gateway is disabled in settings.',
      );
    }

    final sid = _accountSid.trim();
    final token = _authToken.trim();
    final waFrom = _whatsappFrom.trim();

    if (sid.isEmpty || token.isEmpty || waFrom.isEmpty) {
      return TwilioResult(
        success: false,
        deliveryState: SmsDeliveryState.failed,
        message: 'WhatsApp gateway credentials missing in app settings.',
      );
    }

    final effectiveTime = timestamp ?? DateTime.now();
    final timeFormatted =
        DateFormat('hh:mm a, dd MMM').format(effectiveTime.toLocal());
    final battery = batteryLevel ?? 100;

    final messageBody =
        '🚨 *EMERGENCY SOS ALERT!* 🚨\n'
        'Aprajita user is in distress and needs immediate help!\n\n'
        '📍 *Live Location:* $locationUrl\n'
        '⏰ *Time:* $timeFormatted\n'
        '🔋 *Battery:* $battery%\n\n'
        '_(Dispatched via Aprajita Safety Gateway)_';

    final normalizedTo = normalizePhone(recipientPhone);
    final formattedFrom =
        waFrom.startsWith('whatsapp:') ? waFrom : 'whatsapp:$waFrom';
    final formattedTo = 'whatsapp:$normalizedTo';

    final uri = Uri.parse(
        'https://api.twilio.com/2010-04-01/Accounts/$sid/Messages.json');
    final authHeader = 'Basic ${base64Encode(utf8.encode('$sid:$token'))}';

    try {
      final response = await http
          .post(
            uri,
            headers: {
              'Authorization': authHeader,
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {
              'To': formattedTo,
              'From': formattedFrom,
              'Body': messageBody,
            },
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final messageSid = data['sid'] as String?;
        final status = data['status'] as String? ?? 'queued';
        return TwilioResult(
          success: true,
          sid: messageSid,
          deliveryState: SmsDeliveryState.submitted,
          message: 'WhatsApp alert queued via gateway ($status). Ref: $messageSid',
          statusCode: response.statusCode,
        );
      } else {
        final errorMsg = data['message'] ?? 'WhatsApp Gateway Error';
        final errorCode = data['code']?.toString() ?? '${response.statusCode}';
        return TwilioResult(
          success: false,
          deliveryState: SmsDeliveryState.failed,
          message: 'WhatsApp Error ($errorCode): $errorMsg',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return TwilioResult(
        success: false,
        deliveryState: SmsDeliveryState.failed,
        message: 'Network error sending WhatsApp alert: $e',
      );
    }
  }

  /// Sends a test SMS verification
  Future<TwilioResult> sendTestSms({required String recipientPhone}) async {
    final timeFormatted =
        DateFormat('hh:mm a, dd MMM').format(DateTime.now().toLocal());

    final messageBody =
        'Aprajita Test Alert: Emergency SMS gateway is verified and online.\n'
        'Time: $timeFormatted';

    return _sendSms(to: recipientPhone, body: messageBody);
  }

  /// Internal HTTP POST to Twilio SMS Gateway API
  Future<TwilioResult> _sendSms({
    required String to,
    required String body,
  }) async {
    if (!isEnabled) {
      return TwilioResult(
        success: false,
        deliveryState: SmsDeliveryState.failed,
        message: 'Emergency SMS gateway is disabled in settings.',
      );
    }

    final sid = _accountSid.trim();
    final token = _authToken.trim();
    final from = _fromNumber.trim();

    if (sid.isEmpty || token.isEmpty || from.isEmpty) {
      return TwilioResult(
        success: false,
        deliveryState: SmsDeliveryState.failed,
        message: 'Gateway credentials missing in app settings.',
      );
    }

    final normalizedTo = normalizePhone(to);

    final uri = Uri.parse(
        'https://api.twilio.com/2010-04-01/Accounts/$sid/Messages.json');
    final authHeader =
        'Basic ${base64Encode(utf8.encode('$sid:$token'))}';

    try {
      final response = await http
          .post(
            uri,
            headers: {
              'Authorization': authHeader,
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {
              'To': normalizedTo,
              'From': from,
              'Body': body,
            },
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final messageSid = data['sid'] as String?;
        final status = data['status'] as String? ?? 'queued';
        return TwilioResult(
          success: true,
          sid: messageSid,
          deliveryState: SmsDeliveryState.submitted,
          message: 'SMS submitted to gateway ($status). Ref: $messageSid',
          statusCode: response.statusCode,
        );
      } else {
        final errorMsg = data['message'] ?? 'SMS Gateway Error';
        final errorCode = data['code']?.toString() ?? '${response.statusCode}';
        return TwilioResult(
          success: false,
          deliveryState: SmsDeliveryState.failed,
          message: 'Gateway Error ($errorCode): $errorMsg',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return TwilioResult(
        success: false,
        deliveryState: SmsDeliveryState.failed,
        message: 'Network error connecting to SMS Gateway: $e',
      );
    }
  }
}
