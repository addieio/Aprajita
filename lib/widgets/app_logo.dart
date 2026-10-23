import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final bool showGlow;
  final bool withText;

  const AppLogo({
    super.key,
    this.size = 36,
    this.showGlow = true,
    this.withText = false,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(size * 0.28);

    final logoBadge = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF12141B),
        borderRadius: borderRadius,
        border: Border.all(
          color: AppTheme.crimson.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: AppTheme.crimson.withValues(alpha: 0.25),
                  blurRadius: size * 0.35,
                  spreadRadius: 0,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.25),
        child: Image.asset(
          'assets/images/logo.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return CustomPaint(
              size: Size(size, size),
              painter: MinimalistLogoPainter(),
            );
          },
        ),
      ),
    );

    if (!withText) {
      return logoBadge;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        logoBadge,
        const SizedBox(width: 12),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'APRAJITA',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.4,
                color: AppTheme.textPrimary,
              ),
            ),
            SizedBox(height: 1),
            Text(
              'SAFETY & EMERGENCY SOS',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Fallback crisp vector painter for minimalist shield emblem
class MinimalistLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paint = Paint()
      ..color = AppTheme.crimson
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.08
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    // Geometric minimalist shield
    path.moveTo(w * 0.2, h * 0.28);
    path.lineTo(w * 0.8, h * 0.28);
    path.lineTo(w * 0.8, h * 0.55);
    path.quadraticBezierTo(w * 0.8, h * 0.82, w * 0.5, h * 0.92);
    path.quadraticBezierTo(w * 0.2, h * 0.82, w * 0.2, h * 0.55);
    path.close();

    canvas.drawPath(path, paint);

    // Inner stylized 'A' chevron
    final innerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.08
      ..strokeCap = StrokeCap.round;

    final innerPath = Path();
    innerPath.moveTo(w * 0.35, h * 0.65);
    innerPath.lineTo(w * 0.5, h * 0.42);
    innerPath.lineTo(w * 0.65, h * 0.65);

    canvas.drawPath(innerPath, innerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
