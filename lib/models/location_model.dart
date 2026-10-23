import 'dart:math';

enum GpsSource {
  phoneGps,
  keychainGps,
  manual,
  none,
}

class GpsLocation {
  final double lat;
  final double lng;
  final double accuracy; // in meters
  final DateTime timestamp;
  final GpsSource source;
  final bool isStale;

  GpsLocation({
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.timestamp,
    required this.source,
    this.isStale = false,
  });

  String get googleMapsUrl => 'https://maps.google.com/?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';

  String get displayCoords => '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';

  String get sourceName {
    switch (source) {
      case GpsSource.phoneGps:
        return 'Phone GPS (High Accuracy)';
      case GpsSource.keychainGps:
        return 'NEO-6M Hardware GPS';
      case GpsSource.manual:
        return 'Manual/Simulated Location';
      case GpsSource.none:
        return 'No Fix';
    }
  }

  /// Calculates Haversine distance in meters to another coordinate
  double distanceTo(double targetLat, double targetLng) {
    const earthRadius = 6371000.0; // meters
    final dLat = _degToRad(targetLat - lat);
    final dLng = _degToRad(targetLng - lng);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat)) *
            cos(_degToRad(targetLat)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _degToRad(double deg) => deg * (pi / 180.0);

  Map<String, dynamic> toJson() {
    return {
      'lat': lat,
      'lng': lng,
      'accuracy': accuracy,
      'timestamp': timestamp.toIso8601String(),
      'source': source.name,
      'isStale': isStale,
    };
  }

  factory GpsLocation.fromJson(Map<String, dynamic> map) {
    return GpsLocation(
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      accuracy: (map['accuracy'] as num?)?.toDouble() ?? 10.0,
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp']) ?? DateTime.now()
          : DateTime.now(),
      source: GpsSource.values.firstWhere(
        (e) => e.name == map['source'],
        orElse: () => GpsSource.phoneGps,
      ),
      isStale: map['isStale'] ?? false,
    );
  }
}
