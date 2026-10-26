import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'services/storage_service.dart';
import 'services/location_service.dart';
import 'services/hardware_service.dart';
import 'services/twilio_service.dart';
import 'services/supabase_service.dart';
import 'services/nearby_community_service.dart';
import 'services/emergency_service.dart';
import 'views/home_view.dart';
import 'views/contacts_view.dart';
import 'views/hardware_view.dart';
import 'views/nearby_view.dart';
import 'views/history_view.dart';
import 'views/settings_view.dart';
import 'widgets/sos_countdown_dialog.dart';
import 'widgets/app_logo.dart';
import 'services/volume_button_service.dart';

import 'services/hindsight_service.dart';
import 'services/groq_service.dart';
import 'views/ai_companion_view.dart';
import 'views/gif_customizer_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final storageService = await StorageService.init();
  final locationService = LocationService();
  final hardwareService = HardwareService();
  final twilioService = TwilioService(storageService);
  final supabaseService = SupabaseService(storageService);
  final nearbyService = NearbyCommunityService(supabaseService);
  final hindsightService = HindsightService(storageService);
  final groqService = GroqService(storageService, hindsightService);

  // Pipe phone GPS coordinates live to physical ESP32 over BLE
  locationService.locationStream.listen((loc) {
    hardwareService.sendPhoneGpsToEsp32(loc.lat, loc.lng, loc.accuracy);
  });
  Timer.periodic(const Duration(seconds: 8), (_) async {
    final loc = locationService.currentLocation;
    if (loc != null) {
      hardwareService.sendPhoneGpsToEsp32(loc.lat, loc.lng, loc.accuracy);
    }
  });

  final emergencyService = EmergencyService(
    storageService: storageService,
    twilioService: twilioService,
    locationService: locationService,
    hardwareService: hardwareService,
    nearbyService: nearbyService,
    hindsightService: hindsightService,
  );

  final volumeButtonService = VolumeButtonService(
    storageService: storageService,
    emergencyService: emergencyService,
    hardwareService: hardwareService,
  );

  runApp(AprajitaApp(
    storageService: storageService,
    locationService: locationService,
    hardwareService: hardwareService,
    twilioService: twilioService,
    supabaseService: supabaseService,
    nearbyService: nearbyService,
    emergencyService: emergencyService,
    volumeButtonService: volumeButtonService,
    hindsightService: hindsightService,
    groqService: groqService,
  ));
}

class AprajitaApp extends StatelessWidget {
  final StorageService storageService;
  final LocationService locationService;
  final HardwareService hardwareService;
  final TwilioService twilioService;
  final SupabaseService supabaseService;
  final NearbyCommunityService nearbyService;
  final EmergencyService emergencyService;
  final VolumeButtonService volumeButtonService;
  final HindsightService hindsightService;
  final GroqService groqService;

  const AprajitaApp({
    super.key,
    required this.storageService,
    required this.locationService,
    required this.hardwareService,
    required this.twilioService,
    required this.supabaseService,
    required this.nearbyService,
    required this.emergencyService,
    required this.volumeButtonService,
    required this.hindsightService,
    required this.groqService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aprajita - AI Safety Agent',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: AppShell(
        storageService: storageService,
        locationService: locationService,
        hardwareService: hardwareService,
        twilioService: twilioService,
        supabaseService: supabaseService,
        nearbyService: nearbyService,
        emergencyService: emergencyService,
        volumeButtonService: volumeButtonService,
        hindsightService: hindsightService,
        groqService: groqService,
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  final StorageService storageService;
  final LocationService locationService;
  final HardwareService hardwareService;
  final TwilioService twilioService;
  final SupabaseService supabaseService;
  final NearbyCommunityService nearbyService;
  final EmergencyService emergencyService;
  final VolumeButtonService volumeButtonService;
  final HindsightService hindsightService;
  final GroqService groqService;

  const AppShell({
    super.key,
    required this.storageService,
    required this.locationService,
    required this.hardwareService,
    required this.twilioService,
    required this.supabaseService,
    required this.nearbyService,
    required this.emergencyService,
    required this.volumeButtonService,
    required this.hindsightService,
    required this.groqService,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final views = [
      HomeView(
        emergencyService: widget.emergencyService,
        hardwareService: widget.hardwareService,
        locationService: widget.locationService,
        storageService: widget.storageService,
        twilioService: widget.twilioService,
        onNavigateToContacts: () => setState(() => _currentIndex = 4),
        onNavigateToHardware: () => setState(() => _currentIndex = 2),
        onNavigateToAi: () => setState(() => _currentIndex = 1),
        onNavigateToGif: () => setState(() => _currentIndex = 3),
      ),
      AiCompanionView(
        groqService: widget.groqService,
        hindsightService: widget.hindsightService,
        storageService: widget.storageService,
        twilioService: widget.twilioService,
        locationService: widget.locationService,
      ),
      HardwareView(
        hardwareService: widget.hardwareService,
      ),
      GifCustomizerView(
        storageService: widget.storageService,
        hardwareService: widget.hardwareService,
      ),
      ContactsView(
        storageService: widget.storageService,
        hardwareService: widget.hardwareService,
        twilioService: widget.twilioService,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const AppLogo(size: 36, withText: true),
        shape: const Border(
          bottom: BorderSide(color: AppTheme.borderSubtle, width: 0.8),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.near_me_outlined, size: 20),
            tooltip: 'Nearby Distress Radar',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => NearbyView(
                    nearbyService: widget.nearbyService,
                    locationService: widget.locationService,
                    supabaseService: widget.supabaseService,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history_rounded, size: 20),
            tooltip: 'SOS History',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => HistoryView(
                    storageService: widget.storageService,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded, size: 20),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => SettingsView(
                    storageService: widget.storageService,
                    twilioService: widget.twilioService,
                    supabaseService: widget.supabaseService,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: views,
          ),
          // Emergency Pre-Dispatch Countdown Overlay (Appears on any tab)
          SosCountdownDialog(
            emergencyService: widget.emergencyService,
          ),
          // Live floating visual feedback when Volume Up button is pressed
          StreamBuilder<int>(
            stream: widget.volumeButtonService.pressCountStream,
            initialData: 0,
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              if (count <= 0 || count >= 4) return const SizedBox.shrink();

              return Positioned(
                top: 16,
                left: 20,
                right: 20,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.cardElevated,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppTheme.crimson.withValues(alpha: 0.6)),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.crimson.withValues(alpha: 0.25),
                          blurRadius: 16,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.volume_up, color: AppTheme.crimson, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Volume Up ($count/4) • Press ${4 - count} more for SOS',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: _currentIndex != 1
          ? FloatingActionButton.extended(
              onPressed: () => setState(() => _currentIndex = 1),
              backgroundColor: const Color(0xFF10B981),
              icon: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 20),
              label: const Text(
                'AI Safety Agent',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.3,
                  fontSize: 13,
                ),
              ),
            )
          : null,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surfaceDark,
          border: Border(
            top: BorderSide(color: AppTheme.borderSubtle, width: 0.8),
          ),
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: AppTheme.surfaceDark,
          selectedItemColor: AppTheme.crimson,
          unselectedItemColor: Colors.white70,
          elevation: 0,
          selectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.3),
          unselectedLabelStyle: const TextStyle(fontSize: 10, letterSpacing: 0.2),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.shield_outlined),
              activeIcon: Icon(Icons.shield),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.psychology_outlined),
              activeIcon: Icon(Icons.psychology),
              label: 'AI Agent',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.memory_outlined),
              activeIcon: Icon(Icons.memory),
              label: 'Hardware',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.animation_outlined),
              activeIcon: Icon(Icons.animation),
              label: 'Screen GIF',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline),
              activeIcon: Icon(Icons.people),
              label: 'Contacts',
            ),
          ],
        ),
      ),
    );
  }
}
