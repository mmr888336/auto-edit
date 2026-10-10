import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'ad_page.dart';
import 'enhancer.dart';
import 'settings.dart';
import 'silence_cutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AutoEditApp());
}

class AutoEditApp extends StatelessWidget {
  const AutoEditApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF7C5CFC);
    return MaterialApp(
      title: 'Wad Alreda Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: seed,
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0D0D14),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF11111B)),
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const WelcomePage(),
    );
  }
}

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF211847), Color(0xFF10101A), Color(0xFF08080D)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B70FF).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: const Color(0xFF9A85FF), width: 1.3),
                  ),
                  child: const Icon(Icons.movie_creation_outlined, size: 55, color: Color(0xFFB7A8FF)),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Wad Alreda Studio',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 0.2),
                ),
                const SizedBox(height: 10),
                const Text(
                  'صلِ على النبي 🌹 ﷺ',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Color(0xFFE6D9FF)),
                ),
                const SizedBox(height: 38),
                const Text(
                  'مونتاج ذكي، صوت أوضح، وفيديو جاهز للنشر',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.white70, height: 1.7),
                ),
                const SizedBox(height: 34),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const HomePage()),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('ابدأ الآن', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PipelineOut {
  final CutResult cut;
  final EnhanceResult enhanced;
  _PipelineOut(this.cut, this.enhanced);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? inputPath;
  String? inputName;
  EnhanceResult? result;
  String? coverPath;
  String status = 'اختر فيديو للبدء';
  double? progress;
  bool busy = false;
  bool saving = false;

  Future<void> _pick() async {
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.video);
      if (picked == null || picked.files.isEmpty || picked.files.single.path == null) return;
      if (!mounted) return;
      setState(() {
        inputPath = picked.files.single.path;
        inputName = picked.files.single.name;
        result = null;
        coverPath = null;
        progress = null;
        status = 'تم اختيار: ${picked.files.single.name}\nاضغط «ابدأ المونتاج» للمتابعة.';
      });
    } catch (e) {
      if (mounted) setState(() => status = 'تعذر اختيار الفيديو: $e');
    }
  }

  Future<_PipelineOut> _pipeline(String source, AppSettings settings) async {
    CutResult? cut;
    try {
      cut = await SilenceCutter.process(
        source,
        noiseDb: settings.noiseDb,
        minSilence: settings.minSilence,
        onStatus: (message) {
          if (mounted) setState(() => status = message);
        },
        onProgress: (value) {
          if (mounted) setState(() => progress = value * 0.15);
        },
      );
      final enhanced = await Enhancer.run(
        cutPath: cut.path,
        cutSec: cut.newSec,
        s: settings,
        cutTimes: cut.segStarts,
        onStatus: (message) {
          if (mounted) setState(() => status = message);
        },
        onProgress: (value) {
          if (mounted) setState(() => progress = 0.15 + value * 0.85);
        },
      );
      return _PipelineOut(cut, enhanced);
    } catch (_) {
      if (cut != null) {
        try {
          File(cut.path).deleteSync();
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> _run() async {
    final source = inputPath;
    if (source == null || busy) return;
    final settings = await AppSettings.load();
    JobControl.reset();

    setState(() {
      busy = true;
      progress = 0;
      result = null;
      coverPath = null;
      status = 'بدأ المونتاج في الخلفية...\nسيظهر إعلان مكافأة، ولا يكتمل التصدير إلا بعد انتهائه.';
    });

    // نبدأ القص والتصدير فوراً، وفي نفس الوقت نعرض الإعلان.
    final pipeline = _pipeline(source, settings);
    pipeline.ignore();

    try {
      final adCompleted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const AdPage()),
      );
      if (!mounted) return;

      if (adCompleted != true) {
        await JobControl.cancel();
        try {
          await pipeline;
        } catch (_) {}
        if (!mounted) return;
        setState(() {
          progress = null;
          status =
              'تم إيقاف التصدير لأن الإعلان لم يكتمل.\nافتح الإنترنت، وأوقف أي مانع إعلانات أو DNS خاص، ثم حاول مجددًا.';
        });
        return;
      }

      setState(() => status = 'اكتمل الإعلان ✅ جاري إنهاء التصدير...');
      final out = await pipeline;
      if (!mounted) return;
      final cut = out.cut;
      final enhanced = out.enhanced;
      setState(() {
        result = enhanced;
        coverPath = enhanced.coverPath;
        progress = 1;
        status = 'تم تجهيز الفيديو ✅\nالمدة: ${cut.originalSec.toStringAsFixed(1)}ث ← ${cut.newSec.toStringAsFixed(1)}ث\nالدقة: ${enhanced.outW}×${enhanced.outH}\nالحجم: ${enhanced.sizeMb.toStringAsFixed(1)} ميجا' +
            (enhanced.notes.isEmpty ? '' : '\n\nملاحظات:\n- ${enhanced.notes.join('\n- ')}');
      });
    } catch (e) {
      if (mounted) setState(() => status = 'حصل خطأ أثناء المونتاج ❌\n$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _postText() {
    final current = result!;
    final tags = current.hashtags.map((tag) => '#$tag').join(' ');
    return '${current.title}\n\n${current.description}\n\n$tags'.trim();
  }

  Future<void> _saveToGallery() async {
    final current = result;
    if (current == null || saving) return;
    setState(() {
      saving = true;
      status = 'جاري حفظ الفيديو في معرض الجوال...';
    });
    try {
      await Gal.requestAccess(toAlbum: true);
      final allowed = await Gal.hasAccess(toAlbum: true);
      if (!allowed) {
        throw Exception('لم يتم منح صلاحية الوصول إلى المعرض. اسمح بها من إعدادات الجوال ثم حاول مجددًا.');
      }
      await Gal.putVideo(current.videoPath, album: 'Wad Alreda Studio');
      var message = 'تم حفظ الفيديو في المعرض داخل ألبوم Wad Alreda Studio ✅';
      if (coverPath != null && await File(coverPath!).exists()) {
        try {
          await Gal.putImage(coverPath!, album: 'Wad Alreda Studio');
          message += '\nوتم حفظ الغلاف أيضًا.';
        } catch (_) {
          message += '\nتعذر حفظ الغلاف، لكن الفيديو محفوظ.';
        }
      }
      if (mounted) setState(() => status = message);
    } catch (e) {
      if (mounted) setState(() => status = 'تعذر حفظ الفيديو: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _share() async {
    final current = result;
    if (current == null) return;
    try {
      await Share.shareXFiles([
        XFile(current.videoPath),
        if (coverPath != null && await File(coverPath!).exists()) XFile(coverPath!),
      ]);
    } catch (e) {
      if (mounted) setState(() => status = 'تعذرت المشاركة: $e');
    }
  }

  Future<void> _copyPostText() async {
    if (result == null) return;
    await Clipboard.setData(ClipboardData(text: _postText()));
    if (mounted) setState(() => status = 'تم نسخ العنوان والوصف والهاشتاقات.');
  }

  @override
  Widget build(BuildContext context) {
    final current = result;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wad Alreda Studio', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'الإعدادات',
            icon: const Icon(Icons.tune_rounded),
            onPressed: busy ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(colors: [Color(0xFF2A2150), Color(0xFF171727)]),
              border: Border.all(color: const Color(0xFF55438C).withValues(alpha: 0.65)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('صلِ على النبي 🌹 ﷺ', style: TextStyle(color: Color(0xFFE8DFFF), fontSize: 12)),
                SizedBox(height: 8),
                Text('حوّل فيديوك إلى نسخة أنظف وجاهزة للنشر', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, height: 1.45)),
                SizedBox(height: 5),
                Text('قص السكتات • تحسين الصوت • كابشن • B-roll • غلاف', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.6)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: busy ? null : _pick,
            icon: const Icon(Icons.video_library_outlined),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(inputName == null ? 'اختر فيديو' : 'تغيير الفيديو: $inputName', maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: (busy || inputPath == null) ? null : _run,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Text(busy ? 'جاري تجهيز الفيديو...' : 'ابدأ المونتاج والتصدير'),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'أثناء التصدير سيظهر إعلان مكافأة ولا يكتمل التصدير إلا بعد انتهائه. يلزم اتصال بالإنترنت، وأوقف أي مانع إعلانات.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.white60, height: 1.5),
          ),
          const SizedBox(height: 20),
          if (busy) ...[
            LinearProgressIndicator(value: progress, minHeight: 5, borderRadius: BorderRadius.circular(10)),
            const SizedBox(height: 12),
          ],
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFF171721), borderRadius: BorderRadius.circular(14)),
            child: SelectableText(status, style: const TextStyle(fontSize: 14, height: 1.65)),
          ),
          if (current != null) ...[
            if (coverPath != null && File(coverPath!).existsSync()) ...[
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(File(coverPath!), height: 230, fit: BoxFit.contain),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: saving ? null : _saveToGallery,
              icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_rounded),
              label: Text(saving ? 'جاري الحفظ...' : 'حفظ الفيديو في الجوال'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _share,
              icon: const Icon(Icons.share_outlined),
              label: const Text('مشاركة الفيديو والغلاف'),
            ),
            if (current.title.isNotEmpty || current.description.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('وصف المنشور', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SelectableText(_postText(), style: const TextStyle(fontSize: 14, height: 1.6)),
              TextButton.icon(onPressed: _copyPostText, icon: const Icon(Icons.copy_all), label: const Text('نسخ العنوان والوصف')),
            ],
          ],
        ],
      ),
    );
  }
}
