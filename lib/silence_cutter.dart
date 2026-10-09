import 'dart:async';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

class CutResult {
  final String path;
  final double originalSec;
  final double newSec;
  final int segments;
  CutResult(this.path, this.originalSec, this.newSec, this.segments);
}

/// يقص السكتات من الفيديو باستخدام FFmpeg (كله داخل الجوال)
class SilenceCutter {
  static String _f(double v) => v.toStringAsFixed(3);

  static String _tail(String s) =>
      s.length > 500 ? s.substring(s.length - 500) : s;

  static Future<CutResult> process(
    String input, {
    double noiseDb = -30,
    double minSilence = 0.5,
    double? maxSec,
    void Function(String)? onStatus,
    void Function(double)? onProgress,
  }) async {
    // 1) كشف السكتات
    onStatus?.call('جاري تحليل الصوت...');
    final detect = await FFmpegKit.execute(
        '-hide_banner -i "$input" -af silencedetect=noise=${noiseDb.toStringAsFixed(0)}dB:d=${minSilence.toStringAsFixed(2)} -vn -f null -');
    final logs = await detect.getAllLogsAsString() ?? '';
    final rc = await detect.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      throw Exception(
          'فشل تحليل الصوت (ممكن الفيديو بدون صوت).\n${_tail(logs)}');
    }

    // 2) المدة الكلية
    final d = RegExp(r'Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)').firstMatch(logs);
    if (d == null) throw Exception('ما قدرت أعرف مدة الفيديو.');
    final total = int.parse(d.group(1)!) * 3600 +
        int.parse(d.group(2)!) * 60 +
        double.parse(d.group(3)!);

    // 3) السكتات
    final starts = RegExp(r'silence_start:\s*(-?[\d.]+)')
        .allMatches(logs)
        .map((m) => double.parse(m.group(1)!))
        .toList();
    final ends = RegExp(r'silence_end:\s*(-?[\d.]+)')
        .allMatches(logs)
        .map((m) => double.parse(m.group(1)!))
        .toList();

    final silences = <List<double>>[];
    for (var i = 0; i < starts.length; i++) {
      final st = starts[i] < 0 ? 0.0 : starts[i];
      final en = i < ends.length ? ends[i] : total;
      silences.add([st, en > total ? total : en]);
    }

    // 4) مقاطع الكلام (مع هامش صغير عشان ما ينقص أول/آخر الكلمة)
    const pad = 0.08;
    const minSeg = 0.25;
    final keep = <List<double>>[];
    var cursor = 0.0;
    for (final s in silences) {
      final segEnd = (s[0] + pad) > total ? total : (s[0] + pad);
      if (segEnd - cursor > minSeg) keep.add([cursor, segEnd]);
      cursor = (s[1] - pad) < 0 ? 0.0 : (s[1] - pad);
    }
    if (total - cursor > minSeg) keep.add([cursor, total]);

    if (keep.isEmpty) {
      throw Exception('ما لقيت كلام في الفيديو. جرّب تقلل حساسية السكتة.');
    }
    final newSec = keep.fold<double>(0, (a, k) => a + (k[1] - k[0]));
    if (silences.isEmpty || (total - newSec) < 0.3) {
      throw Exception('ما لقيت سكتات تستحق القص. جرّب تزود الحساسية.');
    }

    if (maxSec != null && newSec > maxSec) {
      throw Exception(
          'الفيديو بعد القص ${newSec.toStringAsFixed(0)} ثانية، ورصيدك اليوم ${maxSec.toStringAsFixed(0)} ثانية فقط.\nشاهد إعلان لزيادة الرصيد أو اختر فيديو أقصر.');
    }

    // 5) القص والدمج
    onStatus?.call('جاري القص والتصدير (${keep.length} مقطع)...');
    final sb = StringBuffer();
    for (var i = 0; i < keep.length; i++) {
      sb.write(
          '[0:v]trim=start=${_f(keep[i][0])}:end=${_f(keep[i][1])},setpts=PTS-STARTPTS[v$i];');
      sb.write(
          '[0:a]atrim=start=${_f(keep[i][0])}:end=${_f(keep[i][1])},asetpts=PTS-STARTPTS[a$i];');
    }
    for (var i = 0; i < keep.length; i++) {
      sb.write('[v$i][a$i]');
    }
    // دقة 2K (الضلع الأقصر 1440) مع الحفاظ على النسبة
    sb.write('concat=n=${keep.length}:v=1:a=1[vc][a];');
    sb.write(
        '[vc]scale=1440:1440:force_original_aspect_ratio=increase:force_divisible_by=2[v]');

    final dir = (await getExternalStorageDirectory()) ??
        await getApplicationDocumentsDirectory();
    final out = '${dir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.mp4';

    String cmd(String vcodec) =>
        '-y -i "$input" -filter_complex "${sb.toString()}" -map "[v]" -map "[a]" '
        '$vcodec -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart "$out"';

    var ok = await _encode(
        cmd('-c:v libx264 -preset veryfast -b:v 2200k -maxrate 2600k -bufsize 5200k'), newSec, onProgress);
    if (!ok) {
      // خطة بديلة لو libx264 غير متوفر
      onStatus?.call('جاري المحاولة بترميز بديل...');
      ok = await _encode(cmd('-c:v mpeg4 -b:v 2200k'), newSec, onProgress);
    }
    if (!ok || !File(out).existsSync()) {
      throw Exception('فشل التصدير.');
    }
    return CutResult(out, total, newSec, keep.length);
  }

  /// يستخرج صورة غلاف من الفيديو نفسه (يرجع المسار أو null)
  static Future<String?> makeThumb(String video, double durationSec) async {
    final thumb = video.replaceAll('.mp4', '_cover.jpg');
    final at = durationSec > 2 ? 1.0 : 0.0;
    await FFmpegKit.execute(
        '-y -ss ${at.toStringAsFixed(1)} -i "$video" -frames:v 1 -q:v 2 "$thumb"');
    return File(thumb).existsSync() ? thumb : null;
  }

  static Future<bool> _encode(
      String command, double expectedSec, void Function(double)? onProgress) {
    final c = Completer<bool>();
    FFmpegKit.executeAsync(command, (session) async {
      final rc = await session.getReturnCode();
      c.complete(ReturnCode.isSuccess(rc));
    }, null, (stats) {
      final num t = stats.getTime();
      if (t > 0 && expectedSec > 0) {
        onProgress?.call((t / 1000 / expectedSec).clamp(0.0, 1.0));
      }
    });
    return c.future;
  }
}