import 'location_model.dart';

enum SmsDeliveryState {
  pending,
  submitted,
  delivered,
  failed,
  queuedOffline,
}

class RecipientSmsStatus {
  final String contactId;
  final String name;
  final String phone;
  final SmsDeliveryState status;
  final DateTime timestamp;
  final String? messageSid;
  final String? errorDetail;

  RecipientSmsStatus({
    required this.contactId,
    required this.name,
    required this.phone,
    required this.status,
    required this.timestamp,
    this.messageSid,
    this.errorDetail,
  });

  RecipientSmsStatus copyWith({
    SmsDeliveryState? status,
    String? messageSid,
    String? errorDetail,
  }) {
    return RecipientSmsStatus(
      contactId: contactId,
      name: name,
      phone: phone,
      status: status ?? this.status,
      timestamp: timestamp,
      messageSid: messageSid ?? this.messageSid,
      errorDetail: errorDetail ?? this.errorDetail,
    );
  }

  Map<String, dynamic> toJson() => {
        'contactId': contactId,
        'name': name,
        'phone': phone,
        'status': status.name,
        'timestamp': timestamp.toIso8601String(),
        'messageSid': messageSid,
        'errorDetail': errorDetail,
      };

  factory RecipientSmsStatus.fromJson(Map<String, dynamic> json) =>
      RecipientSmsStatus(
        contactId: json['contactId'] ?? '',
        name: json['name'] ?? '',
        phone: json['phone'] ?? '',
        status: SmsDeliveryState.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => SmsDeliveryState.pending,
        ),
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp']) ?? DateTime.now()
            : DateTime.now(),
        messageSid: json['messageSid'],
        errorDetail: json['errorDetail'],
      );
}

class SosAlertEvent {
  final String id;
  final DateTime timestamp;
  final String source; // 'PHYSICAL_BUTTON_3PRESS', 'APP_SOS_BUTTON', 'TEST_ALERT'
  final String status; // 'ACTIVE', 'RESOLVED', 'CANCELLED'
  final GpsLocation? location;
  final String mapUrl;
  final List<RecipientSmsStatus> recipients;
  final bool isBroadcastToNearby;
  final DateTime? resolvedAt;
  final String notes;
  final String? voiceCallSid;
  final String? voiceCallStatus;
  final String? whatsappMessageSid;
  final String? whatsappStatus;

  SosAlertEvent({
    required this.id,
    required this.timestamp,
    required this.source,
    this.status = 'ACTIVE',
    this.location,
    required this.mapUrl,
    required this.recipients,
    this.isBroadcastToNearby = false,
    this.resolvedAt,
    this.notes = '',
    this.voiceCallSid,
    this.voiceCallStatus,
    this.whatsappMessageSid,
    this.whatsappStatus,
  });

  SosAlertEvent copyWith({
    String? status,
    GpsLocation? location,
    String? mapUrl,
    List<RecipientSmsStatus>? recipients,
    bool? isBroadcastToNearby,
    DateTime? resolvedAt,
    String? notes,
    String? voiceCallSid,
    String? voiceCallStatus,
    String? whatsappMessageSid,
    String? whatsappStatus,
  }) {
    return SosAlertEvent(
      id: id,
      timestamp: timestamp,
      source: source,
      status: status ?? this.status,
      location: location ?? this.location,
      mapUrl: mapUrl ?? this.mapUrl,
      recipients: recipients ?? this.recipients,
      isBroadcastToNearby: isBroadcastToNearby ?? this.isBroadcastToNearby,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      notes: notes ?? this.notes,
      voiceCallSid: voiceCallSid ?? this.voiceCallSid,
      voiceCallStatus: voiceCallStatus ?? this.voiceCallStatus,
      whatsappMessageSid: whatsappMessageSid ?? this.whatsappMessageSid,
      whatsappStatus: whatsappStatus ?? this.whatsappStatus,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'source': source,
        'status': status,
        'location': location?.toJson(),
        'mapUrl': mapUrl,
        'recipients': recipients.map((r) => r.toJson()).toList(),
        'isBroadcastToNearby': isBroadcastToNearby,
        'resolvedAt': resolvedAt?.toIso8601String(),
        'notes': notes,
        'voiceCallSid': voiceCallSid,
        'voiceCallStatus': voiceCallStatus,
        'whatsappMessageSid': whatsappMessageSid,
        'whatsappStatus': whatsappStatus,
      };

  factory SosAlertEvent.fromJson(Map<String, dynamic> json) => SosAlertEvent(
        id: json['id'] ?? '',
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp']) ?? DateTime.now()
            : DateTime.now(),
        source: json['source'] ?? 'APP_SOS_BUTTON',
        status: json['status'] ?? 'RESOLVED',
        location: json['location'] != null
            ? GpsLocation.fromJson(json['location'])
            : null,
        mapUrl: json['mapUrl'] ?? '',
        recipients: (json['recipients'] as List<dynamic>?)
                ?.map((r) => RecipientSmsStatus.fromJson(r))
                .toList() ??
            [],
        isBroadcastToNearby: json['isBroadcastToNearby'] ?? false,
        resolvedAt: json['resolvedAt'] != null
            ? DateTime.tryParse(json['resolvedAt'])
            : null,
        notes: json['notes'] ?? '',
        voiceCallSid: json['voiceCallSid'],
        voiceCallStatus: json['voiceCallStatus'],
        whatsappMessageSid: json['whatsappMessageSid'],
        whatsappStatus: json['whatsappStatus'],
      );
}
