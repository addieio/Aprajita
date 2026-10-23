import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/storage_service.dart';
import '../services/twilio_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';

class SettingsView extends StatefulWidget {
  final StorageService storageService;
  final TwilioService twilioService;
  final SupabaseService supabaseService;

  const SettingsView({
    super.key,
    required this.storageService,
    required this.twilioService,
    required this.supabaseService,
  });

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late TextEditingController _twilioPhoneCtrl;
  late TextEditingController _twilioSidCtrl;
  late TextEditingController _twilioTokenCtrl;
  bool _twilioEnabled = true;
  bool _obscureToken = true;

  late TextEditingController _supabaseUrlCtrl;
  late TextEditingController _supabaseKeyCtrl;

  late int _countdownSeconds;
  late bool _volumeSosEnabled;

  @override
  void initState() {
    super.initState();
    final twilio = widget.storageService.loadTwilioConfig();
    _twilioPhoneCtrl = TextEditingController(text: twilio['phoneNo'] ?? '');
    _twilioSidCtrl = TextEditingController(text: twilio['accountSid'] ?? '');
    _twilioTokenCtrl = TextEditingController(text: twilio['authToken'] ?? '');
    _twilioEnabled = twilio['enabled'] == 'true';

    final supabase = widget.storageService.loadSupabaseConfig();
    _supabaseUrlCtrl = TextEditingController(text: supabase['url'] ?? '');
    _supabaseKeyCtrl = TextEditingController(text: supabase['anonKey'] ?? '');

    _countdownSeconds = widget.storageService.getSosCountdownSeconds();
    _volumeSosEnabled = widget.storageService.isVolumeSosEnabled();
  }

  Future<void> _saveTwilio() async {
    await widget.storageService.saveTwilioConfig(
      phoneNo: _twilioPhoneCtrl.text.trim(),
      accountSid: _twilioSidCtrl.text.trim(),
      authToken: _twilioTokenCtrl.text.trim(),
      enabled: _twilioEnabled,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Emergency SMS gateway configuration saved!'),
        backgroundColor: AppTheme.emerald,
      ),
    );
  }

  Future<void> _saveSupabase() async {
    await widget.storageService.saveSupabaseConfig(
      url: _supabaseUrlCtrl.text.trim(),
      anonKey: _supabaseKeyCtrl.text.trim(),
      enabled: _supabaseUrlCtrl.text.trim().isNotEmpty,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Supabase backend settings saved!'),
        backgroundColor: AppTheme.emerald,
      ),
    );
  }

  void _showSqlSchemaModal() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Supabase SQL Schema', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.copy, size: 20),
              tooltip: 'Copy SQL to Clipboard',
              onPressed: () {
                Clipboard.setData(const ClipboardData(text: SupabaseService.sqlSchemaScript));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied SQL schema to clipboard! Paste into Supabase SQL editor.'),
                    backgroundColor: AppTheme.emerald,
                  ),
                );
              },
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Run this script once in your Supabase project SQL Editor to create tables for SOS Alerts, Nearby Broadcasts, and Contacts.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              Container(
                height: 220,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const SingleChildScrollView(
                  child: Text(
                    SupabaseService.sqlSchemaScript,
                    style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: Color(0xFF6EE7B7)),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: SupabaseService.sqlSchemaScript));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('SQL schema copied to clipboard!'),
                  backgroundColor: AppTheme.emerald,
                ),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy SQL Script'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.emerald),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Settings & Integrations'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // APP BRAND LOGO & INFO
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: const AppLogo(size: 68, withText: true),
            ),
          ),
          const SizedBox(height: 12),

          // EMERGENCY CLOUD SMS GATEWAY SECTION
          _buildSectionHeader('CLOUD EMERGENCY SMS GATEWAY', Icons.sms_outlined),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable Cloud SMS Dispatch', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('Sends distress alerts with Google Maps location links', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  value: _twilioEnabled,
                  activeThumbColor: AppTheme.crimson,
                  onChanged: (val) {
                    setState(() => _twilioEnabled = val);
                    _saveTwilio();
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _twilioPhoneCtrl,
                  decoration: InputDecoration(
                    labelText: 'Virtual Dispatch Phone Number',
                    hintText: '+1234567890',
                    filled: true,
                    fillColor: AppTheme.surfaceDark,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _twilioSidCtrl,
                  decoration: InputDecoration(
                    labelText: 'Account SID',
                    hintText: 'ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
                    filled: true,
                    fillColor: AppTheme.surfaceDark,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _twilioTokenCtrl,
                  obscureText: _obscureToken,
                  decoration: InputDecoration(
                    labelText: 'Account Auth Token',
                    filled: true,
                    fillColor: AppTheme.surfaceDark,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureToken ? Icons.visibility : Icons.visibility_off, size: 20),
                      onPressed: () => setState(() => _obscureToken = !_obscureToken),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saveTwilio,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.crimson,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Save SMS Gateway Settings'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // SUPABASE BACKEND SECTION
          _buildSectionHeader('SUPABASE BACKEND INTEGRATION', Icons.cloud_done_outlined),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Powering the Realtime Nearby Community alerts and cross-device sync.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _supabaseUrlCtrl,
                  decoration: InputDecoration(
                    labelText: 'Supabase Project URL',
                    hintText: 'https://xxxxxxxx.supabase.co',
                    filled: true,
                    fillColor: AppTheme.surfaceDark,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _supabaseKeyCtrl,
                  decoration: InputDecoration(
                    labelText: 'Supabase Anon Public API Key',
                    hintText: 'eyJhbGciOiJIUzI1NiIsIn...',
                    filled: true,
                    fillColor: AppTheme.surfaceDark,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _showSqlSchemaModal,
                        icon: const Icon(Icons.code, size: 16),
                        label: const Text('Get SQL Schema'),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.emerald),
                          foregroundColor: AppTheme.emerald,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saveSupabase,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.emerald,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Save Supabase'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // SOS CANCELLATION COUNTDOWN DURATION
          _buildSectionHeader('SOS CANCELLATION WINDOW', Icons.timer_outlined),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pre-dispatch countdown window to abort accidental triggers before SMS or community broadcast is sent.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [3, 5, 10].map((sec) {
                    final isSelected = _countdownSeconds == sec;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ElevatedButton(
                          onPressed: () async {
                            setState(() => _countdownSeconds = sec);
                            await widget.storageService.setSosCountdownSeconds(sec);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isSelected ? AppTheme.crimson : AppTheme.surfaceDark,
                            foregroundColor: isSelected ? Colors.white : AppTheme.textSecondary,
                            elevation: isSelected ? 4 : 0,
                          ),
                          child: Text('$sec Seconds'),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // PHONE HARDWARE BUTTON SOS
          _buildSectionHeader('PHONE PHYSICAL BUTTON SOS', Icons.volume_up_rounded),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Volume Up 4-Press SOS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('Rapidly click phone Volume Up button 4 times to dispatch emergency SOS automatically', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  value: _volumeSosEnabled,
                  activeThumbColor: AppTheme.crimson,
                  onChanged: (val) async {
                    setState(() => _volumeSosEnabled = val);
                    await widget.storageService.setVolumeSosEnabled(val);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // HARDWARE SPECIFICATIONS SUMMARY
          _buildSectionHeader('HARDWARE SPECIFICATIONS', Icons.memory),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'APRAJITA SAFETY KEYCHAIN (ESP32-A7670C-NEO6M)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                SizedBox(height: 6),
                Text('• MCU: ESP-WROOM-32 240MHz Dual-Core', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                Text('• Cellular Modem: SIMCom A7670C 4G LTE Cat-1 (UART2: RX=16, TX=17)', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                Text('• GPS Receiver: u-blox NEO-6M High-Sensitivity (UART1: RX=26, TX=27)', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                Text('• SOS Trigger: 3-Press Tactile Pushbutton (GPIO 4 with INPUT_PULLUP)', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                Text('• Flash Memory: Preferences.h NVS autonomous contact storage', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.crimson),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
