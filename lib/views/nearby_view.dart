import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/nearby_alert_model.dart';
import '../services/nearby_community_service.dart';
import '../services/location_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class NearbyView extends StatefulWidget {
  final NearbyCommunityService nearbyService;
  final LocationService locationService;
  final SupabaseService supabaseService;

  const NearbyView({
    super.key,
    required this.nearbyService,
    required this.locationService,
    required this.supabaseService,
  });

  @override
  State<NearbyView> createState() => _NearbyViewState();
}

class _NearbyViewState extends State<NearbyView> {
  void _broadcastMyAlert() {
    final loc = widget.locationService.currentLocation;
    if (loc == null) return;

    final msgCtrl = TextEditingController(
      text: 'Urgent: I feel unsafe at my current location. Please assist!',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        title: const Text('Broadcast Distress to Nearby Users'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your live GPS coordinates will be broadcasted to all Aprajita app users within 3 km.',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: msgCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Message Note',
                filled: true,
                fillColor: AppTheme.surfaceDark,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
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
              await widget.nearbyService.broadcastMyAlert(
                userName: 'Aprajita Member (Distress)',
                userPhone: '',
                location: loc,
                message: msgCtrl.text.trim(),
                radiusKm: widget.nearbyService.filterRadiusKm,
              );
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🚨 Distress signal broadcasted to nearby community!'),
                  backgroundColor: AppTheme.crimson,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.crimson),
            child: const Text('Broadcast Alert'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userLoc = widget.locationService.currentLocation;

    return StreamBuilder<List<NearbyCommunityAlert>>(
      stream: widget.nearbyService.alertsStream,
      initialData: widget.nearbyService.alerts,
      builder: (context, snapshot) {
        final alertsWithDistance =
            widget.nearbyService.getAlertsWithDistance(userLoc);

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
                        'Nearby Community',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Decentralized safety radar & alert network',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
                    tooltip: 'Refresh Feed',
                  ),
                ],
              ),
            ),
              // Community Network Header Banner
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.cardDark,
                      AppTheme.indigo.withValues(alpha: 0.15),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.indigo.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.indigo.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.wifi_tethering, color: AppTheme.indigo, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Peer Emergency Broadcast',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.supabaseService.isConfigured
                                ? 'Connected to Supabase Realtime backend'
                                : 'Local mesh mode • Configure Supabase in Settings',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _broadcastMyAlert,
                      icon: const Icon(Icons.campaign, size: 16),
                      label: const Text('Broadcast'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.crimson,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

              // Radius Selector Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [1.0, 3.0, 5.0, 10.0].map((radius) {
                    final isSelected =
                        widget.nearbyService.filterRadiusKm == radius;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('Within ${radius.toInt()} km'),
                        selected: isSelected,
                        selectedColor: AppTheme.indigo,
                        backgroundColor: AppTheme.surfaceDark,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (val) {
                          if (val) {
                            setState(() {
                              widget.nearbyService.setFilterRadius(radius);
                            });
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),

              // Nearby Alerts Feed
              Expanded(
                child: alertsWithDistance.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.shield_outlined, size: 54, color: AppTheme.textMuted),
                            SizedBox(height: 12),
                            Text(
                              'No Active SOS Alerts Nearby',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Your surrounding area within radius is calm and safe.',
                              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: alertsWithDistance.length,
                        itemBuilder: (context, index) {
                          final entry = alertsWithDistance[index];
                          final alert = entry.key;
                          final distanceMeters = entry.value;

                          final distanceText = distanceMeters < 1000
                              ? '${distanceMeters.toInt()} meters away'
                              : '${(distanceMeters / 1000).toStringAsFixed(1)} km away';

                          final isCritical = alert.status == 'ACTIVE';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: AppTheme.cardDark,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isCritical ? AppTheme.crimson : AppTheme.borderSubtle,
                                width: isCritical ? 1.5 : 1.0,
                              ),
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
                                          CircleAvatar(
                                            backgroundColor: isCritical
                                                ? AppTheme.crimson.withValues(alpha: 0.2)
                                                : AppTheme.surfaceDark,
                                            child: Icon(
                                              Icons.warning_amber_rounded,
                                              color: isCritical ? AppTheme.crimson : AppTheme.amber,
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                alert.userName,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppTheme.textPrimary,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '$distanceText • ${_formatAgo(alert.timestamp)}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppTheme.textMuted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: (isCritical ? AppTheme.crimson : AppTheme.indigo)
                                              .withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          alert.status,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isCritical ? AppTheme.crimson : AppTheme.indigo,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppTheme.surfaceDark,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      alert.message,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textPrimary,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () {
                                            launchUrl(Uri.parse(alert.googleMapsUrl));
                                          },
                                          icon: const Icon(Icons.directions, size: 16),
                                          label: const Text('Directions'),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: AppTheme.textPrimary,
                                            side: const BorderSide(color: AppTheme.borderSubtle),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () {
                                            widget.nearbyService.respondToAlert(alert.id);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('Marked: You are responding to this distress alert.'),
                                                backgroundColor: AppTheme.emerald,
                                              ),
                                            );
                                          },
                                          icon: const Icon(Icons.volunteer_activism, size: 16),
                                          label: Text(
                                            alert.respondersCount > 0
                                                ? '${alert.respondersCount} Responding'
                                                : 'I am on my way',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppTheme.indigo,
                                            foregroundColor: Colors.white,
                                          ),
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
      },
    );
  }

  String _formatAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}
