import 'dart:async';
import 'package:uuid/uuid.dart';
import '../models/nearby_alert_model.dart';
import '../models/location_model.dart';
import 'supabase_service.dart';

class NearbyCommunityService {
  final SupabaseService _supabaseService;
  final List<NearbyCommunityAlert> _alerts = [];
  final StreamController<List<NearbyCommunityAlert>> _alertsController =
      StreamController<List<NearbyCommunityAlert>>.broadcast();

  Stream<List<NearbyCommunityAlert>> get alertsStream =>
      _alertsController.stream;
  List<NearbyCommunityAlert> get alerts => List.unmodifiable(_alerts);

  double _filterRadiusKm = 3.0; // Default 3 km radius
  double get filterRadiusKm => _filterRadiusKm;

  NearbyCommunityService(this._supabaseService) {
    _initSampleNearbyAlerts();
  }

  void setFilterRadius(double km) {
    _filterRadiusKm = km;
    _emit();
  }

  void _emit() {
    _alertsController.add(List.unmodifiable(_alerts));
  }

  void _initSampleNearbyAlerts() {
    // Initial realistic community alerts for testing (near Delhi/NCR)
    _alerts.addAll([
      NearbyCommunityAlert(
        id: 'alert-sample-1',
        userId: 'usr-102',
        userName: 'Aanya Sharma',
        userPhone: '+91 98711 44556',
        lat: 28.5482,
        lng: 77.2755,
        accuracy: 8.0,
        timestamp: DateTime.now().subtract(const Duration(minutes: 6)),
        radiusKm: 2.5,
        message: 'Active SOS: Feeling unsafe near Metro Station Exit 2. Need assistance!',
        status: 'ACTIVE',
        respondersCount: 2,
      ),
      NearbyCommunityAlert(
        id: 'alert-sample-2',
        userId: 'usr-103',
        userName: 'Pooja Verma',
        userPhone: '+91 98222 33441',
        lat: 28.5410,
        lng: 77.2690,
        accuracy: 12.0,
        timestamp: DateTime.now().subtract(const Duration(minutes: 18)),
        radiusKm: 3.0,
        message: 'Three-press emergency triggered. Walking alone in dark alleyway.',
        status: 'RESPONDING',
        respondersCount: 4,
      ),
    ]);
    _emit();
  }

  /// Broadcasts the current user's emergency SOS to the nearby community
  Future<NearbyCommunityAlert> broadcastMyAlert({
    required String userName,
    required String userPhone,
    required GpsLocation location,
    required String message,
    double radiusKm = 3.0,
  }) async {
    final alert = NearbyCommunityAlert(
      id: const Uuid().v4(),
      userId: 'current-user',
      userName: userName,
      userPhone: userPhone,
      lat: location.lat,
      lng: location.lng,
      accuracy: location.accuracy,
      timestamp: DateTime.now(),
      radiusKm: radiusKm,
      message: message,
      status: 'ACTIVE',
      respondersCount: 0,
      isCurrentDeviceAlert: true,
    );

    // Insert locally first (offline-first!)
    _alerts.removeWhere((a) => a.isCurrentDeviceAlert);
    _alerts.insert(0, alert);
    _emit();

    // Sync to Supabase in background
    _supabaseService.broadcastNearbyAlert(alert);

    return alert;
  }

  /// Resolve current user's broadcast
  Future<void> resolveMyAlert() async {
    final index = _alerts.indexWhere((a) => a.isCurrentDeviceAlert);
    if (index != -1) {
      final updated = _alerts[index].copyWith(status: 'RESOLVED');
      _alerts[index] = updated;
      _emit();
      _supabaseService.updateBroadcastStatus(updated.id, 'RESOLVED');
    }
  }

  /// Volunteer user responds to a nearby alert
  void respondToAlert(String alertId) {
    final index = _alerts.indexWhere((a) => a.id == alertId);
    if (index != -1) {
      final current = _alerts[index];
      final updated = current.copyWith(
        status: 'RESPONDING',
        respondersCount: current.respondersCount + 1,
      );
      _alerts[index] = updated;
      _emit();
      _supabaseService.updateBroadcastStatus(alertId, 'RESPONDING');
    }
  }

  /// Returns alerts sorted by distance to current user
  List<MapEntry<NearbyCommunityAlert, double>> getAlertsWithDistance(
      GpsLocation? userLoc) {
    if (userLoc == null) {
      return _alerts.map((a) => MapEntry(a, 0.0)).toList();
    }

    final list = _alerts.map((alert) {
      final distMeters = userLoc.distanceTo(alert.lat, alert.lng);
      return MapEntry(alert, distMeters);
    }).where((entry) {
      // Filter within radius km
      return entry.value <= (_filterRadiusKm * 1000);
    }).toList();

    // Sort closest first
    list.sort((a, b) => a.value.compareTo(b.value));
    return list;
  }

  void dispose() {
    _alertsController.close();
  }
}
