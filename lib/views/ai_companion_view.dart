import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/groq_service.dart';
import '../services/hindsight_service.dart';
import '../services/storage_service.dart';
import '../services/twilio_service.dart';
import '../services/location_service.dart';
import '../services/hardware_service.dart';
import '../models/contact_model.dart';
import '../theme/app_theme.dart';

class AiCompanionView extends StatefulWidget {
  final GroqService groqService;
  final HindsightService hindsightService;
  final StorageService storageService;
  final TwilioService twilioService;
  final LocationService locationService;
  final HardwareService hardwareService;

  const AiCompanionView({
    super.key,
    required this.groqService,
    required this.hindsightService,
    required this.storageService,
    required this.twilioService,
    required this.locationService,
    required this.hardwareService,
  });

  @override
  State<AiCompanionView> createState() => _AiCompanionViewState();
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final String? badge;
  final DateTime timestamp;

  _ChatMessage({
    required this.text,
    required this.isUser,
    this.badge,
    required this.timestamp,
  });
}

class _AiCompanionViewState extends State<AiCompanionView> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  // Active Safety Watch / Check-In Timer State
  Timer? _checkinTimer;
  int _watchSecondsLeft = 0;
  bool _isWatchActive = false;
  bool _isUrgentDialogOpen = false;
  StreamSubscription? _hardwareCheckinSub;

  final List<_ChatMessage> _messages = [];

  final List<String> _quickPrompts = const [
    'Check on me in 5 seconds',
    'Check on me in 10 seconds',
    'What is my rule if I miss check-in?',
    'What safety settings did I choose for solo travel?',
    'Who is my primary emergency contact?',
  ];

  @override
  void initState() {
    super.initState();
    _loadInitialGreeting();

    // Listen to real-time Keychain Check-in confirmations and hazard responses
    _hardwareCheckinSub = widget.hardwareService.checkinEventStream.listen((event) {
      if (!mounted) return;
      if (event == 'CHECKIN_SAFE') {
        if (_isUrgentDialogOpen) {
          Navigator.of(context, rootNavigator: true).pop();
          _isUrgentDialogOpen = false;
        }
        _confirmSafeCheckin(fromHardware: true);
      } else if (event == 'CHECKIN_SOS' || event == 'CHECKIN_TIMEOUT_SOS') {
        if (_isUrgentDialogOpen) {
          Navigator.of(context, rootNavigator: true).pop();
          _isUrgentDialogOpen = false;
        }
        _executeMissedCheckinEscalation(
          reason: event == 'CHECKIN_TIMEOUT_SOS'
              ? 'Safety Check-In timed out on physical Keychain (unresponsive within 10s grace period)'
              : 'User pressed NEED HELP (SOS) on physical Aprajita Keychain Check-In',
        );
      } else if (event == 'REROUTE_ACCEPTED') {
        setState(() {
          _messages.add(
            _ChatMessage(
              text: '🛡️ [SAFE REROUTE CONFIRMED ON KEYCHAIN]\n'
                  'User confirmed safe path reroute via Main Metro Blvd (Well-Lit & Monitored). Live guardian tracking active.',
              isUser: false,
              badge: 'SAFE REROUTE',
              timestamp: DateTime.now(),
            ),
          );
        });
        _scrollToBottom();
      }
    });
  }

  @override
  void dispose() {
    _hardwareCheckinSub?.cancel();
    _checkinTimer?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _loadInitialGreeting() {
    _messages.add(
      _ChatMessage(
        text: 'Hello Aditya. I am your Aprajita Safety Companion powered by Vectorize Hindsight episodic memory.\n\n'
            'Tell me when to check on you (e.g. "Check on me in 10 seconds" or "Remind me in 15 mins"), and I will watch over you. '
            'If you do not acknowledge safety, I will automatically escalate to your emergency contacts.',
        isUser: false,
        badge: 'HINDSIGHT ACTIVE',
        timestamp: DateTime.now(),
      ),
    );
  }

  /// Parses duration from user prompt (e.g. "check on me in 10 seconds", "check on me in 5", "remind me in 5 mins")
  int? _parseCheckinDurationSeconds(String text) {
    String lower = text.toLowerCase().trim();

    // Convert written word numbers to digits
    const wordNumbers = {
      'one': '1', 'two': '2', 'three': '3', 'four': '4', 'five': '5',
      'six': '6', 'seven': '7', 'eight': '8', 'nine': '9', 'ten': '10',
      'fifteen': '15', 'twenty': '20', 'thirty': '30', 'forty': '40',
      'fifty': '50', 'sixty': '60',
    };
    wordNumbers.forEach((word, numStr) {
      lower = lower.replaceAll(RegExp(r'\b' + word + r'\b'), numStr);
    });

    // 1. Explicit Seconds (e.g. "10 seconds", "5s", "20 secs", "10 sec")
    final secMatch = RegExp(r'(\d+)\s*(?:s|sec|secs|second|seconds)\b').firstMatch(lower);
    if (secMatch != null) {
      return int.tryParse(secMatch.group(1)!);
    }

    // 2. Explicit Minutes (e.g. "20 mins", "1 minute", "2 m", "5 min")
    final minMatch = RegExp(r'(\d+)\s*(?:m|min|mins|minute|minutes)\b').firstMatch(lower);
    if (minMatch != null) {
      final m = int.tryParse(minMatch.group(1)!);
      if (m != null) return m * 60;
    }

    // 3. Explicit Hours (e.g. "1 hour", "2 hrs")
    final hrMatch = RegExp(r'(\d+)\s*(?:h|hr|hrs|hour|hours)\b').firstMatch(lower);
    if (hrMatch != null) {
      final h = int.tryParse(hrMatch.group(1)!);
      if (h != null) return h * 3600;
    }

    // 4. Intent with isolated number:
    // e.g. "check on me in 5", "check in 10", "ask me after 5", "check in after 10", "remind me in 5"
    final hasCheckinIntent = lower.contains('check') ||
        lower.contains('remind') ||
        lower.contains('ask') ||
        lower.contains('watch') ||
        lower.contains('pucho') ||
        lower.contains('karo');

    if (hasCheckinIntent) {
      final numMatch = RegExp(r'\b(\d+)\b').firstMatch(lower);
      if (numMatch != null) {
        final val = int.tryParse(numMatch.group(1)!);
        if (val != null) {
          // If val <= 60, treat as seconds for rapid interactive testing!
          return val;
        }
      }
      // If check-in intent without any number, default to 10 seconds
      return 10;
    }

    return null;
  }

  TrustedContact _getPrimaryEmergencyContact() {
    final contacts = widget.storageService.loadContacts();
    return contacts.firstWhere(
      (c) => c.isPrimary,
      orElse: () => contacts.isNotEmpty
          ? contacts.first
          : TrustedContact(
              id: 'primary',
              name: 'Emergency Contact',
              phone: '',
              isEmergencyRecipient: true,
              isPrimary: true,
            ),
    );
  }

  /// START SCHEDULED SAFETY WATCH TIMER
  void _startScheduledCheckin(int seconds, String reason) {
    _checkinTimer?.cancel();
    HapticFeedback.mediumImpact();

    final primary = _getPrimaryEmergencyContact();
    final contactDisplay = primary.phone.isNotEmpty ? '${primary.name} (${primary.phone})' : 'Emergency Contacts';

    final durationLabel = seconds >= 60
        ? '${(seconds / 60).round()} minute${(seconds >= 120) ? "s" : ""}'
        : '$seconds second${(seconds != 1) ? "s" : ""}';

    setState(() {
      _isWatchActive = true;
      _watchSecondsLeft = seconds;
      _messages.add(
        _ChatMessage(
          text: '⏱️ [SAFETY WATCH ACTIVATED]\n'
              'I will check on you in $durationLabel.\n'
              'When the time arrives, an urgent safety check-in screen will flash on your phone asking "ARE YOU OKAY? Any troubles?".\n'
              'If you do not confirm safety within 15 seconds, I will automatically escalate to $contactDisplay with your live GPS location.',
          isUser: false,
          badge: 'WATCH SCHEDULED',
          timestamp: DateTime.now(),
        ),
      );
    });
    _scrollToBottom();

    // Retain to Vectorize Hindsight
    widget.hindsightService.retain(
      'Active Safety Watch scheduled for $durationLabel. Escalation protocol: $contactDisplay with live GPS fix if unacknowledged.',
      tag: 'safety_watch',
    );

    _checkinTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_watchSecondsLeft > 1) {
        setState(() => _watchSecondsLeft--);
      } else {
        timer.cancel();
        setState(() {
          _isWatchActive = false;
          _watchSecondsLeft = 0;
        });
        // TIME HAS ARRIVED: FLASH THE URGENT CHECK-IN DIALOG!
        _flashUrgentCheckinDialog();
      }
    });
  }

  void _cancelWatchTimer() {
    _checkinTimer?.cancel();
    setState(() {
      _isWatchActive = false;
      _watchSecondsLeft = 0;
    });
  }

  /// FLASHES SCREEN WITH URGENT SAFETY CHECK-IN DIALOG (SYNCS TO KEYCHAIN DISPLAY)
  void _flashUrgentCheckinDialog() {
    if (!mounted) return;
    _isUrgentDialogOpen = true;

    // Simultaneously trigger Check-in screen on physical ESP32 OLED Keychain!
    widget.hardwareService.sendCheckinAlertToEsp32(timeoutSeconds: 10);

    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (dialogCtx) {
        return _UrgentCheckinDialog(
          onSafe: () {
            _isUrgentDialogOpen = false;
            _confirmSafeCheckin();
          },
          onSos: () {
            _isUrgentDialogOpen = false;
            _executeMissedCheckinEscalation(
              reason: 'User explicitly requested help during safety check-in',
            );
          },
          onTimeout: () {
            _isUrgentDialogOpen = false;
            _executeMissedCheckinEscalation(
              reason: 'No response to scheduled check-in within grace period',
            );
          },
        );
      },
    ).then((_) {
      _isUrgentDialogOpen = false;
    });
  }

  /// USER CONFIRMS SAFETY
  void _confirmSafeCheckin({bool fromHardware = false}) {
    HapticFeedback.lightImpact();

    // Dismiss alert on physical ESP32 if confirmed on phone
    if (!fromHardware) {
      widget.hardwareService.sendCheckinSafeToEsp32();
    }

    setState(() {
      _messages.add(
        _ChatMessage(
          text: fromHardware
              ? '✅ [CHECK-IN CONFIRMED VIA KEYCHAIN DISPLAY]\n'
                'Aditya confirmed safe status on the physical Aprajita keychain! Live Hindsight memory synced.'
              : '✅ [CHECK-IN CONFIRMED ON PHONE]\n'
                'Aditya confirmed safe and sound on time! Synced to keychain. No escalation dispatched.',
          isUser: false,
          badge: fromHardware ? 'HARDWARE SAFE' : 'SAFE CONFIRMED',
          timestamp: DateTime.now(),
        ),
      );
    });
    _scrollToBottom();

    // Retain safe confirmation
    widget.hindsightService.retain(
      'User Aditya safely confirmed scheduled safety check-in on time ${fromHardware ? "via physical Keychain display" : "via Phone app"}.',
      tag: 'checkin_confirmed',
    );
  }

  /// EXECUTES HINDSIGHT ESCALATION PROTOCOL
  Future<void> _executeMissedCheckinEscalation({required String reason}) async {
    HapticFeedback.heavyImpact();

    // 1. Fetch current GPS fix
    final loc = await widget.locationService.getCurrentLocation();
    final mapUrl = 'https://maps.google.com/?q=${loc.lat.toStringAsFixed(4)},${loc.lng.toStringAsFixed(4)}';

    // 2. Resolve primary emergency contact
    final primary = _getPrimaryEmergencyContact();
    final targetPhone = primary.phone.isNotEmpty ? primary.phone : '+919876543210';
    final targetName = primary.name.isNotEmpty ? primary.name : 'Emergency Contact';

    // 3. Dispatch SMS alert with Hindsight Medical Profile
    final smsResult = await widget.twilioService.sendEmergencySms(
      recipientPhone: targetPhone,
      senderName: 'Aprajita Safety Escalation',
      locationUrl: mapUrl,
      latitude: loc.lat,
      longitude: loc.lng,
      accuracy: loc.accuracy,
      batteryLevel: 94,
      triggerSource: 'MISSED_CHECKIN_ESCALATION',
      timestamp: DateTime.now(),
      customNote: '$reason. HINDSIGHT MEDICAL MEMORY: Severe Asthma patient - rescue inhaler in left jacket pocket. Blood Group: O+.',
    );

    // 4. Retain this escalation incident into Vectorize Hindsight
    final incidentSummary = 'SAFETY ESCALATION DISPATCHED: $reason at '
        '${DateTime.now().toLocal().toString().substring(11, 19)}. '
        'Escalated to primary contact $targetName ($targetPhone). '
        'Victim Profile: Asthma patient, inhaler in left pocket. GPS Fix: $mapUrl. Status: ${smsResult.success ? "DELIVERED" : "SENT"}.';
    await widget.hindsightService.retain(incidentSummary, tag: 'escalation_incident');

    if (mounted) {
      setState(() {
        _messages.add(
          _ChatMessage(
            text: '🚨 [ESCALATION PROTOCOL EXECUTED]\n\n'
                '• Reason: $reason\n'
                '• Escalation Rule: "Immediately alert $targetName with live GPS fix."\n'
                '• Medical Memory Recall: Asthma patient, rescue inhaler in left coat pocket.\n'
                '• Dispatch Status: ${smsResult.success ? "Alert Delivered to $targetPhone ✅" : "Dispatched to $targetPhone"}\n'
                '• Live GPS: ${loc.lat.toStringAsFixed(4)}, ${loc.lng.toStringAsFixed(4)}\n'
                '• Incident Record: Stored in Vectorize Cloud memory bank.',
            isUser: false,
            badge: 'ESCALATION DISPATCHED',
            timestamp: DateTime.now(),
          ),
        );
      });
      _scrollToBottom();
    }
  }

  /// SEND USER MESSAGE (WITH DYNAMIC CHECK-IN SCHEDULING & RETENTION)
  Future<void> _sendMessage(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return;

    setState(() {
      _messages.add(
        _ChatMessage(
          text: clean,
          isUser: true,
          timestamp: DateTime.now(),
        ),
      );
      _isLoading = true;
    });

    _textController.clear();
    _scrollToBottom();

    // Check if user is asking to be checked on / reminded
    final durationSeconds = _parseCheckinDurationSeconds(clean);
    if (durationSeconds != null && durationSeconds > 0) {
      _startScheduledCheckin(durationSeconds, clean);
    }

    // Check if user is updating preferences
    final lower = clean.toLowerCase();
    final isPreference = lower.contains('remind me in') ||
        lower.contains('interval') ||
        lower.contains('check in after') ||
        lower.contains('check-in after') ||
        lower.contains('if i don\'t respond') ||
        lower.contains('call ') ||
        lower.contains('update check-in');

    if (isPreference && durationSeconds == null) {
      await widget.hindsightService.retain('User safety preference update: $clean', tag: 'user_preference');
    }

    String reply = '';
    String badge = 'HINDSIGHT MEMORY';

    try {
      reply = await widget.groqService.askSafetyCompanion(clean);
      badge = isPreference ? 'PREFERENCE RETAINED' : 'HINDSIGHT RECALLED';
    } catch (e) {
      reply = 'Error communicating with Agent: $e';
    } finally {
      if (mounted) {
        setState(() {
          _messages.add(
            _ChatMessage(
              text: reply,
              isUser: false,
              badge: badge,
              timestamp: DateTime.now(),
            ),
          );
          _isLoading = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// OPEN CLEAN HINDSIGHT MEMORY BANK MODAL
  void _openMemoryBankSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.72,
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: AppTheme.emerald, width: 1.5)),
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
                        child: const Icon(Icons.memory_rounded, color: AppTheme.emerald, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vectorize Hindsight Memory Bank',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          Text(
                            'Bank ID: aprajita_demo • Active Semantic Storage',
                            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(color: AppTheme.borderSubtle, height: 24),

              // Quick Test Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.flash_on, size: 14),
                      label: const Text('Test Live Recall', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _sendMessage('What is my rule if I miss check-in?');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.emerald,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.shield_outlined, size: 14, color: Colors.lightBlueAccent),
                      label: const Text('Solo Commute Settings', style: TextStyle(fontSize: 11.5, color: Colors.lightBlueAccent)),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _sendMessage('What safety settings did I choose for solo travel?');
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.lightBlueAccent),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              const Text(
                'LIVE HINDSIGHT AUDIT LOG:',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5),
              ),
              const SizedBox(height: 8),

              Expanded(
                child: StreamBuilder<List<HindsightLogEntry>>(
                  stream: widget.hindsightService.logsStream,
                  initialData: widget.hindsightService.recentLogs,
                  builder: (context, snapshot) {
                    final logs = snapshot.data ?? [];
                    if (logs.isEmpty) {
                      return const Center(
                        child: Text(
                          'Memory operations will appear here in real time.',
                          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      );
                    }
                    return ListView.builder(
                      itemCount: logs.length,
                      itemBuilder: (context, i) {
                        final item = logs[i];
                        final isRetain = item.operation.contains('RETAIN');
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isRetain ? AppTheme.emerald.withValues(alpha: 0.4) : Colors.blue.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    item.operation,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: isRetain ? AppTheme.emerald : Colors.lightBlueAccent,
                                    ),
                                  ),
                                  Text(
                                    item.timestamp.toIso8601String().substring(11, 19),
                                    style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.queryOrContent,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.summaryOrResult,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: AppTheme.emerald, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Aprajita AI Safety Agent',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Text(
              'Vectorize Hindsight Episodic Memory + Groq',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.memory_rounded, color: AppTheme.emerald),
            tooltip: 'View Hindsight Memory Bank',
            onPressed: _openMemoryBankSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          // CLEAN, UNCLUTTERED SAFETY WATCH PANEL
          Container(
            margin: const EdgeInsets.fromLTRB(14, 8, 14, 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isWatchActive ? AppTheme.crimson : AppTheme.emerald.withValues(alpha: 0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: (_isWatchActive ? AppTheme.crimson : AppTheme.emerald).withValues(alpha: 0.15),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isWatchActive ? Icons.timer_outlined : Icons.shield_outlined,
                          size: 16,
                          color: _isWatchActive ? AppTheme.crimson : AppTheme.emerald,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isWatchActive ? 'ACTIVE SAFETY WATCH IN PROGRESS' : 'PERSONAL SAFETY WATCH',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _isWatchActive ? AppTheme.crimson : AppTheme.emerald,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    InkWell(
                      onTap: _openMemoryBankSheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.cardElevated,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.borderSubtle),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.visibility_outlined, size: 12, color: Colors.white70),
                            SizedBox(width: 4),
                            Text('Memory Bank', style: TextStyle(fontSize: 10.5, color: Colors.white70)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (!_isWatchActive) ...[
                  const Text(
                    'Rule: If check-in is unacknowledged, automatically escalate to primary emergency contacts with live GPS fix.',
                    style: TextStyle(fontSize: 11.5, color: Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.flash_on, size: 14),
                        label: const Text('Check In (5s Demo)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                        onPressed: () => _startScheduledCheckin(5, '5-second quick live demo check-in'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade800,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.timer, size: 14),
                        label: const Text('Check In (10s)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                        onPressed: () => _startScheduledCheckin(10, '10-second safety check-in test'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.warning_amber_rounded, size: 14),
                        label: const Text('Demo: Sketchy Area', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          HapticFeedback.mediumImpact();
                          await widget.hardwareService.sendDemoHazardToEsp32();
                          setState(() {
                            _messages.add(
                              _ChatMessage(
                                text: '⚠️ [DEMO: ENTERING SKETCHY AREA]\n\n'
                                    'Caution alert pushed to physical Aprajita Keychain display:\n'
                                    '• Past Report: Creepy people reported at this location after dark.\n'
                                    '• Recommended Safe Reroute: Turn Right onto Main Metro Blvd (Well-Lit).\n'
                                    '• Interactive Action: Click once on Keychain to accept detour, or Hold/3x for Panic SOS.',
                                isUser: false,
                                badge: 'HAZARD DEMO',
                                timestamp: DateTime.now(),
                              ),
                            );
                          });
                          _scrollToBottom();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.psychology, size: 14, color: AppTheme.emerald),
                        label: const Text('Recall Rule', style: TextStyle(fontSize: 11.5, color: AppTheme.emerald, fontWeight: FontWeight.bold)),
                        onPressed: () => _sendMessage('What is my rule if I miss check-in?'),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.emerald),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Next Check-In: ${_watchSecondsLeft}s',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.amber),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.cancel_outlined, size: 14, color: Colors.white70),
                        label: const Text('Cancel Watch', style: TextStyle(fontSize: 11, color: Colors.white70)),
                        onPressed: _cancelWatchTimer,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Screen will flash "Are You Okay?" alert when countdown reaches 0s.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ],
              ],
            ),
          ),

          // CHAT MESSAGES
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return _buildMessageBubble(msg);
              },
            ),
          ),

          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.emerald),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Querying Vectorize Hindsight & Groq...',
                    style: TextStyle(fontSize: 11, color: AppTheme.emerald.withValues(alpha: 0.9)),
                  ),
                ],
              ),
            ),

          // QUICK PROMPTS
          Container(
            height: 36,
            margin: const EdgeInsets.only(bottom: 6),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _quickPrompts.length,
              itemBuilder: (context, i) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    backgroundColor: AppTheme.cardDark,
                    side: const BorderSide(color: AppTheme.borderSubtle),
                    label: Text(
                      _quickPrompts[i],
                      style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary),
                    ),
                    onPressed: () => _sendMessage(_quickPrompts[i]),
                  ),
                );
              },
            ),
          ),

          // INPUT BAR
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            decoration: const BoxDecoration(
              color: AppTheme.cardDark,
              border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    style: const TextStyle(fontSize: 13.5, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'e.g. "Check on me in 10 seconds" or "Who to call?"',
                      hintStyle: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: AppTheme.borderSubtle),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: AppTheme.borderSubtle),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: AppTheme.emerald),
                      ),
                    ),
                    onSubmitted: _sendMessage,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.send_rounded, size: 17),
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.emerald,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _sendMessage(_textController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(_ChatMessage msg) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.84),
        decoration: BoxDecoration(
          color: msg.isUser ? AppTheme.indigo.withValues(alpha: 0.25) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: msg.isUser ? const Radius.circular(2) : const Radius.circular(16),
            bottomLeft: !msg.isUser ? const Radius.circular(2) : const Radius.circular(16),
          ),
          border: Border.all(
            color: msg.isUser ? AppTheme.indigo.withValues(alpha: 0.5) : AppTheme.borderSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (msg.badge != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: msg.badge!.contains('ESCALATION')
                      ? AppTheme.crimson.withValues(alpha: 0.2)
                      : AppTheme.emerald.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  msg.badge!,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: msg.badge!.contains('ESCALATION') ? AppTheme.crimson : AppTheme.emerald,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            Text(
              msg.text,
              style: const TextStyle(fontSize: 13, height: 1.35, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

/// HIGH-IMPACT FLASHING SAFETY CHECK-IN DIALOG
class _UrgentCheckinDialog extends StatefulWidget {
  final VoidCallback onSafe;
  final VoidCallback onSos;
  final VoidCallback onTimeout;

  const _UrgentCheckinDialog({
    required this.onSafe,
    required this.onSos,
    required this.onTimeout,
  });

  @override
  State<_UrgentCheckinDialog> createState() => _UrgentCheckinDialogState();
}

class _UrgentCheckinDialogState extends State<_UrgentCheckinDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _pulseAnim;
  Timer? _countdownTimer;
  Timer? _vibrateTimer;
  int _secondsLeft = 10;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    )..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _animController, curve: Curves.easeInOut);

    // Initial impact vibration
    HapticFeedback.heavyImpact();

    // Periodic attention vibration
    _vibrateTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) {
      if (_isDisposed) {
        timer.cancel();
      } else {
        HapticFeedback.vibrate();
      }
    });

    // 15-second grace period countdown
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft > 1) {
        if (mounted) {
          setState(() => _secondsLeft--);
        }
      } else {
        timer.cancel();
        _countdownTimer = null;
        if (!_isDisposed && mounted) {
          _isDisposed = true;
          Navigator.of(context, rootNavigator: true).pop();
          widget.onTimeout();
        }
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _animController.dispose();
    _countdownTimer?.cancel();
    _vibrateTimer?.cancel();
    super.dispose();
  }

  void _handleSafe() {
    _isDisposed = true;
    _countdownTimer?.cancel();
    _vibrateTimer?.cancel();
    Navigator.of(context, rootNavigator: true).pop();
    widget.onSafe();
  }

  void _handleSos() {
    _isDisposed = true;
    _countdownTimer?.cancel();
    _vibrateTimer?.cancel();
    Navigator.of(context, rootNavigator: true).pop();
    widget.onSos();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16),
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Color.lerp(
                  AppTheme.crimson,
                  const Color(0xFFFF5252),
                  _pulseAnim.value,
                )!,
                width: 2.5 + 2.0 * _pulseAnim.value,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.crimson.withValues(alpha: 0.35 + 0.35 * _pulseAnim.value),
                  blurRadius: 28 + 14 * _pulseAnim.value,
                  spreadRadius: 3 + 3 * _pulseAnim.value,
                ),
              ],
            ),
            child: child,
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Warning Icon Halo
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.crimson.withValues(alpha: 0.18),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.crimson.withValues(alpha: 0.6),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: AppTheme.crimson,
                size: 46,
              ),
            ),
            const SizedBox(height: 18),

            // Big Urgent Question
            const Text(
              'ARE YOU OKAY?',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Any troubles or need assistance?',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFFB74D),
              ),
            ),
            const SizedBox(height: 12),

            const Text(
              'Your scheduled check-in time has arrived.\nPlease confirm your status right now.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.4, color: Colors.white70),
            ),
            const SizedBox(height: 18),

            // Countdown Status Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.crimson.withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.timer_outlined, color: Colors.amber, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Auto-escalating to Papa in: ${_secondsLeft}s',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _secondsLeft / 15.0,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.crimson),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // Primary Safe Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_rounded, size: 22),
                label: const Text(
                  'I AM OKAY / SAFE ✅',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                ),
                onPressed: _handleSafe,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.emerald,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 6,
                  shadowColor: AppTheme.emerald.withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // SOS Alert Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.emergency_share, size: 20, color: AppTheme.crimson),
                label: const Text(
                  'I NEED HELP! (SOS) 🚨',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.crimson),
                ),
                onPressed: _handleSos,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.crimson, width: 2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  backgroundColor: AppTheme.crimson.withValues(alpha: 0.1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
