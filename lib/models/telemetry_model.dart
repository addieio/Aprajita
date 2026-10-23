enum DeviceConnectionState {
  connected,
  disconnected,
  connecting,
}

enum DeviceReadinessState {
  ready,
  attentionRequired,
  disconnected,
}

enum SimCardState {
  ready,
  absent,
  checking,
  unknown,
}

enum NetworkRegistrationState {
  registeredHome,
  roaming,
  searching,
  denied,
  offline,
  unknown,
}

class CellularStatus {
  final String operator;
  final int signalRssi; // dBm (-113 to -51)
  final int csq; // 0 to 31
  final int signalBars; // 0 to 4
  final SimCardState simStatus;
  final NetworkRegistrationState registration;
  final DateTime? lastChecked;

  CellularStatus({
    this.operator = 'Searching...',
    this.signalRssi = -95,
    this.csq = 14,
    this.signalBars = 2,
    this.simStatus = SimCardState.ready,
    this.registration = NetworkRegistrationState.registeredHome,
    this.lastChecked,
  });

  Map<String, dynamic> toJson() => {
        'operator': operator,
        'signalRssi': signalRssi,
        'csq': csq,
        'signalBars': signalBars,
        'simStatus': simStatus.name,
        'registration': registration.name,
        'lastChecked': lastChecked?.toIso8601String(),
      };

  factory CellularStatus.fromJson(Map<String, dynamic> json) => CellularStatus(
        operator: json['operator'] ?? 'Unknown',
        signalRssi: json['signalRssi'] ?? -99,
        csq: json['csq'] ?? 0,
        signalBars: json['signalBars'] ?? 0,
        simStatus: SimCardState.values.firstWhere(
          (e) => e.name == json['simStatus'],
          orElse: () => SimCardState.unknown,
        ),
        registration: NetworkRegistrationState.values.firstWhere(
          (e) => e.name == json['registration'],
          orElse: () => NetworkRegistrationState.unknown,
        ),
        lastChecked: json['lastChecked'] != null
            ? DateTime.tryParse(json['lastChecked'])
            : null,
      );
}

class HardwareTelemetry {
  final String deviceId;
  final String firmwareVersion;
  final DeviceConnectionState connectionState;
  final bool isSimulationMode;
  final int contactsSyncedCount;
  final DateTime? lastSyncTimestamp;
  final CellularStatus cellular;
  final bool neo6mFix;
  final int neo6mSatellites;
  final double? neo6mLat;
  final double? neo6mLng;
  final DateTime? physicalButtonLastPressed;
  final int physicalButtonConsecutivePresses;
  final int batteryLevel; // percentage 0 - 100
  final DateTime? lastHeartbeat;
  final String? lastModemResponse;
  final String? lastError;

  HardwareTelemetry({
    this.deviceId = 'SURAKSHA-KEY-01',
    this.firmwareVersion = 'v3.2.0-3PRESS',
    this.connectionState = DeviceConnectionState.disconnected,
    this.isSimulationMode = false,
    this.contactsSyncedCount = 0,
    this.lastSyncTimestamp,
    CellularStatus? cellular,
    this.neo6mFix = false,
    this.neo6mSatellites = 0,
    this.neo6mLat,
    this.neo6mLng,
    this.physicalButtonLastPressed,
    this.physicalButtonConsecutivePresses = 0,
    this.batteryLevel = 92,
    this.lastHeartbeat,
    this.lastModemResponse,
    this.lastError,
  }) : cellular = cellular ?? CellularStatus();

  HardwareTelemetry copyWith({
    String? deviceId,
    String? firmwareVersion,
    DeviceConnectionState? connectionState,
    bool? isSimulationMode,
    int? contactsSyncedCount,
    DateTime? lastSyncTimestamp,
    CellularStatus? cellular,
    bool? neo6mFix,
    int? neo6mSatellites,
    double? neo6mLat,
    double? neo6mLng,
    DateTime? physicalButtonLastPressed,
    int? physicalButtonConsecutivePresses,
    int? batteryLevel,
    DateTime? lastHeartbeat,
    String? lastModemResponse,
    String? lastError,
  }) {
    return HardwareTelemetry(
      deviceId: deviceId ?? this.deviceId,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      connectionState: connectionState ?? this.connectionState,
      isSimulationMode: isSimulationMode ?? this.isSimulationMode,
      contactsSyncedCount: contactsSyncedCount ?? this.contactsSyncedCount,
      lastSyncTimestamp: lastSyncTimestamp ?? this.lastSyncTimestamp,
      cellular: cellular ?? this.cellular,
      neo6mFix: neo6mFix ?? this.neo6mFix,
      neo6mSatellites: neo6mSatellites ?? this.neo6mSatellites,
      neo6mLat: neo6mLat ?? this.neo6mLat,
      neo6mLng: neo6mLng ?? this.neo6mLng,
      physicalButtonLastPressed:
          physicalButtonLastPressed ?? this.physicalButtonLastPressed,
      physicalButtonConsecutivePresses: physicalButtonConsecutivePresses ??
          this.physicalButtonConsecutivePresses,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      lastHeartbeat: lastHeartbeat ?? this.lastHeartbeat,
      lastModemResponse: lastModemResponse ?? this.lastModemResponse,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'firmwareVersion': firmwareVersion,
        'connectionState': connectionState.name,
        'isSimulationMode': isSimulationMode,
        'contactsSyncedCount': contactsSyncedCount,
        'lastSyncTimestamp': lastSyncTimestamp?.toIso8601String(),
        'cellular': cellular.toJson(),
        'neo6mFix': neo6mFix,
        'neo6mSatellites': neo6mSatellites,
        'neo6mLat': neo6mLat,
        'neo6mLng': neo6mLng,
        'batteryLevel': batteryLevel,
      };
}

class DiagnosticCheckItem {
  final String id;
  final String title;
  final String description;
  final String status; // 'PASS', 'FAIL', 'PENDING', 'RUNNING'
  final String detail;
  final String troubleshooting;

  DiagnosticCheckItem({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.detail,
    required this.troubleshooting,
  });

  DiagnosticCheckItem copyWith({
    String? status,
    String? detail,
    String? troubleshooting,
  }) {
    return DiagnosticCheckItem(
      id: id,
      title: title,
      description: description,
      status: status ?? this.status,
      detail: detail ?? this.detail,
      troubleshooting: troubleshooting ?? this.troubleshooting,
    );
  }
}
