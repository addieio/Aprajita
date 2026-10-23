import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/emergency_service.dart';
import '../theme/app_theme.dart';

class SosCountdownDialog extends StatelessWidget {
  final EmergencyService emergencyService;

  const SosCountdownDialog({
    super.key,
    required this.emergencyService,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: emergencyService.countdownStream,
      initialData: 5,
      builder: (context, snapshot) {
        final remaining = snapshot.data ?? 0;
        if (remaining <= 0) {
          return const SizedBox.shrink();
        }

        return Container(
          color: Colors.black.withValues(alpha: 0.88),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.cardDark,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.crimson, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.crimson.withValues(alpha: 0.4),
                    blurRadius: 36,
                    spreadRadius: 6,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Animated Pulsing Warning Icon
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.crimson.withValues(alpha: 0.2),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: AppTheme.crimson,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'SOS TRIGGERED',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: AppTheme.crimson,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Distress SMS with live Google Maps link & timestamp will be sent in:',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Big Countdown Counter
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.crimson, width: 4),
                      color: AppTheme.surfaceDark,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$remaining',
                      style: const TextStyle(
                        fontSize: 46,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Immediate Action Buttons (Call Contact & WhatsApp SOS)
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            HapticFeedback.heavyImpact();
                            emergencyService.dispatchImmediately();
                          },
                          icon: const Icon(Icons.flash_on, size: 16),
                          label: const Text('DISPATCH & CALL'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.crimson,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            HapticFeedback.heavyImpact();
                            emergencyService.sendWhatsAppDistressMessage();
                            emergencyService.dispatchImmediately();
                          },
                          icon: const Icon(Icons.chat_bubble_outline, size: 16),
                          label: const Text('WHATSAPP SOS'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Cancel / False Alarm Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        emergencyService.cancelCountdown();
                      },
                      icon: const Icon(Icons.close, size: 22),
                      label: const Text(
                        'CANCEL SOS (FALSE ALARM)',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Tap Cancel anytime to abort accidental emergency dispatch',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
