import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/sos_event_model.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class HistoryView extends StatefulWidget {
  final StorageService storageService;

  const HistoryView({
    super.key,
    required this.storageService,
  });

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  late List<SosAlertEvent> _history;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  void _loadHistory() {
    setState(() {
      _history = widget.storageService.loadHistory();
    });
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        title: const Text('Clear SOS History?'),
        content: const Text('This will delete all past emergency logs from local storage.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.crimson),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.storageService.saveHistory([]);
      _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    'Emergency Logs & History',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Chronological SOS dispatch log & delivery receipts',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
              if (_history.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined, color: AppTheme.textMuted),
                  onPressed: _clearHistory,
                  tooltip: 'Clear History',
                ),
            ],
          ),
        ),
        Expanded(
          child: _history.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.history_toggle_off, size: 64, color: AppTheme.textMuted),
                  SizedBox(height: 16),
                  Text(
                    'No Past Emergency Events',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Emergency SOS logs and SMS delivery statuses will appear here.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _history.length,
              itemBuilder: (context, index) {
                final item = _history[index];
                final isResolved = item.status == 'RESOLVED';
                final timeFormatted =
                    DateFormat('dd MMM yyyy, hh:mm:ss a').format(item.timestamp.toLocal());

                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.cardDark,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  item.source.contains('PHYSICAL')
                                      ? Icons.touch_app
                                      : Icons.smartphone,
                                  color: AppTheme.crimson,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  item.source,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: (isResolved ? AppTheme.emerald : AppTheme.crimson)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                item.status,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isResolved ? AppTheme.emerald : AppTheme.crimson,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '🕒 Triggered: $timeFormatted',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                        ),
                        if (item.location != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '📍 Coords: ${item.location!.displayCoords} (±${item.location!.accuracy.toInt()}m)',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                          ),
                        ],
                        const SizedBox(height: 10),
                        const Divider(color: AppTheme.borderSubtle, height: 1),
                        const SizedBox(height: 8),
                        const Text(
                          'SMS Delivery Status to Recipients:',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
                        ),
                        const SizedBox(height: 6),
                        ...item.recipients.map((r) {
                          final isOk = r.status == SmsDeliveryState.submitted ||
                              r.status == SmsDeliveryState.delivered;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Icon(
                                  isOk ? Icons.check_circle_outline : Icons.error_outline,
                                  size: 14,
                                  color: isOk ? AppTheme.emerald : AppTheme.amber,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${r.name} (${r.phone}): ${r.status.name.toUpperCase()}',
                                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                  ),
                                ),
                                if (r.messageSid != null)
                                  Text(
                                    'SID: ${r.messageSid!.substring(0, 8)}...',
                                    style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                                  ),
                              ],
                            ),
                          );
                        }),
                        if (item.mapUrl.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => launchUrl(Uri.parse(item.mapUrl)),
                              icon: const Icon(Icons.map_outlined, size: 14),
                              label: const Text('View Location on Google Maps', style: TextStyle(fontSize: 11)),
                              style: TextButton.styleFrom(foregroundColor: AppTheme.indigo),
                            ),
                          ),
                        ],
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
