import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The chat background as on WhatsApp for iPhone: beige (light) or night
/// green (dark) with faint doodles, here electrical ones (bolts, bulbs,
/// plugs, wrenches, gears). Drawn once and kept, so scrolling stays smooth.
class ChatWallpaper extends StatelessWidget {
  const ChatWallpaper({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: dark ? ChatColors.wallpaperDark : ChatColors.wallpaper,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: _Doodles(
                dark
                    ? Colors.white.withValues(alpha: 0.045)
                    : const Color(0xFF8B7E6A).withValues(alpha: 0.13),
              ),
            ),
          ),
          ?child,
        ],
      ),
    );
  }
}

class _Doodles extends CustomPainter {
  _Doodles(this.color);

  final Color color;

  static const _icons = [
    CupertinoIcons.bolt,
    CupertinoIcons.lightbulb,
    CupertinoIcons.wrench,
    CupertinoIcons.gear_alt,
    CupertinoIcons.phone,
    CupertinoIcons.chat_bubble,
    CupertinoIcons.battery_25,
    CupertinoIcons.hammer,
    CupertinoIcons.camera,
    CupertinoIcons.music_note,
    CupertinoIcons.cloud_bolt,
    CupertinoIcons.star,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const step = 64.0;
    final r = math.Random(7);
    var i = 0;
    for (var y = -step / 2; y < size.height + step; y += step) {
      final shift = (y / step).round().isOdd ? step / 2 : 0.0;
      for (var x = -step / 2 + shift; x < size.width + step; x += step) {
        final icon = _icons[i++ % _icons.length];
        final tp = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
              fontSize: 22 + r.nextDouble() * 8,
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
              color: color,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        canvas.save();
        canvas.translate(x + r.nextDouble() * 14, y + r.nextDouble() * 14);
        canvas.rotate((r.nextDouble() - 0.5) * 0.9);
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_Doodles old) => old.color != color;
}

/// Chat screens in WhatsApp green (buttons, links, selection); the rest of
/// the app stays burgundy.
class ChatThemed extends StatelessWidget {
  const ChatThemed({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Theme(data: AppTheme.chat(Theme.of(context)), child: child);
}
