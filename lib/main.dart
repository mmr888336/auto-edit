import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'ad_page.dart';
import 'enhancer.dart';
import 'settings.dart';
import 'silence_cutter.dart';
import 'usage.dart';

/// للتجربة: true = يتجاهل رصيد الإعلانات. غيّرها إلى false قبل نشر التطبيق.
const bool kSkipQuotaForTesting = true;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AutoEditApp());
}

class AutoEditApp extends StatelessWidget {
  const AutoEditApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مونتاج تلقائي',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? inputPath;
  EnhanceResult? result;
  String? coverPath;
  int remaining = 0;
  String status = 'اختر فيديو للبدء';
  double? progress;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _refreshQuota();
  }

  Future<void> _refreshQuota() async {
    final r = await Usage.remaining();
    if (mounted) setState(() => remaining = r);
  }

  Future<void> _watchAd() async {
    if (!await Usage.canWatchAd()) {
      if (mounted) {
        setState(() => status = 'وصلت الحد اليومي (دقيقتين). جرّب بكرة.');
      }
      return;
    }
    if (!mounted) return;
    final ok = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => const AdPage()));
    if (ok == true) {
      await Usage.addAdQuota();
      await _refreshQuota();
    }
  }

  void _deleteCover() {
    try {
      if (coverPath != null) File(coverPath!).deleteSync();
    } catch (_) {}
    setState(() => coverPath = null);
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.video);
    if (r == null || r.files.single.path == null) return;
    setState(() {
      inputPath = r.files.single.path;
      result = null;
      coverPath = null;
      progress = null;
      status = 'تم اختيار: ${r.files.single.name}';
    });
  }

  Future<void> _run() async {
    if (inputPath == null) return;
    final s = await AppSettings.load();
    final left = kSkipQuotaForTesting ? 3600 : await Usage.remaining();
    if (left <= 0) {
      setState(() =>
          status = 'رصيدك اليوم 0 ثانية. اضغط "شاهد إعلان" لتاخد 60 ثانية.');
      return;
    }
    setState(() {
      busy = true;
      progress = null;
      result = null;
      coverPath = null;
      status = 'بدأنا...';
    });
    try {
      final cut = await SilenceCutter.process(
        inputPath!,
        noiseDb: s.noiseDb,
        minSilence: s.minSilence,
        maxSec: left.toDouble(),
        onStatus: (t) {
          if (mounted) setState(() => status = t);
        },
        onProgress: (p) {
          if (mounted) setState(() => progress = p * 0.3);
        },
      );
      if (!kSkipQuotaForTesting) await Usage.consume(cut.newSec.ceil());

      final enh = await Enhancer.run(
        cutPath: cut.path,
        cutSec: cut.newSec,
        s: s,
        onStatus: (t) {
          if (mounted) setState(() => status = t);
        },
        onProgress: (p) {
          if (mounted) setState(() => progress = 0.3 + p * 0.7);
        },
      );
      await _refreshQuota();
      if (!mounted) return;
      setState(() {
        result = enh;
        coverPath = enh.coverPath;
        progress = 1;
        status =
            'تم ✅\nالمدة: ${cut.originalSec.toStringAsFixed(1)}ث ← ${cut.newSec.toStringAsFixed(1)}ث\nالدقة: ${enh.outW}x${enh.outH}\nالحجم: ${enh.sizeMb.toStringAsFixed(1)} ميجا' +
                (enh.notes.isEmpty ? '' : '\n\nملاحظات:\n- ${enh.notes.join('\n- ')}');
      });
    } catch (e) {
      if (mounted) setState(() => status = 'حصل خطأ ❌\n$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _postText() {
    final r = result!;
    final tags = r.hashtags.map((h) => '#$h').join(' ');
    return '${r.title}\n\n${r.description}\n\n$tags'.trim();
  }

  Future<void> _share() async {
    if (result == null) return;
    await Share.shareXFiles([
      XFile(result!.videoPath),
      if (coverPath != null) XFile(coverPath!),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final r = result;
    return Scaffold(
      appBar: AppBar(
        title: const Text('مونتاج تلقائي'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FilledButton.icon(
            onPressed: busy ? null : _pick,
            icon: const Icon(Icons.video_library),
            label: const Text('اختر فيديو'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: (busy || inputPath == null) ? null : _run,
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('ابدأ المونتاج التلقائي'),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: busy ? null : _watchAd,
            icon: const Icon(Icons.ondemand_video),
            label: const Text('شاهد إعلان (+60 ثانية)'),
          ),
          const SizedBox(height: 8),
          Text(
            kSkipQuotaForTesting
                ? 'وضع التجربة: الرصيد غير محدود'
                : 'رصيدك اليوم: $remaining ثانية',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (busy) LinearProgressIndicator(value: progress),
          const SizedBox(height: 12),
          SelectableText(status, style: const TextStyle(fontSize: 16)),
          if (r != null) ...[
            if (coverPath != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(coverPath!), fit: BoxFit.cover),
                ),
              ),
              TextButton.icon(
                onPressed: _deleteCover,
                icon: const Icon(Icons.delete_outline),
                label: const Text('احذف الغلاف'),
              ),
            ],
            if (r.title.isNotEmpty || r.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              SelectableText(_postText(), style: const TextStyle(fontSize: 15)),
              TextButton.icon(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _postText())),
                icon: const Icon(Icons.copy),
                label: const Text('نسخ العنوان والوصف'),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _share,
              icon: const Icon(Icons.share),
              label: const Text('حفظ / مشاركة الفيديو والغلاف'),
            ),
          ],
        ],
      ),
    );
  }
}