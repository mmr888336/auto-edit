import 'dart:io';
import 'dart:math' as math;
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:flutter/material.dart';
import 'analyzer.dart';
import 'broll.dart';
import 'settings.dart';
import 'silence_cutter.dart';
import 'text_render.dart';

class EnhanceResult {
  final String videoPath;
  final String? coverPath;
  final String title;
  final String description;
  final List<String> hashtags;
  final List<String> notes;
  final double sizeMb;
  final int outW;
  final int outH;
  EnhanceResult({
    required this.videoPath,
    required this.coverPath,
    required this.title,
    required this.description,
    required this.hashtags,
    required this.notes,
    required this.sizeMb,
    required this.outW,
    required this.outH,
  });
}

class _Broll {
  final String path;
  final double start;
  final double end;
  _Broll(this.path, this.start, this.end);
}

/// بعد قص السكتات: كابشن + عنوان + B-roll + مؤثرات + غلاف + تصدير بالحجم المطلوب
class Enhancer {
  static String _f(double v) => v.toStringAsFixed(2);

  static Future<bool> _run(String cmd) async {
    final s = await FFmpegKit.execute(cmd);
    return ReturnCode.isSuccess(await s.getReturnCode());
  }

  static Future<EnhanceResult> run({
    required String cutPath,
    required double cutSec,
    required AppSettings s,
    void Function(String)? onStatus,
    void Function(double)? onProgress,
  }) async {
    final notes = <String>[];
    final temps = <String>[];
    final dir = File(cutPath).parent.path;
    final stamp = DateTime.now().millisecondsSinceEpoch;

    // الأبعاد النهائية
    onStatus?.call('جاري فحص الفيديو...');
    final info = await SilenceCutter.probe(cutPath);
    final short = math.min(info.w, info.h);
    final targetShort = s.upscale2k ? 1440 : math.min(short, 1440);
    final factor = targetShort / short;
    int even(double v) {
      var r = v.round();
      if (r.isOdd) r += 1;
      return r;
    }

    final outW = even(info.w * factor);
    final outH = even(info.h * factor);
    final portrait = outH >= outW;

    // 1) تحليل الصوت بالذكاء الاصطناعي
    Analysis? an;
    if (s.geminiKey.trim().isEmpty) {
      notes.add('ما في مفتاح Gemini: ما اتضاف كابشن ولا عنوان.');
    } else if (cutSec > 300) {
      notes.add('الفيديو أطول من 5 دقايق: تخطّيت التحليل بالذكاء الاصطناعي.');
    } else {
      try {
        onStatus?.call('جاري تفريغ الصوت وتحليله بالذكاء الاصطناعي...');
        final wav = '$dir/audio_$stamp.wav';
        temps.add(wav);
        final ok = await _run(
            '-y -i "$cutPath" -vn -ac 1 -ar 16000 -c:a pcm_s16le "$wav"');
        if (!ok) throw Exception('تعذر استخراج الصوت');
        an = await Analyzer.run(s, wav, cutSec);
      } catch (e) {
        notes.add('تعذر التحليل: $e');
      }
    }
    final analysis = an;

    // 2) صور الكابشن والعنوان
    final caps = <Caption>[];
    final capFiles = <String>[];
    String? hookFile;
    if (analysis != null) {
      try {
        if (s.captions) {
          onStatus?.call('جاري تجهيز الكابشن...');
          for (var i = 0; i < analysis.captions.length; i++) {
            final p = '$dir/cap_${stamp}_$i.png';
            await TextRender.png(
              text: analysis.captions[i].text,
              outPath: p,
              width: outW,
              fontSize: outW * 0.062,
              fill: Colors.white,
            );
            temps.add(p);
            caps.add(analysis.captions[i]);
            capFiles.add(p);
          }
          if (caps.isEmpty) notes.add('ما طلع كابشن (ما اتعرف كلام).');
        }
        if (s.hook && analysis.title.isNotEmpty) {
          hookFile = await TextRender.png(
            text: analysis.title,
            outPath: '$dir/hook_$stamp.png',
            width: outW,
            fontSize: outW * 0.085,
            fill: const Color(0xFFFFD400),
            box: true,
          );
          temps.add(hookFile);
        }
      } catch (e) {
        notes.add('تعذر رسم النصوص: $e');
      }
    }

    // 3) B-roll
    final brolls = <_Broll>[];
    if (s.broll && analysis != null && analysis.broll.isNotEmpty) {
      final hasKey = s.brollProvider == 'pixabay'
          ? s.pixabayKey.trim().isNotEmpty
          : s.pexelsKey.trim().isNotEmpty;
      if (!hasKey) {
        notes.add('ما في مفتاح ${s.brollProvider} للـ B-roll. ضعه في الإعدادات.');
      } else {
        try {
          final ideas = analysis.broll
              .where((b) =>
                  b.start >= 3.5 &&
                  b.end <= cutSec - 0.3 &&
                  b.end - b.start >= 1.5)
              .toList()
            ..sort((a, b) => a.start.compareTo(b.start));
          var lastEnd = 0.0;
          var i = 0;
          for (final b in ideas) {
            if (brolls.length >= 4) break;
            if (b.start < lastEnd + 1.0) continue;
            onStatus?.call('جاري تحميل B-roll (${brolls.length + 1})...');
            final p = '$dir/broll_${stamp}_$i.mp4';
            final got = await BrollFetcher.fetch(s, b.query, portrait, p, i);
            i++;
            if (got != null) {
              temps.add(got);
              brolls.add(_Broll(got, b.start, b.end));
              lastEnd = b.end;
            }
          }
          if (brolls.isEmpty) {
            notes.add('ما قدرت أجيب مقاطع B-roll (تحقق من المفتاح أو النت).');
          }
        } catch (e) {
          notes.add('تعذر B-roll: $e');
        }
      }
    }

    // 4) مؤثر صوتي (وش) يتولد بـ FFmpeg
    String? whoosh;
    if (s.sfx) {
      final w = '$dir/whoosh_$stamp.wav';
      final ok = await _run(
          '-y -f lavfi -i "anoisesrc=d=0.6:c=pink:a=0.6" -af "highpass=f=250,lowpass=f=4000,afade=t=in:st=0:d=0.25,afade=t=out:st=0.25:d=0.35" "$w"');
      if (ok && File(w).existsSync()) {
        whoosh = w;
        temps.add(w);
      } else {
        notes.add('تعذر توليد المؤثرات الصوتية.');
      }
    }

    // 5) التركيب والتصدير
    final totalKbps = s.targetMb * 279.6; // معدل البت الكلي لحجم معين لكل 30 ث
    final vK = (totalKbps - 128).clamp(800.0, 14000.0).round();
    final out = '$dir/final_$stamp.mp4';

    final inputs = <String>['-i "$cutPath"'];
    final chains = <String>[
      '[0:v]scale=$outW:$outH:flags=lanczos,setsar=1[base]'
    ];
    var cur = 'base';
    var n = 0;
    final sfxTimes = <double>[];

    for (final b in brolls) {
      final idx = inputs.length;
      inputs.add('-i "${b.path}"');
      chains.add(
          '[$idx:v]scale=$outW:$outH:force_original_aspect_ratio=increase,crop=$outW:$outH,setsar=1,setpts=PTS-STARTPTS+${_f(b.start)}/TB[bv$idx]');
      final o = 'o${n++}';
      chains.add(
          "[$cur][bv$idx]overlay=x=0:y=0:enable='between(t,${_f(b.start)},${_f(b.end)})'[$o]");
      cur = o;
      sfxTimes.add(b.start);
    }

    for (var i = 0; i < capFiles.length; i++) {
      final c = caps[i];
      final idx = inputs.length;
      inputs.add('-i "${capFiles[i]}"');
      final o = 'o${n++}';
      chains.add(
          "[$cur][$idx:v]overlay=x=0:y=main_h*0.70-overlay_h/2:enable='between(t,${_f(c.start)},${_f(c.end)})'[$o]");
      cur = o;
    }

    if (hookFile != null) {
      final idx = inputs.length;
      inputs.add('-i "$hookFile"');
      final o = 'o${n++}';
      chains.add(
          "[$cur][$idx:v]overlay=x=0:y=main_h*0.10:enable='between(t,0.1,3.1)'[$o]");
      cur = o;
      sfxTimes.insert(0, 0.1);
    }

    var audioMap = '0:a';
    if (whoosh != null && sfxTimes.isNotEmpty) {
      final times = sfxTimes.take(6).toList();
      final mix = StringBuffer();
      for (var k = 0; k < times.length; k++) {
        final idx = inputs.length;
        inputs.add('-i "$whoosh"');
        final ms = (times[k] * 1000).round();
        chains.add('[$idx:a]adelay=$ms|$ms,apad,volume=0.8[sf$k]');
        mix.write('[sf$k]');
      }
      chains.add(
          '[0:a]${mix.toString()}amix=inputs=${times.length + 1}:duration=first:dropout_transition=0,volume=${times.length + 1}[aout]');
      audioMap = '[aout]';
    }

    final tail =
        '-c:v libx264 -preset veryfast -crf 21 -maxrate ${vK}k -bufsize ${vK * 2}k -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart -t ${_f(cutSec + 0.2)} "$out"';
    final fullCmd =
        '-y ${inputs.join(' ')} -filter_complex "${chains.join(';')}" -map "[$cur]" -map ${audioMap == '0:a' ? '0:a' : '"[aout]"'} $tail';

    onStatus?.call('جاري التركيب والتصدير بـ ${outW}x$outH ...');
    var ok = await SilenceCutter.encode(fullCmd, cutSec, onProgress);

    if (!ok) {
      notes.add('فشل التركيب الكامل، صدّرت نسخة بسيطة بدون إضافات.');
      onStatus?.call('جاري التصدير البسيط...');
      final simple =
          '-y -i "$cutPath" -vf "scale=$outW:$outH:flags=lanczos" -c:v libx264 -preset veryfast -crf 21 -maxrate ${vK}k -bufsize ${vK * 2}k -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart "$out"';
      ok = await SilenceCutter.encode(simple, cutSec, onProgress);
      if (!ok) {
        final simple2 =
            '-y -i "$cutPath" -vf "scale=$outW:$outH" -c:v mpeg4 -b:v ${vK}k -c:a aac -b:a 128k "$out"';
        ok = await SilenceCutter.encode(simple2, cutSec, onProgress);
      }
    }

    final finalPath = (ok && File(out).existsSync()) ? out : cutPath;
    if (finalPath == cutPath) notes.add('فشل التصدير النهائي، هذه نسخة القص فقط.');

    // 6) الغلاف: لقطة من الفيديو + العنوان
    String? coverPath;
    try {
      onStatus?.call('جاري تجهيز الغلاف...');
      final at = cutSec > 2 ? 1.0 : 0.0;
      final cov = '$dir/cover_$stamp.jpg';
      bool cok;
      if (analysis != null && analysis.title.isNotEmpty) {
        final cp = await TextRender.png(
          text: analysis.title,
          outPath: '$dir/covtitle_$stamp.png',
          width: outW,
          fontSize: outW * 0.105,
          fill: const Color(0xFFFFD400),
          box: true,
        );
        temps.add(cp);
        cok = await _run(
            '-y -ss ${_f(at)} -i "$cutPath" -i "$cp" -filter_complex "[0:v]scale=$outW:$outH:flags=lanczos,setsar=1[b];[b][1:v]overlay=x=0:y=(main_h-overlay_h)/2[o]" -map "[o]" -frames:v 1 -q:v 2 "$cov"');
      } else {
        cok = await _run(
            '-y -ss ${_f(at)} -i "$cutPath" -vf "scale=$outW:$outH:flags=lanczos" -frames:v 1 -q:v 2 "$cov"');
      }
      if (cok && File(cov).existsSync()) coverPath = cov;
    } catch (_) {}

    // تنظيف الملفات المؤقتة
    for (final t in temps) {
      try {
        File(t).deleteSync();
      } catch (_) {}
    }
    if (finalPath != cutPath) {
      try {
        File(cutPath).deleteSync();
      } catch (_) {}
    }

    final mb = File(finalPath).lengthSync() / (1024 * 1024);
    return EnhanceResult(
      videoPath: finalPath,
      coverPath: coverPath,
      title: analysis?.title ?? '',
      description: analysis?.description ?? '',
      hashtags: analysis?.hashtags ?? [],
      notes: notes,
      sizeMb: mb,
      outW: outW,
      outH: outH,
    );
  }
}