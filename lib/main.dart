import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'ad_page.dart';
import 'settings.dart';
import 'silence_cutter.dart';
import 'usage.dart';

void main() => runApp(const AutoEditApp());

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
  String? outputPath;
  String? thumbPath;
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
      if (mounted) setState(() => status = 'وصلت الحد اليومي (دقيقتين). جرّب بكرة.');
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

  void _deleteThumb() {
    try {
      if (thumbPath != null) File(thumbPath!).deleteSync();
    } catch (_) {}
    setState(() => thumbPath = null);
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.video);
    if (r == null || r.files.single.path == null) return;
    setState(() {
      inputPath = r.files.single.path;
      outputPath = null;
      thumbPath = null;
      progress = null;
      status = 'تم اختيار: ${r.files.single.name}';
    });
  }

  Future<void> _run() async {
    if (inputPath == null) return;
    final s = await AppSettings.load();
    final left = await Usage.remaining();
    if (left <= 0) {
      setState(() => status = 'رصيدك اليوم 0 ثانية. اضغط "شاهد إعلان" لتاخد 60 ثانية.');
      return;
    }
    setState(() {
      busy = true;
      progress = null;
      outputPath = null;
      thumbPath = null;
      status = 'بدأنا...';
    });
    try {
      final res = await SilenceCutter.process(
        inputPath!,
        noiseDb: s.noiseDb,
        minSilence: s.minSilence,
        maxSec: left.toDouble(),
        onStatus: (t) {
          if (mounted) setState(() => status = t);
        },
        onProgress: (p) {
          if (mounted) setState(() => progress = p);
        },
      );
      final mb = File(res.path).lengthSync() / (1024 * 1024);
      await Usage.consume(res.newSec.ceil());
      final thumb = await SilenceCutter.makeThumb(res.path, res.newSec);
      await _refreshQuota();
      if (!mounted) return;
      setState(() {
        outputPath = res.path;
        thumbPath = thumb;
        progress = 1;
        status =
            'تم ✅\nالمدة: ${res.originalSec.toStringAsFixed(1)}ث ← ${res.newSec.toStringAsFixed(1)}ث\nالحجم: ${mb.toStringAsFixed(1)} ميجا';
      });
    } catch (e) {
      if (mounted) setState(() => status = 'حصل خطأ ❌\n$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _share() async {
    if (outputPath == null) return;
    await Share.shareXFiles([
      XFile(outputPath!),
      if (thumbPath != null) XFile(thumbPath!),
    ]);
  }

  @override
  Widget build(BuildContext context) {
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
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : _pick,
              icon: const Icon(Icons.video_library),
              label: const Text('اختر فيديو'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: (busy || inputPath == null) ? null : _run,
              icon: const Icon(Icons.content_cut),
              label: const Text('قص السكتات'),
            ),
            const SizedBox(height: 20),
            if (busy) LinearProgressIndicator(value: progress),
            const SizedBox(height: 12),
            SelectableText(status, style: const TextStyle(fontSize: 16)),
            if (thumbPath != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(thumbPath!), fit: BoxFit.cover),
                ),
              ),
              TextButton.icon(
                onPressed: _deleteThumb,
                icon: const Icon(Icons.delete_outline),
                label: const Text('احذف الغلاف'),
              ),
            ],
            const Spacer(),
            if (outputPath != null)
              FilledButton.tonalIcon(
                onPressed: _share,
                icon: const Icon(Icons.share),
                label: const Text('حفظ / مشاركة الفيديو'),
              ),
          ],
        ),
      ),
    );
  }
}