class NearbyCommunityAlert {
  final String id;
  final String userId;
  final String userName;
  final String userPhone;
  final double lat;
  final double lng;
  final double accuracy;
  final DateTime timestamp;
  final double radiusKm;
  final String message;
  final String status; // 'ACTIVE', 'RESPONDING', 'RESOLVED'
  final int respondersCount;
  final bool isCurrentDeviceAlert;

  NearbyCommunityAlert({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userPhone,
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.timestamp,
    this.radiusKm = 2.0,
    required this.message,
    this.status = 'ACTIVE',
    this.respondersCount = 0,
    this.isCurrentDeviceAlert = false,
  });

  String get googleMapsUrl => 'https://maps.google.com/?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';

  NearbyCommunityAlert copyWith({
    String? status,
    int? respondersCount,
  }) {
    return NearbyCommunityAlert(
      id: id,
      userId: userId,
      userName: userName,
      userPhone: userPhone,
      lat: lat,
      lng: lng,
      accuracy: accuracy,
      timestamp: timestamp,
      radiusKm: radiusKm,
      message: message,
      status: status ?? this.status,
      respondersCount: respondersCount ?? this.respondersCount,
      isCurrentDeviceAlert: isCurrentDeviceAlert,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'user_name': userName,
        'user_phone': userPhone,
        'latitude': lat,
        'longitude': lng,
        'accuracy': accuracy,
        'timestamp': timestamp.toIso8601String(),
        'radius_km': radiusKm,
        'message': message,
        'status': status,
        'responders_count': respondersCount,
      };

  factory NearbyCommunityAlert.fromJson(Map<String, dynamic> json) =>
      NearbyCommunityAlert(
        id: json['id'] ?? '',
        userId: json['user_id'] ?? '',
        userName: json['user_name'] ?? 'Community Member',
        userPhone: json['user_phone'] ?? '',
        lat: (json['latitude'] as num).toDouble(),
        lng: (json['longitude'] as num).toDouble(),
        accuracy: (json['accuracy'] as num?)?.toDouble() ?? 15.0,
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp']) ?? DateTime.now()
            : DateTime.now(),
        radiusKm: (json['radius_km'] as num?)?.toDouble() ?? 2.0,
        message: json['message'] ?? 'EMERGENCY SOS triggered nearby',
        status: json['status'] ?? 'ACTIVE',
        respondersCount: json['responders_count'] ?? 0,
        isCurrentDeviceAlert: json['is_current_device'] ?? false,
      );
}
