import 'package:shared_preferences/shared_preferences.dart';

/// Persists per-game best scores locally using SharedPreferences.
/// Key format: "hs_<gameId>"  e.g.  "hs_tetris", "hs_snake"
class HighScoreService {
  static const _prefix = 'hs_';

  /// When true, [submit] is a no-op. Set during hub demo playback.
  static bool _demoMode = false;
  static void setDemoMode(bool v) => _demoMode = v;

  /// Returns the stored best score for [gameId], or 0 if never set.
  static Future<int> load(String gameId) async {
    final p = await SharedPreferences.getInstance();
    return p.getInt('$_prefix$gameId') ?? 0;
  }

  /// Persists [score] if it exceeds the current best.
  /// Returns true if a new record was set.
  /// No-op when demo mode is active.
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
