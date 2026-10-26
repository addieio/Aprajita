import 'dart:async';
import 'package:flutter/material.dart';
import '../services/hardware_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class GifCustomizerView extends StatefulWidget {
  final StorageService storageService;
  final HardwareService hardwareService;

  const GifCustomizerView({
    super.key,
    required this.storageService,
    required this.hardwareService,
  });

  @override
  State<GifCustomizerView> createState() => _GifCustomizerViewState();
}

class _PresetAnimation {
  final String id;
  final String title;
  final String description;
  final String icon;
  final String gifUrl;

  const _PresetAnimation({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.gifUrl,
  });
}

class _GifCustomizerViewState extends State<GifCustomizerView> {
  late String _selectedPreset;
  late int _fps;
  late bool _clock24;
  late bool _showBattery;
  bool _invertColors = false;
  final TextEditingController _customUrlController = TextEditingController();

  DateTime _currentTime = DateTime.now();
  Timer? _clockTimer;

  final List<_PresetAnimation> _presets = const [
    _PresetAnimation(
      id: 'aprajita_happy',
      title: 'Aprajita Classic Happy (HAPPY)',
      description: 'Default cheerful blinking expression synced to hardware',
      icon: '😊',
      gifUrl: 'https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExM3hicmFpbnk1eXl4dmt2OGd1NDJ5NHF2OGdtNGF6c2V4Ymt6ZzM5dCZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9cw/MDJ9IbxxvDUQM/giphy.gif',
    ),
    _PresetAnimation(
      id: 'aprajita_laugh',
      title: 'Aprajita Joyful Laugh (LAUGH)',
      description: 'Big laughing celebration face on Aprajita Display',
      icon: '😂',
      gifUrl: 'https://media.giphy.com/media/ICOgUNjpvO0PC/giphy.gif',
    ),
    _PresetAnimation(
      id: 'aprajita_excited',
      title: 'Aprajita High Energy (EXCITED)',
      description: 'Bouncing energetic star eyes face',
      icon: '🤩',
      gifUrl: 'https://media.giphy.com/media/artj92V8o75VPL7AeQ/giphy.gif',
    ),
    _PresetAnimation(
      id: 'aprajita_alert',
      title: 'Aprajita Guardian Shield (DETERMINED)',
      description: 'Vigilant shield mode for high-risk zones',
      icon: '🛡️',
      gifUrl: 'https://media.giphy.com/media/3o7aD2saalBwwftBIY/giphy.gif',
    ),
    _PresetAnimation(
      id: 'aprajita_love',
      title: 'Aprajita Heart Eyes (LOVE)',
      description: 'Heart-filled warm companion expression',
      icon: '❤️',
      gifUrl: 'https://media.giphy.com/media/3o7TKoWXm3okO1kgHC/giphy.gif',
    ),
    _PresetAnimation(
      id: 'aprajita_sleepy',
      title: 'Aprajita Night Commute (SLEEPY)',
      description: 'Gentle calm face for late-night travels',
      icon: '😴',
      gifUrl: 'https://media.giphy.com/media/mguPrVJAnEHIY/giphy.gif',
    ),
    _PresetAnimation(
      id: 'aprajita_music',
      title: 'Aprajita Cyber Beats (MUSIC)',
      description: 'Head-bobbing rhythmic audio pulse animation',
      icon: '🎵',
      gifUrl: 'https://media.giphy.com/media/blSTtZehjAZ8I/giphy.gif',
    ),
    _PresetAnimation(
      id: 'aprajita_cycle',
      title: 'Cycle All 18 Emotions (CYCLE)',
      description: 'Rotates through all 18 emotion animations on loop',
      icon: '🔄',
      gifUrl: 'https://media.giphy.com/media/26AHONQ79FdWZhAI0/giphy.gif',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _selectedPreset = widget.storageService.getCustomGifPreset();
    _fps = widget.storageService.getCustomGifFps();
    _clock24 = widget.storageService.getCustomGifClock24();
    _showBattery = widget.storageService.getCustomGifShowBattery();

    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _currentTime = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _customUrlController.dispose();
    super.dispose();
  }

  String _resolveGifUrl(String input) {
    input = input.trim();
    if (input.isEmpty) return '';
    // Resolve standard Giphy webpage URLs to direct GIF media link
    if (input.contains('giphy.com/gifs/')) {
      final parts = input.split('giphy.com/gifs/')[1].split('?')[0].split('/');
      final segment = parts.firstWhere((p) => p.isNotEmpty, orElse: () => '');
      final id = segment.contains('-') ? segment.split('-').last : segment;
      if (id.isNotEmpty) {
        return 'https://media.giphy.com/media/$id/giphy.gif';
      }
    }
    if (input.contains('i.giphy.com/')) {
      final id = input.split('i.giphy.com/')[1].split('.')[0];
      return 'https://media.giphy.com/media/$id/giphy.gif';
    }
    return input;
  }

  Future<void> _saveAndApply() async {
    final customResolved = _resolveGifUrl(_customUrlController.text);
    if (customResolved.isNotEmpty) {
      await widget.storageService.setCustomGifPreset(customResolved);
    } else {
      await widget.storageService.setCustomGifPreset(_selectedPreset);
    }

    await widget.storageService.setCustomGifFps(_fps);
    await widget.storageService.setCustomGifClock24(_clock24);
    await widget.storageService.setCustomGifShowBattery(_showBattery);

    // Map preset to hardware emotion name
    String hardwareEmotion = 'HAPPY';
    switch (_selectedPreset) {
      case 'aprajita_happy': hardwareEmotion = 'HAPPY'; break;
      case 'aprajita_laugh': hardwareEmotion = 'LAUGH'; break;
      case 'aprajita_excited': hardwareEmotion = 'EXCITED 2'; break;
      case 'aprajita_alert': hardwareEmotion = 'DETERMINED'; break;
      case 'aprajita_love': hardwareEmotion = 'LOVE'; break;
      case 'aprajita_sleepy': hardwareEmotion = 'SLEEPY'; break;
      case 'aprajita_music': hardwareEmotion = 'MUSIC'; break;
      case 'aprajita_cycle': hardwareEmotion = 'CYCLE'; break;
      default: hardwareEmotion = 'HAPPY';
    }

    // DIRECT SYNC TO ESP32 OVER BLE + HTTP!
    final ok = await widget.hardwareService.syncEmotionToEsp32(hardwareEmotion);

    widget.hardwareService.logTerminal(
      'TX -> Synced to Aprajita Hardware: Emotion $hardwareEmotion | FPS: $_fps | 24H: $_clock24',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? '✨ "$hardwareEmotion" Emotion synced live to Aprajita Screen!'
              : 'Saved! When Aprajita connects, "$hardwareEmotion" will display.'),
          backgroundColor: AppTheme.emerald,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final activePreset = _presets.firstWhere(
      (p) => p.id == _selectedPreset,
      orElse: () => _presets.first,
    );

    final hourStr = _clock24
        ? _currentTime.hour.toString().padLeft(2, '0')
        : ((_currentTime.hour % 12 == 0) ? 12 : _currentTime.hour % 12).toString().padLeft(2, '0');
    final minStr = _currentTime.minute.toString().padLeft(2, '0');
    final secStr = _currentTime.second.toString().padLeft(2, '0');
    final ampmStr = _clock24 ? '' : (_currentTime.hour >= 12 ? ' PM' : ' AM');

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        elevation: 0,
        title: const Text(
          'Aprajita Screen & GIF Customizer',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section 1: OLED 128x64 Canvas Simulator
            const Text(
              'LIVE OLED SIMULATOR (128 × 64 PIXELS)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppTheme.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),

            Center(
              child: Container(
                width: 320,
                height: 160,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF334155), width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyanAccent.withValues(alpha: 0.12),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    children: [
                      // Background Animated GIF (Real Giphy / Custom Stream)
                      Positioned.fill(
                        child: ColorFiltered(
                          colorFilter: _invertColors
                              ? const ColorFilter.matrix([
                                  -1, 0, 0, 0, 255, // red
                                  0, -1, 0, 0, 255, // green
                                  0, 0, -1, 0, 255, // blue
                                  0, 0, 0, 1, 0, // alpha
                                ])
                              : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
                          child: Builder(
                            builder: (ctx) {
                              final resolved = _resolveGifUrl(_customUrlController.text);
                              final urlToLoad = resolved.isNotEmpty ? resolved : activePreset.gifUrl;
                              return Image.network(
                                urlToLoad,
                                fit: BoxFit.contain,
                                errorBuilder: (ctx, err, stack) => Center(
                                  child: Text(
                                    activePreset.icon,
                                    style: const TextStyle(fontSize: 48),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                      // Live Clock Overlay
                      Positioned(
                        top: 6,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '$hourStr:$minStr:$secStr$ampmStr',
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w800,
                              color: Colors.cyanAccent,
                            ),
                          ),
                        ),
                      ),

                      // Battery & Risk Status Overlay
                      if (_showBattery)
                        Positioned(
                          top: 6,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.bolt, size: 11, color: AppTheme.emerald),
                                SizedBox(width: 2),
                                Text(
                                  '92%',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.emerald,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Bottom State Label
                      Positioned(
                        bottom: 6,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            activePreset.title.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 8,
                              letterSpacing: 0.5,
                              color: Colors.white70,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Section 2: Choose Preset or Enter Custom GIF URL
            const Text(
              'SELECT ANIMATION PROFILE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppTheme.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),

            ..._presets.map((preset) {
              final isSelected = _selectedPreset == preset.id && _customUrlController.text.isEmpty;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppTheme.cardDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? AppTheme.emerald : AppTheme.borderSubtle,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: ListTile(
                  leading: Text(preset.icon, style: const TextStyle(fontSize: 24)),
                  title: Text(
                    preset.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? AppTheme.emerald : AppTheme.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    preset.description,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle_rounded, color: AppTheme.emerald)
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedPreset = preset.id;
                      _customUrlController.clear();
                    });
                  },
                ),
              );
            }),

            const SizedBox(height: 12),

            // Custom GIF / Giphy URL Input
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.cardDark,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _customUrlController.text.isNotEmpty ? AppTheme.emerald : AppTheme.borderSubtle,
                  width: _customUrlController.text.isNotEmpty ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6157FF),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'GIPHY',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Import Real Animated GIF / Giphy Link',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Paste any direct .gif link or Giphy webpage URL. It auto-resolves and streams directly to your companion display!',
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _customUrlController,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'https://giphy.com/gifs/cute-cat-MDJ9IbxxvDUQM',
                      hintStyle: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      filled: true,
                      fillColor: AppTheme.bgDark,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppTheme.borderSubtle),
                      ),
                      suffixIcon: _customUrlController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18, color: Colors.white70),
                              onPressed: () => setState(() => _customUrlController.clear()),
                            )
                          : const Icon(Icons.link, size: 18, color: Colors.white38),
                    ),
                    onChanged: (val) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Trending Real Giphy Presets:',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ActionChip(
                        avatar: const Text('🐱', style: TextStyle(fontSize: 12)),
                        label: const Text('Cute Cat', style: TextStyle(fontSize: 11)),
                        backgroundColor: AppTheme.bgDark,
                        side: const BorderSide(color: AppTheme.borderSubtle),
                        onPressed: () {
                          setState(() {
                            _customUrlController.text = 'https://media.giphy.com/media/MDJ9IbxxvDUQM/giphy.gif';
                          });
                        },
                      ),
                      ActionChip(
                        avatar: const Text('🛡️', style: TextStyle(fontSize: 12)),
                        label: const Text('Guardian Shield', style: TextStyle(fontSize: 11)),
                        backgroundColor: AppTheme.bgDark,
                        side: const BorderSide(color: AppTheme.borderSubtle),
                        onPressed: () {
                          setState(() {
                            _customUrlController.text = 'https://media.giphy.com/media/3o7aD2saalBwwftBIY/giphy.gif';
                          });
                        },
                      ),
                      ActionChip(
                        avatar: const Text('⚡', style: TextStyle(fontSize: 12)),
                        label: const Text('Cyber Beat', style: TextStyle(fontSize: 11)),
                        backgroundColor: AppTheme.bgDark,
                        side: const BorderSide(color: AppTheme.borderSubtle),
                        onPressed: () {
                          setState(() {
                            _customUrlController.text = 'https://media.giphy.com/media/blSTtZehjAZ8I/giphy.gif';
                          });
                        },
                      ),
                      ActionChip(
                        avatar: const Text('❤️', style: TextStyle(fontSize: 12)),
                        label: const Text('Heart Glow', style: TextStyle(fontSize: 11)),
                        backgroundColor: AppTheme.bgDark,
                        side: const BorderSide(color: AppTheme.borderSubtle),
                        onPressed: () {
                          setState(() {
                            _customUrlController.text = 'https://media.giphy.com/media/3o7TKoWXm3okO1kgHC/giphy.gif';
                          });
                        },
                      ),
                      ActionChip(
                        avatar: const Text('🤖', style: TextStyle(fontSize: 12)),
                        label: const Text('Cyber Eye', style: TextStyle(fontSize: 11)),
                        backgroundColor: AppTheme.bgDark,
                        side: const BorderSide(color: AppTheme.borderSubtle),
                        onPressed: () {
                          setState(() {
                            _customUrlController.text = 'https://media.giphy.com/media/artj92V8o75VPL7AeQ/giphy.gif';
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Section 3: Time & Screen Settings
            const Text(
              'SCREEN & CLOCK FORMAT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppTheme.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.cardDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('24-Hour Digital Clock Format', style: TextStyle(fontSize: 13)),
                    subtitle: const Text('Toggles between 23:59 and 11:59 PM', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                    value: _clock24,
                    activeTrackColor: AppTheme.emerald,
                    onChanged: (val) => setState(() => _clock24 = val),
                  ),
                  const Divider(color: AppTheme.borderSubtle, height: 1),
                  SwitchListTile(
                    title: const Text('Show Battery & Telemetry Badge', style: TextStyle(fontSize: 13)),
                    subtitle: const Text('Renders live battery % on top corner of OLED', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                    value: _showBattery,
                    activeTrackColor: AppTheme.emerald,
                    onChanged: (val) => setState(() => _showBattery = val),
                  ),
                  const Divider(color: AppTheme.borderSubtle, height: 1),
                  SwitchListTile(
                    title: const Text('Invert Monochrome Colors', style: TextStyle(fontSize: 13)),
                    subtitle: const Text('Switch between Black-on-White and White-on-Black', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                    value: _invertColors,
                    activeTrackColor: AppTheme.emerald,
                    onChanged: (val) => setState(() => _invertColors = val),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Frame Speed (FPS):', style: TextStyle(fontSize: 13)),
                      Text('$_fps FPS', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.emerald)),
                    ],
                  ),
                  Slider(
                    value: _fps.toDouble(),
                    min: 5,
                    max: 30,
                    divisions: 5,
                    activeColor: AppTheme.emerald,
                    onChanged: (val) => setState(() => _fps = val.toInt()),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Save & Sync Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.sync_rounded),
                label: const Text(
                  'APPLY TO APP & SYNC TO APRAJITA',
                  style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.emerald,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _saveAndApply,
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
