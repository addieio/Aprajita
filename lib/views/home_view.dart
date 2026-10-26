import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
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
  final VoidCallback? onNavigateToAi;
  final VoidCallback? onNavigateToGif;

  const HomeView({
    super.key,
    required this.emergencyService,
    required this.hardwareService,
    required this.locationService,
    required this.storageService,
    required this.twilioService,
    required this.onNavigateToContacts,
    required this.onNavigateToHardware,
    this.onNavigateToAi,
    this.onNavigateToGif,
  });

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isRefreshingLocation = false;
  StreamSubscription<List<TrustedContact>>? _contactsSubscription;

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

    _contactsSubscription = widget.storageService.contactsStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _contactsSubscription?.cancel();
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

  void _showAddEditContactDialog({
    TrustedContact? existing,
    VoidCallback? onSaved,
  }) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    bool isRecipient = existing?.isEmergencyRecipient ?? true;
    String? errorText;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (stfCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.cardDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: AppTheme.borderSubtle),
              ),
              title: Row(
                children: [
                  Icon(
                    existing == null ? Icons.person_add_rounded : Icons.edit_note_rounded,
                    color: AppTheme.crimson,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      existing == null ? 'Add Trusted Contact' : 'Edit Contact',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Emergency alerts, live GPS maps links, and emergency SMS will be sent to this number.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Contact Name',
                        hintText: 'e.g. Mother, Sister, Friend',
                        prefixIcon: const Icon(Icons.person_outline, size: 20),
                        filled: true,
                        fillColor: AppTheme.surfaceDark,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Mobile Number',
                        hintText: 'e.g. 9876543210 or +91 98765 43210',
                        prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                        errorText: errorText,
                        filled: true,
                        fillColor: AppTheme.surfaceDark,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Include in SOS Dispatch', style: TextStyle(fontSize: 14)),
                      subtitle: const Text('Receives automated emergency SMS & GPS', style: TextStyle(fontSize: 11)),
                      value: isRecipient,
                      activeThumbColor: AppTheme.crimson,
                      onChanged: (val) {
                        setDialogState(() => isRecipient = val);
                      },
                    ),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              actions: [
                if (existing != null)
                  TextButton.icon(
                    onPressed: () async {
                      if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                      if (!mounted) return;
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (delCtx) => AlertDialog(
                          backgroundColor: AppTheme.cardDark,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          title: const Text('Remove Contact?'),
                          content: Text('Are you sure you want to remove ${existing.name} (${existing.phone})?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(delCtx, false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(delCtx, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.crimson,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await widget.storageService.deleteContact(existing.id);
                        onSaved?.call();
                        if (mounted) {
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Removed ${existing.name} (${existing.phone})'),
                              backgroundColor: AppTheme.crimson,
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.delete_outline, color: AppTheme.crimson, size: 18),
                    label: const Text('Delete', style: TextStyle(color: AppTheme.crimson, fontWeight: FontWeight.bold)),
                  ),
                TextButton(
                  onPressed: () {
                    if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  },
                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final rawPhone = phoneCtrl.text.trim();

                    if (name.isEmpty) {
                      setDialogState(() => errorText = 'Please enter a contact name');
                      return;
                    }

                    final validation = TrustedContact.validatePhone(rawPhone);
                    if (!validation.isValid) {
                      setDialogState(() => errorText = validation.message);
                      return;
                    }

                    final formattedPhone = validation.formattedNumber!;

                    if (existing == null) {
                      final newContact = TrustedContact(
                        id: const Uuid().v4(),
                        name: name,
                        phone: formattedPhone,
                        isEmergencyRecipient: isRecipient,
                        isPrimary: widget.storageService.loadContacts().isEmpty,
                      );
                      await widget.storageService.addContact(newContact);
                    } else {
                      final updated = existing.copyWith(
                        name: name,
                        phone: formattedPhone,
                        isEmergencyRecipient: isRecipient,
                      );
                      await widget.storageService.updateContact(updated);
                    }

                    onSaved?.call();
                    if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                    if (mounted) {
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(existing == null ? 'Contact "$name" added' : 'Contact "$name" updated'),
                          backgroundColor: AppTheme.emerald,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.crimson,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(existing == null ? 'Add Contact' : 'Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showChangeRecipientDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetCtx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final contacts = widget.storageService.loadContacts();
            final currentPrimaryId = widget.storageService.getPrimaryContactId();

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.70,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  child: Column(
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
                              _showAddEditContactDialog(
                                onSaved: () {
                                  if (bottomSheetCtx.mounted) setModalState(() {});
                                },
                              );
                            },
                            icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                            label: const Text('Add Contact'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tap a contact to set as active emergency recipient, or use Edit/Delete to manage numbers.',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      if (contacts.isNotEmpty) ...[
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
                            if (bottomSheetCtx.mounted) Navigator.pop(bottomSheetCtx);
                          },
                        ),
                        const Divider(color: AppTheme.borderSubtle),
                        Expanded(
                          child: ListView.builder(
                            itemCount: contacts.length,
                            itemBuilder: (itemCtx, idx) {
                              final c = contacts[idx];
                              final isSelected = c.id == currentPrimaryId;

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: isSelected ? AppTheme.crimson.withValues(alpha: 0.2) : AppTheme.surfaceDark,
                                  child: Text(
                                    c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                                    style: TextStyle(color: isSelected ? AppTheme.crimson : AppTheme.textPrimary, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        c.name,
                                        style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isSelected) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: AppTheme.crimson,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text('ACTIVE', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white)),
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: Text(c.phone, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 19, color: AppTheme.indigo),
                                      tooltip: 'Edit Contact',
                                      onPressed: () {
                                        _showAddEditContactDialog(
                                          existing: c,
                                          onSaved: () {
                                            if (bottomSheetCtx.mounted) setModalState(() {});
                                          },
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 19, color: AppTheme.crimson),
                                      tooltip: 'Delete Contact',
                                      onPressed: () async {
                                        final confirmed = await showDialog<bool>(
                                          context: context,
                                          builder: (delCtx) => AlertDialog(
                                            backgroundColor: AppTheme.cardDark,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                            title: const Text('Remove Contact?'),
                                            content: Text('Are you sure you want to remove ${c.name} (${c.phone})?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(delCtx, false),
                                                child: const Text('Cancel'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () => Navigator.pop(delCtx, true),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: AppTheme.crimson,
                                                  foregroundColor: Colors.white,
                                                ),
                                                child: const Text('Remove'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirmed == true) {
                                          await widget.storageService.deleteContact(c.id);
                                          final remaining = widget.storageService.loadContacts();
                                          if (remaining.isEmpty) {
                                            if (bottomSheetCtx.mounted) Navigator.pop(bottomSheetCtx);
                                          } else {
                                            if (bottomSheetCtx.mounted) setModalState(() {});
                                          }
                                          if (mounted) {
                                            setState(() {});
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('Removed ${c.name} (${c.phone})'),
                                                backgroundColor: AppTheme.crimson,
                                              ),
                                            );
                                          }
                                        }
                                      },
                                    ),
                                    if (isSelected)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 4),
                                        child: Icon(Icons.check_circle, color: AppTheme.crimson, size: 20),
                                      ),
                                  ],
                                ),
                                onTap: () async {
                                  await widget.storageService.setPrimaryContactId(c.id);
                                  if (mounted) setState(() {});
                                  if (bottomSheetCtx.mounted) Navigator.pop(bottomSheetCtx);
                                },
                              );
                            },
                          ),
                        ),
                      ] else ...[
                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.contact_phone_outlined, size: 52, color: AppTheme.textMuted),
                                const SizedBox(height: 12),
                                const Text(
                                  'No Contacts Added Yet',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Add your trusted contact number to receive emergency SOS alerts',
                                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    if (bottomSheetCtx.mounted) Navigator.pop(bottomSheetCtx);
                                    _showAddEditContactDialog();
                                  },
                                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                                  label: const Text('Add Emergency Contact'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.crimson,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
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
            if (contacts.isNotEmpty) {
              if (primaryId != null && primaryId.isNotEmpty) {
                primaryContact = contacts.cast<TrustedContact?>().firstWhere(
                  (c) => c?.id == primaryId,
                  orElse: () => contacts.cast<TrustedContact?>().firstWhere(
                    (c) => c?.isEmergencyRecipient == true,
                    orElse: () => contacts.first,
                  ),
                );
              } else {
                final em = contacts.where((c) => c.isEmergencyRecipient).toList();
                primaryContact = em.isNotEmpty ? em.first : contacts.first;
              }
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

                      // APRAJITA AEGIS AI AGENT & SCREEN CUSTOMIZER BANNER
                      _buildAiAndGifLauncherBanner(),
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

  Widget _buildAiAndGifLauncherBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.emerald.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.emerald.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.psychology, color: AppTheme.emerald, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Aprajita AI Agent',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        'Vectorize Hindsight Memory Active',
                        style: TextStyle(fontSize: 10.5, color: AppTheme.emerald),
                      ),
                    ],
                  ),
                ],
              ),
              if (widget.onNavigateToAi != null)
                TextButton(
                  onPressed: widget.onNavigateToAi,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        'Chat Agent',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.emerald),
                      ),
                      SizedBox(width: 2),
                      Icon(Icons.chevron_right, size: 14, color: AppTheme.emerald),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Remembers solo travel preferences, previous incident GPS fixes, and device troubleshooting history.',
            style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.3),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onNavigateToAi,
                  icon: const Icon(Icons.smart_toy_outlined, size: 14, color: AppTheme.textPrimary),
                  label: const Text('Ask Agent', style: TextStyle(fontSize: 11, color: AppTheme.textPrimary)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.borderSubtle),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onNavigateToGif,
                  icon: const Icon(Icons.animation, size: 14, color: Colors.cyanAccent),
                  label: const Text('OLED GIF Customizer', style: TextStyle(fontSize: 11, color: Colors.cyanAccent)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecipientSelectorCard(
    TrustedContact? primaryContact,
    List<TrustedContact> contacts,
  ) {
    final bool hasContacts = contacts.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasContacts ? AppTheme.borderSubtle : AppTheme.amber.withValues(alpha: 0.6),
          width: hasContacts ? 1.0 : 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (hasContacts) {
              _showChangeRecipientDialog();
            } else {
              _showAddEditContactDialog();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: (hasContacts ? AppTheme.crimson : AppTheme.amber).withValues(alpha: 0.15),
                  child: Icon(
                    hasContacts ? Icons.shield_outlined : Icons.person_add_alt_1_rounded,
                    color: hasContacts ? AppTheme.crimson : AppTheme.amber,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            hasContacts ? 'ACTIVE SOS RECIPIENT' : 'NO CONTACT CONFIGURED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: hasContacts ? AppTheme.textMuted : AppTheme.amber,
                            ),
                          ),
                          if (!hasContacts) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: AppTheme.amber.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'ACTION REQUIRED',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.amber,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        primaryContact != null
                            ? '${primaryContact.name} • ${primaryContact.phone}'
                            : (hasContacts
                                ? 'All ${contacts.where((c) => c.isEmergencyRecipient).length} Emergency Contacts'
                                : 'Tap here to add emergency contact number'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: hasContacts ? AppTheme.textPrimary : AppTheme.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (primaryContact != null)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.indigo),
                    tooltip: 'Edit This Contact',
                    onPressed: () => _showAddEditContactDialog(existing: primaryContact),
                  ),
                FilledButton.icon(
                  onPressed: () {
                    if (hasContacts) {
                      _showChangeRecipientDialog();
                    } else {
                      _showAddEditContactDialog();
                    }
                  },
                  icon: Icon(hasContacts ? Icons.swap_horiz_rounded : Icons.add, size: 15),
                  label: Text(hasContacts ? 'Change' : 'Add Contact'),
                  style: FilledButton.styleFrom(
                    backgroundColor: hasContacts ? AppTheme.surfaceDark : AppTheme.crimson,
                    foregroundColor: Colors.white,
                    side: BorderSide(color: hasContacts ? AppTheme.borderSubtle : Colors.transparent),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    minimumSize: const Size(0, 32),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
        ),
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
