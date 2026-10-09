import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'ad_page.dart';
import 'settings.dart';
import 'silence_cutter.dart';
import 'usage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AdsService.init();
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
      await Usage.ad