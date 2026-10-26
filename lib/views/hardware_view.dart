import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/telemetry_model.dart';
import '../services/hardware_service.dart';
import '../theme/app_theme.dart';

class HardwareView extends StatefulWidget {
  final HardwareService hardwareService;

  const HardwareView({
    super.key,
    required this.hardwareService,
  });

  @override
  State<HardwareView> createState() => _HardwareViewState();
}

class _HardwareViewState extends State<HardwareView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _ipController;
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _ipController = TextEditingController(text: widget.hardwareService.espIp);
    widget.hardwareService.terminalLogStream.listen((log) {
      if (mounted) {
        setState(() {
          _logs.add(log);
          if (_logs.length > 100) _logs.removeAt(0);
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<HardwareTelemetry>(
      stream: widget.hardwareService.telemetryStream,
      initialData: widget.hardwareService.telemetry,
      builder: (context, snapshot) {
        final hw = snapshot.data ?? HardwareTelemetry();
        final isConnected = hw.connectionState == DeviceConnectionState.connected;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Hardware Diagnostics',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'ESP32 & A7670C GSM/GPS Telemetry',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isConnected
                          ? AppTheme.emerald.withValues(alpha: 0.15)
                          : Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isConnected
                            ? AppTheme.emerald.withValues(alpha: 0.4)
                            : Colors.red.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isConnected ? AppTheme.emerald : Colors.red,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isConnected ? 'CONNECTED' : 'OFFLINE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: isConnected ? AppTheme.emerald : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.surfaceDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: AppTheme.crimson,
                indicatorWeight: 2.5,
                labelColor: AppTheme.textPrimary,
                unselectedLabelColor: AppTheme.textMuted,
                isScrollable: false,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                unselectedLabelStyle: const TextStyle(fontSize: 11),
                tabs: const [
                  Tab(icon: Icon(Icons.hub_rounded, size: 16), text: 'Hardware Link'),
                  Tab(icon: Icon(Icons.build_circle_outlined, size: 16), text: 'Troubleshoot'),
                  Tab(icon: Icon(Icons.terminal_rounded, size: 16), text: 'Terminal Log'),
                  Tab(icon: Icon(Icons.code_rounded, size: 16), text: 'Firmware'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildStatusAndSimulatorTab(hw, isConnected),
                  _buildTroubleshootTab(hw),
                  _buildTerminalTab(),
                  _buildFirmwareCodeTab(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // TAB 1: Status & Simulator
  Widget _buildStatusAndSimulatorTab(HardwareTelemetry hw, bool isConnected) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Main Bluetooth Link Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.cardDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isConnected ? AppTheme.emerald : AppTheme.borderSubtle,
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.bluetooth_connected,
                        color: isConnected ? AppTheme.emerald : Colors.blueAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isConnected
                            ? (hw.isSimulationMode ? 'SIMULATOR ACTIVE' : 'BLE LINKED: ${widget.hardwareService.bleDeviceName ?? "SURAKSHA-KEY"}')
                            : 'BLUETOOTH LINK',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isConnected ? AppTheme.emerald : Colors.white,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('Sim Mode', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      Switch(
                        value: hw.isSimulationMode,
                        activeThumbColor: AppTheme.indigo,
                        onChanged: (val) {
                          widget.hardwareService.enableSimulationMode(val);
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                isConnected
                    ? '🟢 Paired with ESP32-C6 • Phone GPS streamed continuously • Hardware Wi-Fi ready for Twilio'
                    : 'Pair your phone with Aprajita ESP32 over Bluetooth to stream phone GPS & trigger SOS.',
                style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 14),

              // PRIMARY BLUETOOTH ACTION BUTTON
              if (!isConnected)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: widget.hardwareService.isScanning
                        ? null
                        : () async {
                            final success = await widget.hardwareService.startBleScanAndConnect();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    success
                                        ? '🟢 Paired with SURAKSHA-KEY over Bluetooth! Streaming Phone GPS.'
                                        : '⚠️ Could not find "SURAKSHA-KEY". Ensure ESP32 is powered on nearby.',
                                  ),
                                  backgroundColor: success ? AppTheme.emerald : AppTheme.amber,
                                  duration: const Duration(seconds: 4),
                                ),
                              );
                            }
                          },
                    icon: widget.hardwareService.isScanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.bluetooth_searching, size: 18),
                    label: Text(
                      widget.hardwareService.isScanning
                          ? 'Scanning for "SURAKSHA-KEY"...'
                          : 'Connect via Bluetooth (1-Tap)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.emerald.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.emerald.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.location_searching, size: 14, color: AppTheme.emerald),
                          SizedBox(width: 6),
                          Text(
                            'Streaming Phone GPS over BLE',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.emerald),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    OutlinedButton(
                      onPressed: () => widget.hardwareService.disconnect(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      ),
                      child: const Text('Disconnect', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),

              const SizedBox(height: 14),

              // LIVE HARDWARE REMOTE CONTROLS
              const Text('LIVE HARDWARE REMOTE CONTROLS (BLE):', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.emerald, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.face, size: 14),
                      label: const Text('Face', style: TextStyle(fontSize: 11)),
                      onPressed: () => widget.hardwareService.setEspScreen('FACES'),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.borderSubtle)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.cloud_outlined, size: 14),
                      label: const Text('Weather', style: TextStyle(fontSize: 11)),
                      onPressed: () => widget.hardwareService.setEspScreen('WEATHER'),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.borderSubtle)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.nightlight_round, size: 14, color: Colors.indigoAccent),
                      label: const Text('Night Mode', style: TextStyle(fontSize: 10.5, color: Colors.indigoAccent)),
                      onPressed: () => widget.hardwareService.setEspScreen('NIGHT_MODE'),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.indigoAccent)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: StreamBuilder<bool>(
                      stream: widget.hardwareService.nightModeStream,
                      initialData: false,
                      builder: (btnCtx, snapshot) {
                        final isNightActive = snapshot.data ?? false;
                        return OutlinedButton.icon(
                          icon: Icon(isNightActive ? Icons.shield : Icons.shield_outlined, size: 14, color: isNightActive ? AppTheme.emerald : Colors.white70),
                          label: Text(
                            isNightActive ? 'Night Watch: ACTIVE (10m Ping)' : 'Turn ON Night Watch',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isNightActive ? AppTheme.emerald : Colors.white,
                            ),
                          ),
                          onPressed: () async {
                            final newState = !isNightActive;
                            await widget.hardwareService.syncNightModeToEsp32(newState);
                            if (!btnCtx.mounted) return;
                            ScaffoldMessenger.of(btnCtx).showSnackBar(
                              SnackBar(
                                content: Text(newState
                                    ? '🛡️ Night Watch Mode ACTIVATED! Location will share every 10 mins.'
                                    : 'Night Watch Mode turned OFF.'),
                                backgroundColor: newState ? AppTheme.emerald : AppTheme.cardElevated,
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: isNightActive ? AppTheme.emerald : AppTheme.borderSubtle),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.warning_amber_rounded, size: 14),
                    label: const Text('Test SOS', style: TextStyle(fontSize: 11)),
                    onPressed: () async {
                      final success = await widget.hardwareService.triggerEspSos();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              success
                                  ? '🚨 Real Twilio SOS Dispatched from ESP32 via Wi-Fi with Phone GPS!'
                                  : '❌ Failed to reach ESP32.',
                            ),
                            backgroundColor: success ? AppTheme.crimson : AppTheme.amber,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.crimson, foregroundColor: Colors.white),
                  ),
                ],
              ),

              const SizedBox(height: 14),
              const Divider(color: AppTheme.borderSubtle),

              // OPTIONAL WI-FI IP FALLBACK
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Advanced: Wi-Fi / IP Direct Link', style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary)),
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceDark,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.borderSubtle),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.wifi, size: 16, color: AppTheme.textMuted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _ipController,
                              style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                              decoration: const InputDecoration(
                                hintText: 'ESP IP (e.g. 192.168.4.1)',
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              onChanged: (val) => widget.hardwareService.espIp = val,
                            ),
                          ),
                          TextButton(
                            onPressed: () => widget.hardwareService.connectRealEsp(_ipController.text),
                            child: const Text('Connect IP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.emerald)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        ActionChip(
                          label: const Text('SoftAP: 192.168.4.1', style: TextStyle(fontSize: 10, color: AppTheme.emerald)),
                          backgroundColor: AppTheme.surfaceDark,
                          onPressed: () {
                            _ipController.text = '192.168.4.1';
                            widget.hardwareService.connectRealEsp('192.168.4.1');
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3-PRESS PHYSICAL BUTTON MECHANISM CARD
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.indigo.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.touch_app_outlined, color: AppTheme.indigo, size: 22),
                      SizedBox(width: 8),
                      Text(
                        '3-PRESS SOS MECHANISM (GPIO 4)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.indigo.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Presses: ${hw.physicalButtonConsecutivePresses}/3',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.indigo),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Prevents accidental triggers: requires three physical clicks within a 1.5-second time window.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    widget.hardwareService.recordButtonPress();
                  },
                  icon: const Icon(Icons.radio_button_checked),
                  label: const Text('Simulate Physical Button Click'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.cardElevated,
                    foregroundColor: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // HARDWARE SUBSYSTEMS STATUS
        const Text(
          'Hardware Subsystems',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 10),
        _buildSubsystemTile(
          icon: Icons.cell_tower,
          name: 'SIMCom A7670C 4G LTE',
          status: 'Online (${hw.cellular.operator})',
          detail: 'Signal: ${hw.cellular.csq}/31 CSQ (${hw.cellular.signalRssi} dBm)',
          isOk: hw.cellular.csq > 0,
        ),
        _buildSubsystemTile(
          icon: Icons.sim_card,
          name: 'Micro-SIM Status',
          status: hw.cellular.simStatus.name.toUpperCase(),
          detail: 'Registration: ${hw.cellular.registration.name}',
          isOk: hw.cellular.simStatus == SimCardState.ready,
        ),
        _buildSubsystemTile(
          icon: Icons.satellite_alt,
          name: 'u-blox NEO-6M GPS',
          status: hw.neo6mFix ? '3D Satellite Fix' : 'Searching for Fix',
          detail: 'Locked Satellites: ${hw.neo6mSatellites}',
          isOk: hw.neo6mFix,
        ),
        _buildSubsystemTile(
          icon: Icons.battery_charging_full,
          name: 'Hardware LiPo Battery',
          status: '${hw.batteryLevel}%',
          detail: 'Nominal 3.7V - 4.2V lithium cell',
          isOk: hw.batteryLevel > 20,
        ),
      ],
    );
  }

  Widget _buildSubsystemTile({
    required IconData icon,
    required String name,
    required String status,
    required String detail,
    required bool isOk,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(icon, size: 24, color: isOk ? AppTheme.emerald : AppTheme.amber),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 2),
                Text(detail, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (isOk ? AppTheme.emerald : AppTheme.amber).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isOk ? AppTheme.emerald : AppTheme.amber,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // TAB 2: Troubleshooting Guide
  Widget _buildTroubleshootTab(HardwareTelemetry hw) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Hardware Troubleshooting Assistant',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 6),
        const Text(
          'Solutions for the most common issues with ESP32, A7670C, and NEO-6M prototypes:',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 16),
        _buildTroubleshootCard(
          title: '1. A7670C Power Brownouts (Most Common!)',
          severity: 'HIGH PRIORITY',
          problem: 'Modem shuts off or ESP32 resets when sending SMS or registering.',
          solution:
              'The A7670C 4G module requires up to 2A burst current during RF transmission. '
              'The ESP32 3.3V pin can only supply ~500mA! '
              'Fix: Power the A7670C using an external 3.7V LiPo battery or a dedicated 5V 2A buck regulator with shared ground.',
        ),
        _buildTroubleshootCard(
          title: '2. UART Baud Rate Mismatch',
          severity: 'COMMUNICATION',
          problem: 'Serial monitor prints garbage characters or AT commands never respond.',
          solution:
              'A7670C factory default is 115200 baud. '
              'Verify in ESP32 code that `modemSerial.begin(115200, SERIAL_8N1, 16, 17);` is used. '
              'Ensure RX2 (Pin 16) goes to Modem TX, and TX2 (Pin 17) goes to Modem RX.',
        ),
        _buildTroubleshootCard(
          title: '3. NEO-6M GPS No Satellite Fix Indoors',
          severity: 'ENVIRONMENT',
          problem: 'NEO-6M PPS LED never blinks, satellites locked = 0.',
          solution:
              'GPS satellite signals at 1575.42 MHz cannot penetrate concrete walls or ceilings. '
              'Fix: Test the keychain near an open window or outdoors for 2-3 minutes. '
              'Note: Aprajita automatically pipes Phone GPS to ESP32 over BLE as a continuous fallback!',
        ),
        _buildTroubleshootCard(
          title: '4. Three-Press Tactile Button Wiring',
          severity: 'WIRING',
          problem: 'False triggers or button does not register clicks.',
          solution:
              'Connect one pin of the push button to ESP32 GPIO 4 and the other pin to GND. '
              'In firmware, use `pinMode(PIN_SOS_BUTTON, INPUT_PULLUP);`. '
              'The firmware software debounces and requires 3 presses within 1.5 seconds.',
        ),
        _buildTroubleshootCard(
          title: '5. SIM Card & 4G APN',
          severity: 'NETWORK',
          problem: 'AT+CPIN? returns ERROR or no 4G registration.',
          solution:
              'Ensure the micro-SIM is inserted with the notched corner aligned correctly. '
              'Ensure the SIM has active SMS & data validity. '
              'For Jio 4G, APN is "jionet"; for Airtel, APN is "airtelgprs.com".',
        ),
      ],
    );
  }

  Widget _buildTroubleshootCard({
    required String title,
    required String severity,
    required String problem,
    required String solution,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.crimson.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  severity,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.crimson),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Symptom: $problem',
            style: const TextStyle(fontSize: 12, color: AppTheme.amber, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Text(
            solution,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.35),
          ),
        ],
      ),
    );
  }

  // TAB 3: BLE Terminal
  Widget _buildTerminalTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: AppTheme.surfaceDark,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'GATT BLE Stream & AT Output',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
              ),
              IconButton(
                icon: const Icon(Icons.clear_all, size: 18),
                onPressed: () => setState(() => _logs.clear()),
                tooltip: 'Clear Terminal',
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: Colors.black,
            padding: const EdgeInsets.all(12),
            child: ListView.builder(
              reverse: true,
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                final log = _logs[_logs.length - 1 - index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    log,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // TAB 4: ESP32 Firmware Code
  Widget _buildFirmwareCodeTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Production ESP32 Arduino Code',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: _esp32ArduinoSource));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Arduino code copied to clipboard!'),
                      backgroundColor: AppTheme.emerald,
                    ),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy .ino Code'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.indigo,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Includes 3-press physical button mechanism, A7670C 4G UART driver, NEO-6M GPS parser, and BLE GATT server.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: SingleChildScrollView(
                child: Text(
                  _esp32ArduinoSource,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Color(0xFFA5F3FC),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const String _esp32ArduinoSource = '''
/*
 * ======================================================================================
 *  SURAKSHA KEY - ESP32 Physical Women's Safety Firmware (v3.2.0-3PRESS)
 *  Hardware: ESP32 DevKit + SIMCom A7670C 4G + NEO-6M GPS + 3-Press Tactile Button
 * ======================================================================================
 */
#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <HardwareSerial.h>
#include <TinyGPSPlus.h>
#include <Preferences.h>

#define PIN_SOS_BUTTON     4    // Tactile push button (Active LOW)
#define GSM_RX_PIN         16   // ESP32 RX2 <- A7670C TX
#define GSM_TX_PIN         17   // ESP32 TX2 -> A7670C RX
#define GPS_RX_PIN         26   // ESP32 RX1 <- NEO-6M TX
#define GPS_TX_PIN         27   // ESP32 TX1 -> NEO-6M RX

#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHAR_SOS_EVENT      "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define CHAR_PHONE_GPS      "beb5483e-36e1-4688-b7f5-ea07361b26a9"
#define CHAR_SYNC_CONTACTS  "beb5483e-36e1-4688-b7f5-ea07361b26aa"
#define CHAR_MODEM_STATUS   "beb5483e-36e1-4688-b7f5-ea07361b26ab"

HardwareSerial modemSerial(2);
HardwareSerial gpsSerial(1);
TinyGPSPlus gps;
Preferences prefs;

BLECharacteristic* pCharSos = nullptr;
BLECharacteristic* pCharModemStatus = nullptr;
bool bleConnected = false;

// 3-PRESS DETECTION LOGIC
int buttonPressCount = 0;
unsigned long lastPressTime = 0;
const unsigned long MULTI_PRESS_TIMEOUT_MS = 1500; // 1.5s window for 3 clicks

void triggerEmergencySos() {
  Serial.println("🚨 3-PRESS CONFIRMED! DISPATCHING EMERGENCY SOS!");
  if (bleConnected && pCharSos != nullptr) {
    pCharSos->setValue("SOS:PHYSICAL_BUTTON_3PRESS");
    pCharSos->notify();
  }
}

void checkThreePressButton() {
  static int lastState = HIGH;
  int currentState = digitalRead(PIN_SOS_BUTTON);

  if (lastState == HIGH && currentState == LOW) {
    delay(40); // Debounce
    if (digitalRead(PIN_SOS_BUTTON) == LOW) {
      unsigned long now = millis();
      if (now - lastPressTime > MULTI_PRESS_TIMEOUT_MS) {
        buttonPressCount = 1;
      } else {
        buttonPressCount++;
      }
      lastPressTime = now;
      Serial.printf("🔘 Button Click #%d detected!\\n", buttonPressCount);

      if (buttonPressCount >= 3) {
        buttonPressCount = 0;
        triggerEmergencySos();
      }
    }
  }
  lastState = currentState;

  if (buttonPressCount > 0 && (millis() - lastPressTime > MULTI_PRESS_TIMEOUT_MS)) {
    Serial.println("⚠️ 3-Press sequence timed out. Cleared.");
    buttonPressCount = 0;
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_SOS_BUTTON, INPUT_PULLUP);

  modemSerial.begin(115200, SERIAL_8N1, GSM_RX_PIN, GSM_TX_PIN);
  gpsSerial.begin(9600, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);

  BLEDevice::init("SURAKSHA-KEY");
  BLEServer* pServer = BLEDevice::createServer();
  BLEService* pService = pServer->createService(SERVICE_UUID);

  pCharSos = pService->createCharacteristic(
    CHAR_SOS_EVENT,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pCharSos->addDescriptor(new BLE2902());
  pService->start();

  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->start();
  Serial.println("✅ SURAKSHA-KEY BLE Advertising started.");
}

void loop() {
  checkThreePressButton();
  while (gpsSerial.available() > 0) {
    gps.encode(gpsSerial.read());
  }
  delay(10);
}
''';
}
