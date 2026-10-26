import 'dart:async';
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
  StreamSubscription<List<TrustedContact>>? _contactsSubscription;

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _contactsSubscription = widget.storageService.contactsStream.listen((list) {
      if (mounted) {
        setState(() {
          _contacts = list;
          _primaryContactId = widget.storageService.getPrimaryContactId();
        });
      }
    });
  }

  @override
  void dispose() {
    _contactsSubscription?.cancel();
    super.dispose();
  }

  void _loadContacts() {
    setState(() {
      _contacts = widget.storageService.loadContacts();
      _primaryContactId = widget.storageService.getPrimaryContactId();
    });
  }


  void _showAddEditDialog({TrustedContact? existing}) {
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
                        hintText: 'e.g. 9876543210 or +91 98765 43210',
                        prefixIcon: const Icon(Icons.phone_outlined, size: 20),
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
              ),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              actions: [
                if (existing != null)
                  TextButton.icon(
                    onPressed: () {
                      if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                      _deleteContact(existing);
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
                      // Add new
                      final newContact = TrustedContact(
                        id: const Uuid().v4(),
                        name: name,
                        phone: formattedPhone,
                        isEmergencyRecipient: isRecipient,
                        isPrimary: _contacts.isEmpty,
                      );
                      await widget.storageService.addContact(newContact);
                    } else {
                      // Update existing in-place (no duplicate)
                      final updated = existing.copyWith(
                        name: name,
                        phone: formattedPhone,
                        isEmergencyRecipient: isRecipient,
                      );
                      await widget.storageService.updateContact(updated);
                    }

                    _loadContacts();

                    if (dialogCtx.mounted) {
                      Navigator.pop(dialogCtx);
                    }

                    if (mounted) {
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

  Future<void> _deleteContact(TrustedContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (delCtx) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Contact?'),
        content: Text('Are you sure you want to remove ${contact.name} (${contact.phone})?'),
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
      await widget.storageService.deleteContact(contact.id);
      _loadContacts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed ${contact.name} (${contact.phone})'),
            backgroundColor: AppTheme.crimson,
          ),
        );
      }
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
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                        decoration: BoxDecoration(
                          color: AppTheme.cardDark,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.borderSubtle),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.crimson.withValues(alpha: 0.12),
                              ),
                              child: const Icon(
                                Icons.person_add_alt_1_rounded,
                                size: 32,
                                color: AppTheme.crimson,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No Emergency Contacts Added',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Add your family or trusted contacts so they receive immediate SMS alerts, WhatsApp distress calls, and live GPS map tracking when SOS is triggered.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 22),
                            ElevatedButton.icon(
                              onPressed: () => _showAddEditDialog(),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Add Trusted Contact'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.crimson,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _contacts.length,
                    itemBuilder: (context, index) {
                      final c = _contacts[index];
                      final isPrimary = c.id == _primaryContactId;

                      return Dismissible(
                        key: ValueKey('contact_${c.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.only(right: 20),
                          alignment: Alignment.centerRight,
                          decoration: BoxDecoration(
                            color: AppTheme.crimson.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.crimson),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: const [
                              Text(
                                'Remove',
                                style: TextStyle(
                                  color: AppTheme.crimson,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.delete_forever_rounded, color: AppTheme.crimson, size: 24),
                            ],
                          ),
                        ),
                        confirmDismiss: (direction) async {
                          return await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: AppTheme.cardDark,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              title: const Text('Remove Contact?'),
                              content: Text('Are you sure you want to remove ${c.name} (${c.phone})?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.crimson,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Remove'),
                                ),
                              ],
                            ),
                          );
                        },
                        onDismissed: (_) {
                          // Synchronously remove from local list to satisfy Flutter's Dismissible lifecycle contract
                          setState(() {
                            _contacts.removeWhere((item) => item.id == c.id);
                          });
                          widget.storageService.deleteContact(c.id);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Removed ${c.name} (${c.phone})'),
                                backgroundColor: AppTheme.crimson,
                              ),
                            );
                          }
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.cardDark,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isPrimary ? AppTheme.crimson : AppTheme.borderSubtle,
                              width: isPrimary ? 1.5 : 1.0,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _showAddEditDialog(existing: c),
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
                                                  Flexible(
                                                    child: Text(
                                                      c.name,
                                                      style: const TextStyle(
                                                        fontSize: 15,
                                                        fontWeight: FontWeight.bold,
                                                        color: AppTheme.textPrimary,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
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
                                              const SizedBox(height: 3),
                                              Text(
                                                c.phone,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: AppTheme.textSecondary,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: () => _showAddEditDialog(existing: c),
                                          icon: const Icon(Icons.edit_outlined, size: 20, color: AppTheme.indigo),
                                          tooltip: 'Edit Contact',
                                        ),
                                        IconButton(
                                          onPressed: () => _deleteContact(c),
                                          icon: const Icon(Icons.delete_outline, size: 20, color: AppTheme.crimson),
                                          tooltip: 'Delete Contact',
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
                                          borderRadius: BorderRadius.circular(6),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  isPrimary ? Icons.star_rounded : Icons.star_border_rounded,
                                                  size: 18,
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
                            ),
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
