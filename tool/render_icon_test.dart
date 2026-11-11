// Tekent het app-icoon. Opnieuw maken: flutter test tool/render_icon_test.dart
// en daarna: dart run flutter_launcher_icons
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _bgTop = Color(0xFF7C5CD6);
const _bgBottom = Color(0xFF4A2F9E);
const _ink = Color(0xFF4A2F9E);

/// Symbool: witte cirkel met afspeeldriehoek, met aan beide kanten twee geluidsgolven.
void _symbol(Canvas c, Offset center, double s, {bool cutout = false}) {
  // Bij [cutout] wordt de driehoek uitgespaard (transparant), voor monochrome thema-iconen.
  c.saveLayer(null, Paint());
  final white = Paint()..color = Colors.white;
  c.drawCircle(center, s * 0.22, white);

  final r = s * 0.22;
  final tri = Path()
    ..moveTo(center.dx - r * 0.32, center.dy - r * 0.48)
    ..lineTo(center.dx + r * 0.55, center.dy)
    ..lineTo(center.dx - r * 0.32, center.dy + r * 0.48)
    ..close();
  c.drawPath(
      tri,
      Paint()
        ..color = _ink
        ..blendMode = cutout ? BlendMode.clear : BlendMode.srcOver
        ..style = PaintingStyle.fill
        ..strokeJoin = StrokeJoin.round);
  c.drawPath(
      tri,
      Paint()
        ..color = _ink
        ..blendMode = cutout ? BlendMode.clear : BlendMode.srcOver
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.12
        ..strokeJoin = StrokeJoin.round);

  final wave = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  for (final (radius, width, alpha) in [(0.33, 0.055, 1.0), (0.44, 0.05, 0.6)]) {
    wave
      ..strokeWidth = s * width
      ..color = Colors.white.withValues(alpha: alpha);
    final rect = Rect.fromCircle(center: center, radius: s * radius);
    const sweep = pi / 2.6;
    c.drawArc(rect, -sweep / 2, sweep, false, wave); // rechts
    c.drawArc(rect, pi - sweep / 2, sweep, false, wave); // links
  }
  c.restore();
}

Future<void> _save(String path, int size, void Function(Canvas, double) paint) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  paint(canvas, size.toDouble());
  final img = await rec.endRecording().toImage(size, size);
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(png!.buffer.asUint8List());
}

void _background(Canvas c, double s) {
  c.drawRect(
      Rect.fromLTWH(0, 0, s, s),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(s, s), [_bgTop, _bgBottom]));
}

void main() {
  testWidgets('app-icoon renderen', (tester) async {
    await tester.runAsync(() async {
      // Volledig icoon (iOS, Windows, oudere Android): achtergrond tot de rand.
      await _save('assets/icon/icon.png', 1024, (c, s) {
        _background(c, s);
        _symbol(c, Offset(s / 2, s / 2), s * 0.88);
      });
      // Adaptief Android-icoon: alleen het symbool. Android zet er zelf 16% marge omheen,
      // zodat het binnen de veilige zone valt.
      await _save('assets/icon/foreground.png', 1024, (c, s) {
        _symbol(c, Offset(s / 2, s / 2), s * 0.95);
      });
      // Monochroom (Android 13+ thema-iconen).
      await _save('assets/icon/monochrome.png', 1024, (c, s) {
        _symbol(c, Offset(s / 2, s / 2), s * 0.95, cutout: true);
      });
    });
  });
}
