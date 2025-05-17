// lib/models/leaderboard_entry.dart
import '../game_logic/difficulty.dart';

class LeaderboardEntry {
  final String username;
  final int timeSeconds;
  final int rank;
  final String? countryEmoji; // Keep this for UI
  final String? countryName;  // Store for potential re-serialization if needed
  final Difficulty difficulty;

  LeaderboardEntry({
    required this.username,
    required this.timeSeconds,
    required this.rank,
    this.countryEmoji,
    this.countryName, // Added
    required this.difficulty,
  });

  String get formattedTime =>
      '${(timeSeconds ~/ 60).toString().padLeft(2, '0')}:${(timeSeconds % 60).toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'username': username,
        'timeSeconds': timeSeconds,
        'rank': rank,
        'countryEmoji': countryEmoji,
        'countryName': countryName, // Added
        'difficulty': difficulty.toString(),
      };

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    Difficulty difficulty = Difficulty.medium; // Default
    try {
        difficulty = Difficulty.values.firstWhere((d) => d.toString() == json['difficulty']);
    } catch (_) { /* Use default if parsing fails */ }

    return LeaderboardEntry(
      username: json['username'],
      timeSeconds: json['timeSeconds'],
      rank: json['rank'],
      countryEmoji: json['countryEmoji'],
      countryName: json['countryName'], // Added
      difficulty: difficulty,
    );
  }
}