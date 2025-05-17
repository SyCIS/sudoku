// lib/utils/cache_service.dart (Example)
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/leaderboard_entry.dart';
import '../models/user_rank_and_time.dart';
import '../game_logic/difficulty.dart';

class CacheService {
  static const String _leaderboardPrefix = 'leaderboard_cache_';
  static const String _userRanksPrefix = 'user_all_ranks_cache_';
  static const String _cacheTimestampSuffix = '_timestamp';

  // --- Leaderboard Cache ---
  static String _getLeaderboardCacheKey(Difficulty difficulty, String type, String? country) {
    String key = "$_leaderboardPrefix${difficulty.toString()}_$type";
    if (type == 'country' && country != null && country.isNotEmpty) {
      key += "_${country.replaceAll(' ', '_')}"; // Sanitize country name for key
    }
    return key;
  }

  static Future<void> saveLeaderboardToCache(
      List<LeaderboardEntry> leaderboard, Difficulty difficulty, String type, String? country) async {
    final prefs = await SharedPreferences.getInstance();
    String key = _getLeaderboardCacheKey(difficulty, type, country);
    List<String> jsonList = leaderboard.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(key, jsonList);
    await prefs.setInt("$key$_cacheTimestampSuffix", DateTime.now().millisecondsSinceEpoch);
  }

  static Future<List<LeaderboardEntry>?> getLeaderboardFromCache(
      Difficulty difficulty, String type, String? country, {Duration maxAge = const Duration(hours: 1)}) async {
    final prefs = await SharedPreferences.getInstance();
    String key = _getLeaderboardCacheKey(difficulty, type, country);
    
    int? timestamp = prefs.getInt("$key$_cacheTimestampSuffix");
    if (timestamp == null || DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(timestamp)) > maxAge) {
        // Cache is old or doesn't exist
        await prefs.remove(key); // Clear old data
        await prefs.remove("$key$_cacheTimestampSuffix");
        return null;
    }

    List<String>? jsonList = prefs.getStringList(key);
    if (jsonList == null) return null;
    try {
      return jsonList.map((s) => LeaderboardEntry.fromJson(jsonDecode(s) as Map<String, dynamic>)).toList();
    } catch (e) {
      // print("Error decoding leaderboard from cache: $e");
      await prefs.remove(key); // Clear corrupted data
      await prefs.remove("$key$_cacheTimestampSuffix");
      return null;
    }
  }

  // --- User Ranks Cache ---
  static String _getUserRanksCacheKey(String username) {
    return "$_userRanksPrefix${username.replaceAll(' ', '_')}";
  }

  static Future<void> saveUserRanksToCache(Map<Difficulty, UserRankAndTime> ranks, String username) async {
    final prefs = await SharedPreferences.getInstance();
    String key = _getUserRanksCacheKey(username);
    Map<String, String> jsonMap = ranks.map((k, v) => MapEntry(k.toString(), jsonEncode(v.toJson())));
    // SharedPreferences doesn't directly support Map<String, String>, so serialize the whole map.
    String serializedMap = jsonEncode(jsonMap);
    await prefs.setString(key, serializedMap);
    await prefs.setInt("$key$_cacheTimestampSuffix", DateTime.now().millisecondsSinceEpoch);
  }

  static Future<Map<Difficulty, UserRankAndTime>?> getUserRanksFromCache(String username, {Duration maxAge = const Duration(hours: 1)}) async {
    final prefs = await SharedPreferences.getInstance();
    String key = _getUserRanksCacheKey(username);

    int? timestamp = prefs.getInt("$key$_cacheTimestampSuffix");
     if (timestamp == null || DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(timestamp)) > maxAge) {
        await prefs.remove(key);
        await prefs.remove("$key$_cacheTimestampSuffix");
        return null;
    }

    String? serializedMap = prefs.getString(key);
    if (serializedMap == null) return null;
    try {
      Map<String, dynamic> decodedJsonMap = jsonDecode(serializedMap) as Map<String, dynamic>;
      Map<Difficulty, UserRankAndTime> ranks = {};
      decodedJsonMap.forEach((k, v) {
        Difficulty? diffKey;
        try {
            diffKey = Difficulty.values.firstWhere((d) => d.toString() == k);
        } catch(_){}
        
        if (diffKey != null) {
          ranks[diffKey] = UserRankAndTime.fromJson(jsonDecode(v as String) as Map<String, dynamic>);
        }
      });
      return ranks;
    } catch (e) {
      // print("Error decoding user ranks from cache: $e");
      await prefs.remove(key);
      await prefs.remove("$key$_cacheTimestampSuffix");
      return null;
    }
  }
}