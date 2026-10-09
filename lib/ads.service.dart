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