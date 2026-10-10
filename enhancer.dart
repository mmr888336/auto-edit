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

/// بعد قص السكتات: كابشن + عنوان + B-roll + مؤثرات + تحسين صوت + غلاف + تصدير بالحجم المطلوب
class Enhancer {
  static String _f(double v) => v.toStringAsFixed(2);

  static void _checkCancel() {
    if (JobControl.cancelled) throw Exception('تم إلغاء المونتاج.');
  }

  static Future<bool> _run(String cmd) async {
    final session = await FFmpegKit.execute(cmd);
    return ReturnCode.isSuccess(await session.getReturnCode());
  }

  static String _styleFilter(String style) {
    switch (style) {
      case 'clean':
        return ',eq=contrast=1.05:saturation=1.08,unsharp=5:5:0.4:3:3:0.0';
      case 'vivid':
        return ',eq=contrast=1.08:saturation=1.30:brightness=0.01,unsharp=5:5:0.45:3:3:0.0';
      case 'cinematic':
      default:
        return ',colorbalance=rs=-0.04:bs=0.05:rh=0.05:bh=-0.04,eq=contrast=1.10:saturation=1.05:brightness=-0.01,unsharp=5:5:0.35:3:3:0.0,vignette=angle=PI/5';
    }
  }

  /// يفحص مقطع B-roll بصرياً: true = آمن (ما فيه امرأة)
  static Future<bool> _clipIsSafe(
      AppSettings s, String clip, String dir, int stamp, String tag, List<String> temps) async {
    try {
      final jpg = '$dir/chk_${stamp}_$tag.jpg';
      temps.add(jpg);
      final ok = await _run(
          '-y -ss 1 -i "$clip" -frames:v 1 -vf scale=320:-2 -q:v 5 "$jpg"');
      if (!ok || !File(jpg).existsSync()) return false;
      final woman = await Analyzer.containsWoman(s, jpg);
      return !woman;
    } catch (_) {
      return false; // ما قدرنا نتأكد، فنتجاهل المقطع احتياطاً
    }
  }

  static Future<EnhanceResult> run({
    required String cutPath,
    required double cutSec,
    required AppSettings s,
    List<double> cutTimes = const [],
    void Function(String)? onStatus,
    void Function(double)? onProgress,
  }) async {
    final notes = <String>[];
    final temps = <String>[];
    final dir = File(cutPath).parent.path;
    final stamp = DateTime.now().millisecondsSinceEpoch;

    onStatus?.call('جاري فحص الفيديو...');
    final info = await SilenceCutter.probe(cutPath);
    final short = math.min(info.w, info.h);
    final targetShort = s.upscale2k ? 1440 : math.min(short, 1440);
    final factor = targetShort / short;
    int even(double value) {
      var result = value.round();
      if (result.isOdd) result++;
      return result;
    }

    final outW = even(info.w * factor);
    final outH = even(info.h * factor);
    final portrait = outH >= outW;

    // 1) تحليل الصوت بالذكاء الاصطناعي (Gemini يسمع الصوت)
    Analysis? an;
    if (s.geminiKey.trim().isEmpty) {
      notes.add('ما في مفتاح Gemini؛ لم تتم إضافة الكابشن أو العنوان أو B-roll.');
    } else if (cutSec > 300) {
      notes.add('الفيديو أطول من 5 دقائق؛ تم تخطي التحليل بالذكاء الاصطناعي.');
    } else {
      try {
        _checkCancel();
        onStatus?.call('جاري تفريغ الصوت وتحليله بالذكاء الاصطناعي...');
        final wav = '$dir/audio_$stamp.wav';
        temps.add(wav);
        final ok = await _run(
            '-y -i "$cutPath" -vn -ac 1 -ar 16000 -c:a pcm_s16le "$wav"');
        if (!ok) throw Exception('تعذر استخراج الصوت من الفيديو.');
        an = await Analyzer.run(s, wav, cutSec);
      } catch (e) {
        if (JobControl.cancelled) rethrow;
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
            final path = '$dir/cap_${stamp}_$i.png';
            await TextRender.png(
              text: analysis.captions[i].text,
              outPath: path,
              width: outW,
              fontSize: outW * 0.062,
              fill: Colors.white,
            );
            temps.add(path);
            caps.add(analysis.captions[i]);
            capFiles.add(path);
          }
          if (caps.isEmpty) notes.add('لم يتم التعرف على كلام مناسب للكابشن.');
        }
        if (s.hook && analysis.title.isNotEmpty) {
          final path = await TextRender.png(
            text: analysis.title,
            outPath: '$dir/hook_$stamp.png',
            width: outW,
            fontSize: outW * 0.085,
            fill: const Color(0xFFFFD400),
            box: true,
          );
          temps.add(path);
          hookFile = path;
        }
      } catch (e) {
        notes.add('تعذر رسم النصوص: $e');
      }
    }

    // 3) B-roll مرتبط بمعنى الكلام، بدون نساء (فلتر وصف + فحص بصري بـ Gemini)
    final brolls = <_Broll>[];
    if (s.broll && analysis != null && analysis.broll.isNotEmpty) {
      final hasKey = s.brollProvider == 'pixabay'
          ? s.pixabayKey.trim().isNotEmpty
          : s.pexelsKey.trim().isNotEmpty;
      if (!hasKey) {
        notes.add('لا يوجد مفتاح ${s.brollProvider} للـ B-roll. أضفه من الإعدادات.');
      } else {
        try {
          final ideas = analysis.broll
              .where((b) =>
                  b.start >= 3.5 && b.end <= cutSec - 0.3 && b.end - b.start >= 1.5)
              .toList()
            ..sort((a, b) => a.start.compareTo(b.start));
          var lastEnd = 0.0;
          var index = 0;
          for (final idea in ideas) {
            if (brolls.length >= 4) break;
            if (idea.start < lastEnd + 1.0) continue;
            _checkCancel();
            onStatus?.call('جاري تحميل وفحص B-roll (${brolls.length + 1})...');
            String? got;
            for (var attempt = 0; attempt < 3 && got == null; attempt++) {
              // المحاولة الأخيرة: رسوم متحركة 2D (Pixabay) لو المقاطع الواقعية فيها نساء
              final animation = attempt == 2;
              final out = '$dir/broll_${stamp}_${index}_$attempt.mp4';
              final file = await BrollFetcher.fetch(
                  s, idea.query, portrait, out, index + attempt,
                  animation: animation);
              if (file == null) continue;
              temps.add(file);
              final safe = await _clipIsSafe(s, file, dir, stamp, '${index}_$attempt', temps);
              if (safe) {
                got = file;
              } else {
                try {
                  File(file).deleteSync();
                } catch (_) {}
              }
            }
            index++;
            if (got != null) {
              brolls.add(_Broll(got, idea.start, idea.end));
              lastEnd = idea.end;
            }
          }
          if (brolls.isEmpty) {
            notes.add('لم أجد مقاطع B-roll مناسبة وآمنة؛ بقي الفيديو الأصلي.');
          }
        } catch (e) {
          if (JobControl.cancelled) rethrow;
          notes.add('تعذر تحميل B-roll: $e');
        }
      }
    }

    // 4) مؤثر صوتي (وش) يتولد بـ FFmpeg
    String? whoosh;
    if (s.sfx) {
      final path = '$dir/whoosh_$stamp.wav';
      final ok = await _run(
          '-y -f lavfi -i "anoisesrc=d=0.6:c=pink:a=0.45" -af "highpass=f=250,lowpass=f=4000,afade=t=in:st=0:d=0.25,afade=t=out:st=0.25:d=0.35" "$path"');
      if (ok && File(path).existsSync()) {
        whoosh = path;
        temps.add(path);
      } else {
        notes.add('تعذر توليد المؤثرات الصوتية.');
      }
    }

    // 5) التركيب والتصدير
    final totalKbps = s.targetMb * 279.6;
    final vK = (totalKbps - 128).clamp(800.0, 14000.0).round();
    final out = '$dir/final_$stamp.mp4';
    final hook = hookFile;

    String buildCommand({required bool audioFx, required bool visFx}) {
      final inputs = <String>['-i "$cutPath"'];
      final style = (visFx && s.visualEffects) ? _styleFilter(s.visualStyle) : '';
      final chains = <String>[
        '[0:v]scale=$outW:$outH:flags=lanczos,setsar=1$style[base]'
      ];
      var cur = 'base';
      var n = 0;
      String next() => 'v${n++}';
      final sfxTimes = <double>[];
      final flashTimes = <double>[];

      // تقريب سريع بالتناوب عند القطع (Punch-in)
      if (visFx && s.visualEffects && s.punchZoom && cutTimes.length >= 3) {
        final wins = <String>[];
        for (var i = 1; i < cutTimes.length; i += 2) {
          final st = cutTimes[i];
          final en = (i + 1 < cutTimes.length) ? cutTimes[i + 1] : cutSec;
          if (en - st > 0.3) wins.add('between(t,${_f(st)},${_f(en)})');
        }
        if (wins.isNotEmpty) {
          final o = next();
          chains.add('[$cur]split[za][zb]');
          chains.add(
              '[zb]crop=w=iw/1.12:h=ih/1.12:x=(iw-ow)/2:y=(ih-oh)/2,scale=$outW:$outH:flags=bicubic[zc]');
          chains.add(
              "[za][zc]overlay=x=0:y=0:enable='${wins.take(60).join('+')}'[$o]");
          cur = o;
        }
      }

      for (final b in brolls) {
        final idx = inputs.length;
        inputs.add('-i "${b.path}"');
        chains.add(
            '[$idx:v]scale=$outW:$outH:force_original_aspect_ratio=increase,crop=$outW:$outH,setsar=1,setpts=PTS-STARTPTS+${_f(b.start)}/TB[bv$idx]');
        final o = next();
        chains.add(
            "[$cur][bv$idx]overlay=x=0:y=0:enable='between(t,${_f(b.start)},${_f(b.end)})'[$o]");
        cur = o;
        sfxTimes.add(b.start);
        flashTimes.add(b.start);
      }

      // وميض انتقالي قصير عند بداية كل B-roll
      if (visFx && s.visualEffects && s.flashTransitions && flashTimes.isNotEmpty) {
        final en = flashTimes
            .map((t) => 'between(t,${_f(t)},${_f(t + 0.07)})')
            .join('+');
        final o = next();
        chains.add(
            "[$cur]drawbox=x=0:y=0:w=iw:h=ih:color=white@0.5:t=fill:enable='$en'[$o]");
        cur = o;
      }

      for (var i = 0; i < capFiles.length; i++) {
        final c = caps[i];
        final idx = inputs.length;
        inputs.add('-i "${capFiles[i]}"');
        final o = next();
        chains.add(
            "[$cur][$idx:v]overlay=x=0:y=main_h*0.70-overlay_h/2:enable='between(t,${_f(c.start)},${_f(c.end)})'[$o]");
        cur = o;
      }

      if (hook != null) {
        final idx = inputs.length;
        inputs.add('-i "$hook"');
        final o = next();
        chains.add(
            "[$cur][$idx:v]overlay=x=0:y=main_h*0.10:enable='between(t,0.1,3.1)'[$o]");
        cur = o;
        sfxTimes.insert(0, 0.1);
      }

      // شريط تقدم أسفل الفيديو
      if (visFx && s.visualEffects && s.progressBar) {
        final idx = inputs.length;
        inputs.add(
            '-f lavfi -i "color=c=0xFFD400:s=${outW}x14:r=30:d=${_f(cutSec + 1)}"');
        final o = next();
        chains.add(
            '[$cur][$idx:v]overlay=x=-overlay_w+main_w*t/${_f(cutSec)}:y=main_h-14[$o]');
        cur = o;
      }

      // الصوت: تحسين + مؤثرات
      var aLabel = '0:a';
      if (audioFx && s.enhanceAudio) {
        chains.add(
            '[0:a]highpass=f=80,afftdn=nf=-25,acompressor=threshold=0.1:ratio=3:attack=20:release=250,loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000[clean]');
        aLabel = 'clean';
      }
      var audioMap = aLabel == '0:a' ? '0:a' : '"[clean]"';
      if (whoosh != null && sfxTimes.isNotEmpty) {
        final times = sfxTimes.take(6).toList();
        final mix = StringBuffer();
        for (var k = 0; k < times.length; k++) {
          final idx = inputs.length;
          inputs.add('-i "$whoosh"');
          final ms = (times[k] * 1000).round();
          chains.add('[$idx:a]adelay=$ms|$ms,apad,volume=0.45[sf$k]');
          mix.write('[sf$k]');
        }
        final count = times.length + 1;
        chains.add(
            '[$aLabel]${mix.toString()}amix=inputs=$count:duration=first:dropout_transition=0,volume=$count,alimiter=limit=0.95[aout]');
        audioMap = '"[aout]"';
      }

      final tail =
          '-c:v libx264 -preset veryfast -crf 21 -maxrate ${vK}k -bufsize ${vK * 2}k -pix_fmt yuv420p -c:a aac -b:a 128k -ar 48000 -movflags +faststart -t ${_f(cutSec + 0.2)} "$out"';
      return '-y ${inputs.join(' ')} -filter_complex "${chains.join(';')}" -map "[$cur]" -map $audioMap $tail';
    }

    onStatus?.call('جاري التصدير ${outW}×$outH مع التحسينات...');
    var ok = await SilenceCutter.encode(
        buildCommand(audioFx: true, visFx: true), cutSec, onProgress);

    if (!ok) {
      _checkCancel();
      notes.add('بعض الفلاتر المتقدمة ما اشتغلت؛ صدّرت بدونها مع الكابشن والـ B-roll.');
      onStatus?.call('جاري التصدير بدون الفلاتر المتقدمة...');
      ok = await SilenceCutter.encode(
          buildCommand(audioFx: false, visFx: false), cutSec, onProgress);
    }
    if (!ok) {
      _checkCancel();
      notes.add('فشل التركيب؛ صدّرت نسخة بسيطة.');
      onStatus?.call('جاري التصدير البسيط...');
      final simple =
          '-y -i "$cutPath" -vf "scale=$outW:$outH:flags=lanczos" -c:v libx264 -preset veryfast -crf 21 -maxrate ${vK}k -bufsize ${vK * 2}k -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart "$out"';
      ok = await SilenceCutter.encode(simple, cutSec, onProgress);
      if (!ok) {
        _checkCancel();
        final simple2 =
            '-y -i "$cutPath" -vf "scale=$outW:$outH" -c:v mpeg4 -b:v ${vK}k -c:a aac -b:a 128k "$out"';
        ok = await SilenceCutter.encode(simple2, cutSec, onProgress);
      }
    }
    _checkCancel();

    final finalPath = (ok && File(out).existsSync()) ? out : cutPath;
    if (finalPath == cutPath) {
      notes.add('فشل التصدير المحسّن؛ هذه نسخة القص فقط.');
    }

    // 6) الغلاف: لقطة من الفيديو (قبل الإضافات) + العنوان
    String? coverPath;
    try {
      onStatus?.call('جاري تجهيز الغلاف...');
      final at = cutSec > 2 ? 1.0 : 0.0;
      final cover = '$dir/cover_$stamp.jpg';
      bool coverOk;
      if (analysis != null && analysis.title.isNotEmpty) {
        final titlePath = await TextRender.png(
          text: analysis.title,
          outPath: '$dir/covtitle_$stamp.png',
          width: outW,
          fontSize: outW * 0.105,
          fill: const Color(0xFFFFD400),
          box: true,
        );
        temps.add(titlePath);
        coverOk = await _run(
            '-y -ss ${_f(at)} -i "$cutPath" -i "$titlePath" -filter_complex "[0:v]scale=$outW:$outH:flags=lanczos,setsar=1[b];[b][1:v]overlay=x=0:y=(main_h-overlay_h)/2[o]" -map "[o]" -frames:v 1 -q:v 2 "$cover"');
      } else {
        coverOk = await _run(
            '-y -ss ${_f(at)} -i "$cutPath" -vf "scale=$outW:$outH:flags=lanczos" -frames:v 1 -q:v 2 "$cover"');
      }
      if (coverOk && File(cover).existsSync()) coverPath = cover;
    } catch (e) {
      notes.add('تعذر تجهيز الغلاف: $e');
    }

    for (final path in temps) {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
    if (finalPath != cutPath) {
      try {
        File(cutPath).deleteSync();
      } catch (_) {}
    }

    final sizeMb = File(finalPath).lengthSync() / (1024 * 1024);
    return EnhanceResult(
      videoPath: finalPath,
      coverPath: coverPath,
      title: analysis?.title ?? '',
      description: analysis?.description ?? '',
      hashtags: analysis?.hashtags ?? <String>[],
      notes: notes,
      sizeMb: sizeMb,
      outW: outW,
      outH: outH,
    );
  }
}
