import 'dart:async';
import 'package:flutter/material.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';

class AdsConfig {
  static const String gameId = '800393741'; // Unity Game ID
  // true = إعلانات تجريبية (آمن للتجربة). غيّرها إلى false عند نشر التطبيق.
  static const bool testMode = true;
  static const String rewarded = 'BP_Rewarded_Android';
}

class AdsService {
  static Completer<bool>? _init;
  static String lastError = '';

  static void _done(Completer<bool> c, bool v) {
    if (!c.isCompleted) c.complete(v);
  }

  /// تهيئة Unity عند أول طلب إعلان فقط (مش عند فتح التطبيق)
  static Future<bool> _ensureInit() {
    if (_init != null) return _init!.future;
    final c = Completer<bool>();
    _init = c;
    try {
      UnityAds.init(
        gameId: AdsConfig.gameId,
        testMode: AdsConfig.testMode,
        onComplete: () => _done(c, true),
        onFailed: (error, message) {
          lastError = '$error $message';
          _done(c, false);
        },
      );
    } catch (e) {
      lastError = '$e';
      _done(c, false);
    }
    return c.future.timeout(const Duration(seconds: 20), onTimeout: () {
      lastError = 'انتهت مهلة التهيئة';
      return false;
    });
  }

  static Future<bool> _load(String placement) async {
    final ready = await _ensureInit();
    if (!ready) {
      _init = null; // عشان المحاولة الجاية تعيد التهيئة
      return false;
    }
    final c = Completer<bool>();
    UnityAds.load(
      placementId: placement,
      onComplete: (_) => _done(c, true),
      onFailed: (_, error, message) {
        lastError = '$error $message';
        _done(c, false);
      },
    );
    return c.future.timeout(const Duration(seconds: 20), onTimeout: () {
      lastError = 'انتهت المهلة';
      return false;
    });
  }

  /// يرجع true فقط لو المستخدم شاف الإعلان كامل
  static Future<bool> showRewarded() async {
    lastError = '';
    if (!await _load(AdsConfig.rewarded)) return false;
    final c = Completer<bool>();
    UnityAds.showVideoAd(
      placementId: AdsConfig.rewarded,
      onComplete: (_) => _done(c, true),
      onSkipped: (_) => _done(c, false),
      onFailed: (_, error, message) {
        lastError = '$error $message';
        _done(c, false);
      },
    );
    return c.future;
  }
}

/// شاشة الإعلان: تعرض إعلان Unity المكافأة، ولو اكتمل تدي المستخدم رصيده
class AdPage extends StatefulWidget {
  const AdPage({super.key});
  @override
  State<AdPage> createState() => _AdPageState();
}

class _AdPageState extends State<AdPage> {
  bool loading = true;
  String error = '';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      loading = true;
      error = '';
    });
    final ok = await AdsService.showRewarded();
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        loading = false;
        error = AdsService.lastError.isEmpty
            ? 'ما اكتمل الإعلان. شوفه للآخر عشان تاخد الرصيد.'
            : 'ما قدرنا نعرض الإعلان: ${AdsService.lastError}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إعلان')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.ondemand_video, size: 80),
            const SizedBox(height: 24),
            if (loading) ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
              const Text('جاري تحميل الإعلان...',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
            ] else ...[
              SelectableText(error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _run, child: const Text('حاول تاني')),
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('رجوع')),
            ],
          ],
        ),
      ),
    );
  }
}