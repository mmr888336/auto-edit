import 'package:shared_preferences/shared_preferences.dart';

/// رصيد المستخدم اليومي (بالثواني). كل إعلان = 60 ثانية، والحد الأقصى 120 ثانية في اليوم.
class Usage {
  static const int adQuotaSec = 60;
  static const int maxDailySec = 120;

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  static Future<SharedPreferences> _prefs() async {
    final p = await SharedPreferences.getInstance();
    if (p.getString('usageDay') != _today()) {
      await p.setString('usageDay', _today());
      await p.setInt('grantedSec', 0);
      await p.setInt('usedSec', 0);
    }
    return p;
  }

  static Future<int> remaining() async {
    final p = await _prefs();
    final left = (p.getInt('grantedSec') ?? 0) - (p.getInt('usedSec') ?? 0);
    return left < 0 ? 0 : left;
  }

  static Future<bool> canWatchAd() async {
    final p = await _prefs();
    return (p.getInt('grantedSec') ?? 0) < maxDailySec;
  }

  static Future<void> addAdQuota() async {
    final p = await _prefs();
    var g = (p.getInt('grantedSec') ?? 0) + adQuotaSec;
    if (g > maxDailySec) g = maxDailySec;
    await p.setInt('grantedSec', g);
  }

  static Future<void> consume(int sec) async {
    final p = await _prefs();
    await p.setInt('usedSec', (p.getInt('usedSec') ?? 0) + sec);
  }
}