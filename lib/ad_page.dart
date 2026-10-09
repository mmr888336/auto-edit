import 'dart:async';
import 'package:flutter/material.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';

class AdsConfig {
  static const String gameId = '800393741'; // لو الإعلانات ما ظهرت، تأكد من الـ Game ID في Unity
  static const bool testMode = true; // خليه false قبل النشر النهائي
  static const String rewarded = 'BP_Rewarded_Android';
  static const String interstitial = 'BP_Interstitial_Android';
  static const String banner = 'BP_Banner_Android';
}

class AdsService {
  static final Completer<bool> _init = Completer<bool>();
  static String lastError = '';

  static void _done(Completer<bool> c, bool v) {
    if (!c.isCompleted) c.complete(v);
  }

  static void init() {
    UnityAds.init(
      gameId: AdsConfig.gameId,
      testMode: AdsConfig.testMode,
      onComplete: () => _done(_init, true),
      onFailed: (error, message) {
        lastError = '$error $message';
        _done(_init, false);
      },
    );
  }

  static Future<bool> _load(String placement) async {
    if (!await _init.future) return false;
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

  static Future<void> showInterstitial() async {
    if (!await _load(AdsConfig.interstitial)) return;
    UnityAds.showVideoAd(
      placementId: AdsConfig.interstitial,
      onFailed: (_, __, ___) {},
    );
  }
}

class BannerSlot extends StatelessWidget {
  const BannerSlot({super.key});
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: UnityBannerAd(
        placementId: AdsConfig.banner,
        size: BannerSize.standard,
      ),
    );
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
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
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