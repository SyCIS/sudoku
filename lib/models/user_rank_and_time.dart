// lib/models/user_rank_and_time.dart
class UserRankAndTime {
  final int? rank;
  final int? timeSeconds;
  final bool found;

  UserRankAndTime({this.rank, this.timeSeconds, this.found = false});

  String get formattedTime => (timeSeconds != null && found)
      ? '${(timeSeconds! ~/ 60).toString().padLeft(2, '0')}:${(timeSeconds! % 60).toString().padLeft(2, '0')}'
      : "N/A";

  Map<String, dynamic> toJson() => {
        'rank': rank,
        'timeSeconds': timeSeconds,
        'found': found,
      };

  factory UserRankAndTime.fromJson(Map<String, dynamic> json) => UserRankAndTime(
        rank: json['rank'] as int?,
        timeSeconds: json['timeSeconds'] as int?,
        found: json['found'] as bool? ?? false,
      );
}