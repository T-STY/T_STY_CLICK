import 'package:shared_preferences/shared_preferences.dart';

class HighScoreService {
  static const _prefix = 'hs_';

  static bool _demoMode = false;
  static void setDemoMode(bool v) => _demoMode = v;

  static Future<int> load(String gameId) async {
    final p = await SharedPreferences.getInstance();
    return p.getInt('$_prefix$gameId') ?? 0;
  }

  static Future<bool> submit(String gameId, int score) async {
    if (_demoMode) return false;
    final best = await load(gameId);
    if (score > best) {
      final p = await SharedPreferences.getInstance();
      await p.setInt('$_prefix$gameId', score);
      return true;
    }
    return false;
  }
}
