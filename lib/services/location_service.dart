import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/location_model.dart';

class LocationService {
  GpsLocation? _lastKnownLocation;
  final StreamController<GpsLocation> _locationStreamController =
      StreamController<GpsLocation>.broadcast();

  Stream<GpsLocation> get locationStream => _locationStreamController.stream;
  GpsLocation? get currentLocation => _lastKnownLocation;

  // Default fallback coordinates (IIIT Delhi campus: 28.5457, 77.2732)
  static const double defaultLat = 28.545732;
  static const double defaultLng = 77.273185;

  LocationService() {
    // Initial default location
    _lastKnownLocation = GpsLocation(
      lat: defaultLat,
      lng: defaultLng,
      accuracy: 12.0,
      timestamp: DateTime.now(),
      source: GpsSource.manual,
    );
  }

  /// Refreshes phone GPS with high accuracy
  Future<GpsLocation> getCurrentLocation({bool forceRefresh = false}) async {
    try {
      // Check service status
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return _fallbackLocation('Location services are disabled on device');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return _fallbackLocation('Location permission denied by user');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return _fallbackLocation('Location permission permanently denied');
      }

      // Fetch actual phone GPS
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );

      final loc = GpsLocation(
        lat: position.latitude,
        lng: position.longitude,
        accuracy: position.accuracy,
        timestamp: position.timestamp,
        source: GpsSource.phoneGps,
      );

      _lastKnownLocation = loc;
      _locationStreamController.add(loc);
      return loc;
    } catch (e) {
      debugPrint('Geolocator error: $e. Falling back to default coordinate.');
      return _fallbackLocation('Using simulated GPS: $e');
    }
  }

  /// Manually update coordinates (used for simulation or manual override)
  void setManualLocation(double lat, double lng, {double accuracy = 8.0}) {
    final loc = GpsLocation(
      lat: lat,
      lng: lng,
      accuracy: accuracy,
      timestamp: DateTime.now(),
      source: GpsSource.manual,
    );
    _lastKnownLocation = loc;
    _locationStreamController.add(loc);
  }

  GpsLocation _fallbackLocation(String reason) {
    final loc = GpsLocation(
      lat: _lastKnownLocation?.lat ?? defaultLat,
      lng: _lastKnownLocation?.lng ?? defaultLng,
      accuracy: 15.0,
      timestamp: DateTime.now(),
      source: GpsSource.manual,
      isStale: true,
    );
    _lastKnownLocation = loc;
    _locationStreamController.add(loc);
    return loc;
  }

  void dispose() {
    _locationStreamController.close();
  }
}
