// lib/models/game_record.dart

import '../game_logic/difficulty.dart'; // Import Difficulty

class GameRecord {
  final Difficulty difficulty;
  final int timeSeconds;
  final DateTime date;

  GameRecord({
    required this.difficulty,
    required this.timeSeconds,
    required this.date,
  });

  String get formattedTime =>
      '${(timeSeconds ~/ 60).toString().padLeft(2, '0')}:${(timeSeconds % 60).toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'difficulty': difficulty.toString(),
        'timeSeconds': timeSeconds,
        'date': date.toIso8601String(),
      };

  factory GameRecord.fromJson(Map<String, dynamic> json) => GameRecord(
        difficulty: Difficulty.values.firstWhere(
            (d) => d.toString() == json['difficulty'],
            orElse: () => Difficulty.medium), // Default if parsing fails
        timeSeconds: json['timeSeconds'],
        date: DateTime.parse(json['date']),
      );
}