import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// يرسم النص (العربي سليم) في صورة PNG شفافة، وFFmpeg يركّبها فوق الفيديو
class TextRender {
  static Future<String> png({
    required String text,
    required String outPath,
    required int width,
    required double fontSize,
    Color fill = Colors.white,
    Color stroke = Colors.black,
    bool box = false,
  }) async {
    final maxW = width * 0.9;
    final pad = fontSize * 0.35;
    final strokeW = fontSize * 0.2;

    TextPainter build(TextStyle style) => TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.center,
          maxLines: 3,
        )..layout(minWidth: maxW, maxWidth: maxW);

    final back = build(TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      height: 1.3,
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeJoin = StrokeJoin.round
        ..color = stroke,
    ));
    final front = build(TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      height: 1.3,
      color: fill,
    ));

    final h = (back.height + pad * 2).ceil();
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    final left = (width - maxW) / 2;

    if (box) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, 0, maxW, h.toDouble()),
          Radius.circular(fontSize * 0.4),
        ),
        Paint()..color = const Color(0xB3000000),
      );
    }
    back.paint(canvas, Offset(left, pad));
    front.paint(canvas, Offset(left, pad));

    final img = await rec.endRecording().toImage(width, h);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    await File(outPath).writeAsBytes(data!.buffer.asUint8List());
    return outPath;
  }
}