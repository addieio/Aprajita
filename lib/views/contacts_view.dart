import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/contact_model.dart';
import '../services/storage_service.dart';
import '../services/hardware_service.dart';
import '../services/twilio_service.dart';
import '../theme/app_theme.dart';

class ContactsView extends StatefulWidget {
  final StorageService storageService;
  final HardwareService hardwareService;
  final TwilioService twilioService;

  const ContactsView({
    super.key,
    required this.storageService,
    required this.hardwareService,
    required this.twilioService,
  });

  @override
  State<ContactsView> createState() => _ContactsViewState();
}

class _ContactsViewState extends State<ContactsView> {
  late List<TrustedContact> _contacts;
  String? _primaryContactId;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  void _loadContacts() {
    setState(() {
      _contacts = widget.storageService.loadContacts();
      _primaryContactId = widget.storageService.getPrimaryContactId();
    });
  }

  Future<void> _saveAndRefresh(List<TrustedContact> list) async {
    await widget.storageService.saveContacts(list);
    _loadContacts();
  }

  void _showAddEditDialog({TrustedContact? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    bool isRecipient = existing?.isEmergencyRecipient ?? true;
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.cardDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: AppTheme.borderSubtle),
              ),
              title: Text(
                existing == null ? 'Add Trusted Contact' : 'Edit Contact',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Emergency alerts, live GPS links, and emergency SMS will be sent to this number.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Contact Name',
                      hintText: 'e.g. Mother, Sister, Police Helpline',
                      filled: true,
                      fillColor: AppTheme.surfaceDark,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Mobile Number',
                      hintText: 'e.g. +91 98765 43210',
                      errorText: errorText,
                      filled: true,
                      fillColor: AppTheme.surfaceDark,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final rawPhone = phoneCtrl.text.trim();

                    if (name.isEmpty) {
                      setDialogState(() => errorText = 'Please enter a name');
                      return;
                    }

                    final validation = TrustedContact.validatePhone(rawPhone);
                    if (!validation.isValid) {
                      setDialogState(() => errorText = validation.message);
                      return;
                    }

                    final formattedPhone = validation.formattedNumber!;

                    if (existing == null) {
                      // Add new
                      final newContact = TrustedContact(
                        id: const Uuid().v4(),
                        name: name,
                        phone: formattedPhone,
                        isEmergencyRecipient: isRecipient,
                        isPrimary: _contacts.isEmpty,
                      );
                      final updated = [..._contacts, newContact];
                      await _saveAndRefresh(updated);
                    } else {
                      // Update existing
                      final updated = _contacts.map((c) {
                        if (c.id == existing.id) {
                          return c.copyWith(
                            name: name,
                            phone: formattedPhone,
                            isEmergencyRecipient: isRecipient,
                          );
                        }
                        return c;
                      }).toList();
                      await _saveAndRefresh(updated);
                    }

                    if (ctx.mounted) {
                      Navigator.pop(ctx);
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

  Future<void> _deleteContact(TrustedContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        title: const Text('Remove Contact?'),
        content: Text('Are you sure you want to remove ${contact.name} (${contact.phone})?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.crimson),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final updated = _contacts.where((c) => c.id != contact.id).toList();
      if (_primaryContactId == contact.id) {
        await widget.storageService.setPrimaryContactId('');
      }
      await _saveAndRefresh(updated);
    }
  }

  Future<void> _setAsPrimary(TrustedContact contact) async {
    await widget.storageService.setPrimaryContactId(contact.id);
    _loadContacts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Set ${contact.name} as Primary SOS Recipient'),
        backgroundColor: AppTheme.cardElevated,
      ),
    );
  }

  Future<void> _testSms(TrustedContact contact) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sending test SMS alert to ${contact.phone}...'),
        backgroundColor: AppTheme.cardElevated,
      ),
    );

    final res = await widget.twilioService.sendTestSms(
      recipientPhone: contact.phone,
    );

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.cardDark,
          title: Text(res.success ? 'SMS Sent Successfully' : 'SMS Test Failed'),
          content: Text(res.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _syncToEsp32() async {
    setState(() => _isSyncing = true);
    final ok = await widget.hardwareService.syncContactsToKeychain(_contacts);
    if (mounted) {
      setState(() => _isSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? '✅ Contacts synced to ESP32 Flash memory!'
                : '⚠️ Could not reach ESP32. Saved locally.',
          ),
          backgroundColor: ok ? AppTheme.emerald : AppTheme.amber,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final emergencyCount =
        _contacts.where((c) => c.isEmergencyRecipient).length;

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
                    'Emergency Contacts',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Trusted numbers receiving automated SOS alerts',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
              FilledButton.icon(
                onPressed: () => _showAddEditDialog(),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                label: const Text('Add'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.crimson,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
          // Header info banner & ESP32 Sync action
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$emergencyCount Armed Recipients',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Stored offline on phone & synced to ESP32 Flash',
                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isSyncing ? null : _syncToEsp32,
                  icon: _isSyncing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync, size: 16),
                  label: const Text('Sync to ESP32'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.indigo,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          // Contact Cards List
          Expanded(
            child: _contacts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.contact_phone_outlined, size: 64, color: AppTheme.textMuted),
                        const SizedBox(height: 16),
                        const Text('No Emergency Contacts Added', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text('Add trusted friends or family to receive distress SMS', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                        const SizedBox(height: 18),
                        ElevatedButton.icon(
                          onPressed: () => _showAddEditDialog(),
                          icon: const Icon(Icons.add),
                          label: const Text('Add First Contact'),
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.crimson),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _contacts.length,
                    itemBuilder: (context, index) {
                      final c = _contacts[index];
                      final isPrimary = c.id == _primaryContactId;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.cardDark,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isPrimary ? AppTheme.crimson : AppTheme.borderSubtle,
                            width: isPrimary ? 1.5 : 1.0,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: isPrimary
                                        ? AppTheme.crimson.withValues(alpha: 0.2)
                                        : AppTheme.surfaceDark,
                                    child: Text(
                                      c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                                      style: TextStyle(
                                        color: isPrimary ? AppTheme.crimson : AppTheme.textPrimary,
                                        fontWeight: FontWeight.bold,
                                      ),
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
                                              c.name,
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.textPrimary,
                                              ),
                                            ),
                                            if (isPrimary) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.crimson,
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Text(
                                                  'PRIMARY SOS',
                                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          c.phone,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => _showAddEditDialog(existing: c),
                                    icon: const Icon(Icons.edit_outlined, size: 20),
                                    tooltip: 'Edit',
                                  ),
                                  IconButton(
                                    onPressed: () => _deleteContact(c),
                                    icon: const Icon(Icons.delete_outline, size: 20, color: AppTheme.textMuted),
                                    tooltip: 'Delete',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              const Divider(color: AppTheme.borderSubtle, height: 1),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  InkWell(
                                    onTap: () => _setAsPrimary(c),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isPrimary ? Icons.star : Icons.star_border,
                                          size: 16,
                                          color: isPrimary ? AppTheme.crimson : AppTheme.textMuted,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          isPrimary ? 'Default SOS Recipient' : 'Set as Default Recipient',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isPrimary ? AppTheme.crimson : AppTheme.textMuted,
                                            fontWeight: isPrimary ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _testSms(c),
                                    icon: const Icon(Icons.sms_outlined, size: 14),
                                    label: const Text('Test SMS', style: TextStyle(fontSize: 12)),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppTheme.indigo,
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
  }
}
