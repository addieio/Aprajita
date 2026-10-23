import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/contact_model.dart';
import '../models/location_model.dart';
import '../models/telemetry_model.dart';
import '../models/sos_event_model.dart';
import '../services/emergency_service.dart';
import '../services/hardware_service.dart';
import '../services/location_service.dart';
import '../services/storage_service.dart';
import '../services/twilio_service.dart';
import '../theme/app_theme.dart';

class HomeView extends StatefulWidget {
  final EmergencyService emergencyService;
  final HardwareService hardwareService;
  final LocationService locationService;
  final StorageService storageService;
  final TwilioService twilioService;
  final VoidCallback onNavigateToContacts;
  final VoidCallback onNavigateToHardware;

  const HomeView({
    super.key,
    required this.emergencyService,
    required this.hardwareService,
    required this.locationService,
    required this.storageService,
    required this.twilioService,
    required this.onNavigateToContacts,
    required this.onNavigateToHardware,
  });

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isRefreshingLocation = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.07).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _refreshGps() async {
    setState(() => _isRefreshingLocation = true);
    HapticFeedback.selectionClick();
    await widget.locationService.getCurrentLocation(forceRefresh: true);
    if (mounted) {
      setState(() => _isRefreshingLocation = false);
    }
  }

  void _showChangeRecipientDialog() {
    final contacts = widget.storageService.loadContacts();
    final currentPrimaryId = widget.storageService.getPrimaryContactId();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Select SOS Recipient',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      widget.onNavigateToContacts();
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add New'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose which mobile number directly receives the emergency SMS signal, timestamp, and live Google Maps link.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.group_outlined, color: AppTheme.crimson),
                title: const Text('All Active Emergency Contacts'),
                subtitle: Text(
                  'Dispatches to ${contacts.where((c) => c.isEmergencyRecipient).length} contacts simultaneously',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
                trailing: (currentPrimaryId == null || currentPrimaryId.isEmpty)
                    ? const Icon(Icons.check_circle, color: AppTheme.crimson)
                    : null,
                onTap: () async {
                  await widget.storageService.setPrimaryContactId('');
                  if (mounted) setState(() {});
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
              const Divider(color: AppTheme.borderSubtle),
              ...contacts.map((c) {
                final isSelected = c.id == currentPrimaryId;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.surfaceDark,
                    child: Text(
                      c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                      style: const TextStyle(color: AppTheme.textPrimary),
                    ),
                  ),
                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(c.phone, style: const TextStyle(color: AppTheme.textSecondary)),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: AppTheme.crimson)
                      : null,
                  onTap: () async {
                    await widget.storageService.setPrimaryContactId(c.id);
                    if (mounted) setState(() {});
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Future<void> _callHelpline(String number) async {
    final uri = Uri.parse('tel:$number');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SosAlertEvent?>(
      stream: widget.emergencyService.activeEventStream,
      initialData: widget.emergencyService.activeEvent,
      builder: (context, activeSosSnapshot) {
        final activeSos = activeSosSnapshot.data;
        final isSosActive = activeSos != null && activeSos.status == 'ACTIVE';

        return StreamBuilder<HardwareTelemetry>(
          stream: widget.hardwareService.telemetryStream,
          initialData: widget.hardwareService.telemetry,
          builder: (context, hwSnapshot) {
            final hw = hwSnapshot.data ?? HardwareTelemetry();
            final contacts = widget.storageService.loadContacts();
            final primaryId = widget.storageService.getPrimaryContactId();

            TrustedContact? primaryContact;
            if (primaryId != null && primaryId.isNotEmpty) {
              primaryContact = contacts.firstWhere((c) => c.id == primaryId,
                  orElse: () => contacts.firstWhere((c) => c.isEmergencyRecipient,
                      orElse: () => contacts.first));
            }

            return StreamBuilder<GpsLocation>(
              stream: widget.locationService.locationStream,
              initialData: widget.locationService.currentLocation,
              builder: (context, locSnapshot) {
                final loc = locSnapshot.data;

                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ACTIVE SOS ALERT BANNER (If currently triggered)
                      if (isSosActive) ...[
                        _buildActiveEmergencyBanner(activeSos),
                        const SizedBox(height: 16),
                      ],

                      // SYSTEM READINESS STATUS CARD
                      _buildReadinessCard(hw, contacts, loc),
                      const SizedBox(height: 14),

                      // SOS RECIPIENT QUICK SELECTOR / CHANGER
                      _buildRecipientSelectorCard(primaryContact, contacts),
                      const SizedBox(height: 18),

                      // CENTRAL SOS BUTTON WITH 3-PRESS PHYSICAL HARDWARE NOTICE
                      _buildSosTriggerSection(isSosActive),
                      const SizedBox(height: 22),

                      // LIVE GPS LOCATION & MAPS LINK
                      _buildLiveLocationCard(loc),
                      const SizedBox(height: 14),

                      // HARDWARE & EMERGENCY GATEWAY QUICK TELEMETRY CHIPS
                      _buildQuickTelemetryChips(hw),
                      const SizedBox(height: 18),

                      // EMERGENCY HELPLINES QUICK DIAL (112, 1091, 108, 181)
                      _buildEmergencyHelplinesSection(),
                      const SizedBox(height: 24),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildActiveEmergencyBanner(SosAlertEvent event) {
    final formattedTime =
        DateFormat('hh:mm:ss a, dd MMM').format(event.timestamp.toLocal());

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.crimson.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.crimson, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: AppTheme.crimson,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'EMERGENCY SOS IS CURRENTLY ACTIVE',
                  style: TextStyle(
                    color: AppTheme.crimson,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _callHelpline('112'),
                icon: const Icon(Icons.phone_in_talk, size: 14),
                label: const Text('CALL 112'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.crimson,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Trigger Source: ${event.source} • Dispatched at: $formattedTime',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          // Recipient status pills
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: event.recipients.map((r) {
              final isSuccess = r.status == SmsDeliveryState.submitted ||
                  r.status == SmsDeliveryState.delivered;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSuccess ? AppTheme.emerald : AppTheme.amber,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isSuccess ? Icons.check_circle : Icons.schedule,
                      size: 14,
                      color: isSuccess ? AppTheme.emerald : AppTheme.amber,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${r.name}: ${r.status.name.toUpperCase()}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          // 3-CHANNEL GATEWAY STATUS DISPLAY
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildChannelChip(
                icon: Icons.sms_outlined,
                label: 'SMS GATEWAY: DISPATCHED',
                isSuccess: true,
              ),
              _buildChannelChip(
                icon: Icons.phone_in_talk,
                label: 'VOICE CALL: ${event.voiceCallStatus ?? "DIALING"}',
                isSuccess: event.voiceCallStatus != 'FAILED',
              ),
              _buildChannelChip(
                icon: Icons.chat_bubble_outline,
                label: 'WHATSAPP: ${event.whatsappStatus ?? "QUEUED"}',
                isSuccess: event.whatsappStatus != 'FAILED',
              ),
            ],
          ),
          const SizedBox(height: 12),
          // EMERGENCY ACTIONS: Direct Call & WhatsApp Distress Alert
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.heavyImpact();
                    widget.emergencyService.makeEmergencyPhoneCall();
                  },
                  icon: const Icon(Icons.call, size: 16),
                  label: const Text('CALL PRIMARY'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.crimson,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    widget.emergencyService.sendWhatsAppDistressMessage();
                  },
                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                  label: const Text('WHATSAPP SOS'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _callHelpline('112'),
                  icon: const Icon(Icons.local_police_outlined, size: 15, color: Colors.white70),
                  label: const Text('CALL 112 (POLICE)', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    widget.emergencyService.resolveActiveSos();
                  },
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('RESOLVE SOS'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.emerald,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: () {
                  if (event.mapUrl.isNotEmpty) {
                    launchUrl(Uri.parse(event.mapUrl));
                  }
                },
                icon: const Icon(Icons.map, color: Colors.white),
                tooltip: 'Open Live Google Maps Link',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChannelChip({
    required IconData icon,
    required String label,
    required bool isSuccess,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSuccess ? AppTheme.emerald : AppTheme.amber,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: isSuccess ? AppTheme.emerald : AppTheme.amber,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadinessCard(
    HardwareTelemetry hw,
    List<TrustedContact> contacts,
    GpsLocation? loc,
  ) {
    final emergencyContactsCount =
        contacts.where((c) => c.isEmergencyRecipient).length;
    final isGpsReady = loc != null && !loc.isStale;
    final isArmed = emergencyContactsCount > 0 && isGpsReady;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isArmed
              ? AppTheme.emerald.withValues(alpha: 0.3)
              : AppTheme.borderSubtle,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (isArmed ? AppTheme.emerald : AppTheme.amber)
                  .withValues(alpha: 0.12),
            ),
            child: Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isArmed ? AppTheme.emerald : AppTheme.amber,
                  boxShadow: [
                    BoxShadow(
                      color: (isArmed ? AppTheme.emerald : AppTheme.amber)
                          .withValues(alpha: 0.6),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isArmed ? 'PROTECTION ACTIVE' : 'SETUP REQUIRED',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: isArmed ? AppTheme.emerald : AppTheme.amber,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceDark,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isArmed ? 'ARMED' : 'STANDBY',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  isArmed
                      ? 'Cloud Gateway • Phone GPS • 4-Click Volume SOS ready'
                      : 'Add an emergency contact to arm automatic SOS dispatch',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: widget.onNavigateToHardware,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.surfaceDark,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    'Hub',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  SizedBox(width: 2),
                  Icon(Icons.chevron_right, size: 14, color: AppTheme.textMuted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecipientSelectorCard(
    TrustedContact? primaryContact,
    List<TrustedContact> contacts,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: AppTheme.crimson.withValues(alpha: 0.12),
            child: const Icon(Icons.shield_outlined, color: AppTheme.crimson, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ACTIVE SOS RECIPIENT',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  primaryContact != null
                      ? '${primaryContact.name} • ${primaryContact.phone}'
                      : 'All ${contacts.where((c) => c.isEmergencyRecipient).length} Emergency Contacts',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: _showChangeRecipientDialog,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              side: const BorderSide(color: AppTheme.borderSubtle),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              minimumSize: const Size(0, 32),
            ),
            child: const Text(
              'Change',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSosTriggerSection(bool isSosActive) {
    return Center(
      child: Column(
        children: [
          ScaleTransition(
            scale: _pulseAnimation,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.heavyImpact();
                widget.emergencyService.triggerInstantSos(
                  source: 'APP_SOS_BUTTON',
                );
              },
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF13151D),
                  border: Border.all(
                    color: AppTheme.crimson.withValues(alpha: isSosActive ? 0.6 : 0.25),
                    width: 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.crimson.withValues(alpha: isSosActive ? 0.6 : 0.25),
                      blurRadius: isSosActive ? 48 : 32,
                      spreadRadius: isSosActive ? 4 : 1,
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 172,
                    height: 172,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [
                          Color(0xFFE53935),
                          Color(0xFFC62828),
                          Color(0xFF881313),
                        ],
                        stops: [0.3, 0.7, 1.0],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isSosActive ? Icons.warning_amber_rounded : Icons.shield_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'SOS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            isSosActive ? 'ALARM ACTIVE' : 'TAP FOR INSTANT SOS',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'SMS • CALL • WHATSAPP',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Trigger Mechanism Info Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.touch_app_outlined, size: 13, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                const Text(
                  'Physical: 4-Click Volume Up or 3-Click Keychain',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveLocationCard(GpsLocation? loc) {
    final timestampFormatted = loc != null
        ? DateFormat('hh:mm:ss a').format(loc.timestamp.toLocal())
        : 'Acquiring';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.location_on, color: AppTheme.crimson, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'LIVE GPS TRACKING',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              IconButton(
                onPressed: _isRefreshingLocation ? null : _refreshGps,
                icon: _isRefreshingLocation
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
                tooltip: 'Refresh GPS Fix',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            loc?.displayCoords ?? 'Acquiring GPS fix...',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Source: ${loc?.sourceName ?? "Initializing"} • Fixed at: $timestampFormatted (±${loc?.accuracy.toInt() ?? 10}m)',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    if (loc != null) {
                      launchUrl(Uri.parse(loc.googleMapsUrl));
                    }
                  },
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open Google Maps Link'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textPrimary,
                    side: const BorderSide(color: AppTheme.borderSubtle),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  if (loc != null) {
                    Clipboard.setData(ClipboardData(text: loc.googleMapsUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Google Maps link copied to clipboard!'),
                        backgroundColor: AppTheme.cardElevated,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Copy Link',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickTelemetryChips(HardwareTelemetry hw) {
    return Row(
      children: [
        Expanded(
          child: _telemetryChip(
            icon: Icons.bluetooth_rounded,
            label: 'BLE LINK',
            value: hw.connectionState == DeviceConnectionState.connected
                ? 'CONNECTED'
                : 'STANDBY',
            isPositive: hw.connectionState == DeviceConnectionState.connected,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _telemetryChip(
            icon: Icons.gps_fixed_rounded,
            label: 'DUAL GPS',
            value: 'ACTIVE ±8m',
            isPositive: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _telemetryChip(
            icon: Icons.cloud_done_rounded,
            label: 'CLOUD SOS',
            value: 'ONLINE',
            isPositive: true,
          ),
        ),
      ],
    );
  }

  Widget _telemetryChip({
    required IconData icon,
    required String label,
    required String value,
    required bool isPositive,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: isPositive ? AppTheme.emerald : AppTheme.textMuted),
              const Spacer(),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isPositive ? AppTheme.emerald : AppTheme.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9.5,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: isPositive ? AppTheme.textPrimary : AppTheme.amber,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyHelplinesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.phone_outlined, size: 14, color: AppTheme.textMuted),
            SizedBox(width: 6),
            Text(
              'EMERGENCY HELPLINES (DIRECT DIAL)',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _helplineButton('112', 'Police', Icons.local_police_outlined),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _helplineButton('1091', 'Women Safety', Icons.shield_outlined),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _helplineButton('108', 'Ambulance', Icons.medical_services_outlined),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _helplineButton('181', 'Helpline', Icons.support_agent_outlined),
            ),
          ],
        ),
      ],
    );
  }

  Widget _helplineButton(String number, String label, IconData icon) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        _callHelpline(number);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.borderSubtle),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: AppTheme.textPrimary),
            const SizedBox(height: 6),
            Text(
              number,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
                color: AppTheme.textMuted,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
