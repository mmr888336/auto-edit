import 'dart:async';
import 'package:flutter/material.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';

class AdsConfig {
  // تأكد من أن Game ID وPlacement ID مطابقان حرفيًا للوحة Unity Ads.
  static const String gameId = '800393741';
  // اتركه true أثناء التجربة. عطّله فقط بعد إعداد الإعلانات الفعلية في لوحة Unity.
  static const bool testMode = true;
  static const String rewarded = 'BP_Rewarded_Android';
}

class AdsService {
  static Completer<bool>? _init;
  static String lastError = '';

  static void _complete(Completer<bool> completer, bool value) {
    if (!completer.isCompleted) completer.complete(value);
  }

  static Future<bool> _ensureInit() {
    if (_init != null) return _init!.future;
    final completer = Completer<bool>();
    _init = completer;
    try {
      UnityAds.init(
        gameId: AdsConfig.gameId,
        testMode: AdsConfig.testMode,
        onComplete: () => _complete(completer, true),
        onFailed: (error, message) {
          lastError = '$error: $message';
          _complete(completer, false);
        },
      );
    } catch (e) {
      lastError = '$e';
      _complete(completer, false);
    }
    return completer.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () {
        lastError = 'انتهت مهلة الاتصال بخدمة الإعلانات.';
        return false;
      },
    );
  }

  static Future<bool> _load(String placement) async {
    final ready = await _ensureInit();
    if (!ready) {
      _init = null;
      return false;
    }
    final completer = Completer<bool>();
    try {
      UnityAds.load(
        placementId: placement,
        onComplete: (_) => _complete(completer, true),
        onFailed: (_, error, message) {
          lastError = '$error: $message';
          _complete(completer, false);
        },
      );
    } catch (e) {
      lastError = '$e';
      _complete(completer, false);
    }
    return completer.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () {
        lastError = 'لم يصل إعلان خلال المهلة المحددة.';
        return false;
      },
    );
  }

  /// يرجع true فقط عند وصول callback اكتمال الإعلان، وليس عند تخطيه.
  static Future<bool> showRewarded() async {
    lastError = '';
    final loaded = await _load(AdsConfig.rewarded);
    if (!loaded) return false;

    final completer = Completer<bool>();
    try {
      UnityAds.showVideoAd(
        placementId: AdsConfig.rewarded,
        onComplete: (_) => _complete(completer, true),
        onSkipped: (_) => _complete(completer, false),
        onFailed: (_, error, message) {
          lastError = '$error: $message';
          _complete(completer, false);
        },
      );
    } catch (e) {
      lastError = '$e';
      _complete(completer, false);
    }
    return completer.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () {
        lastError = 'لم يصل تأكيد اكتمال الإعلان.';
        return false;
      },
    );
  }
}

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
    if (mounted) {
      setState(() {
        loading = true;
        error = '';
      });
    }
    final completed = await AdsService.showRewarded();
    if (!mounted) return;
    if (completed) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        loading = false;
        error = AdsService.lastError.isEmpty
            ? 'لم يكتمل الإعلان. شاهده حتى النهاية ليتم التصدير.'
            : 'تعذر عرض الإعلان: ${AdsService.lastError}\n\nافتح الإنترنت، وأوقف أي مانع إعلانات أو DNS خاص، ثم اضغط «حاول تاني». لا يتم التصدير إلا بعد اكتمال الإعلان.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إعلان قبل التصدير')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.ondemand_video_rounded, size: 76),
            const SizedBox(height: 24),
            if (loading) ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
              const Text(
                'جاري تحميل إعلان المكافأة...\nالتصدير النهائي يبدأ بعد اكتماله.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, height: 1.6),
              ),
            ] else ...[
              SelectableText(error, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.6)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _run, child: const Text('حاول تاني')),
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('رجوع بدون تصدير')),
            ],
          ],
        ),
      ),
    );
  }
}
