// lib/widgets/leaderboard_section_widget.dart

import 'package:flutter/material.dart';
import '../models/leaderboard_entry.dart';
import '../game_logic/difficulty.dart';
import '../utils/string_extensions.dart'; // For capitalizeFirst

class LeaderboardSectionWidget extends StatelessWidget {
  final bool isLoadingLeaderboard;
  final List<LeaderboardEntry> leaderboardData;
  final bool showGlobalLeaderboard;
  final Difficulty leaderboardDifficultyFilter;
  final String? username;
  final int? userRank;
  // final String? selectedCountry; // Not strictly needed by this widget if API handles filtering
  final Function(bool isGlobal) onSetLeaderboardType;
  final Function(Difficulty? newDifficulty) onDifficultyFilterChanged;
  final ThemeData theme;

  const LeaderboardSectionWidget({
    super.key,
    required this.isLoadingLeaderboard,
    required this.leaderboardData,
    required this.showGlobalLeaderboard,
    required this.leaderboardDifficultyFilter,
    this.username,
    this.userRank,
    // this.selectedCountry,
    required this.onSetLeaderboardType,
    required this.onDifficultyFilterChanged,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    const double leaderboardRowHeight = 24.0;
    const int numberOfLeaderboardRows = 5;
    const double leaderboardContentHeight = leaderboardRowHeight * numberOfLeaderboardRows;
    final TextStyle yourRankTextStyle = theme.textTheme.bodyMedium?.copyWith(
          fontStyle: FontStyle.italic,
          color: theme.colorScheme.secondary,
          fontSize: 13,
        ) ??
        const TextStyle(fontStyle: FontStyle.italic, fontSize: 13);

    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8.0, 6.0, 8.0, 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text("Leaderboard",
                    style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        minimumSize: const Size(0, 28),
                        backgroundColor: showGlobalLeaderboard
                            ? theme.colorScheme.primaryContainer
                            : null,
                        side: BorderSide(
                            color: showGlobalLeaderboard
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline),
                        textStyle:
                            theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                      ),
                      onPressed: () => onSetLeaderboardType(true),
                      child: Text("Global",
                          style: TextStyle(
                              color: showGlobalLeaderboard
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.primary)),
                    ),
                    const SizedBox(width: 4),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        minimumSize: const Size(0, 28),
                        backgroundColor: !showGlobalLeaderboard
                            ? theme.colorScheme.primaryContainer
                            : null,
                        side: BorderSide(
                            color: !showGlobalLeaderboard
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline),
                        textStyle:
                            theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                      ),
                      onPressed: () => onSetLeaderboardType(false),
                      child: Text("Country",
                          style: TextStyle(
                              color: !showGlobalLeaderboard
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.primary)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text("Difficulty:",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<Difficulty>(
                      isDense: true,
                      value: leaderboardDifficultyFilter,
                      items: Difficulty.values.map((Difficulty d) {
                        return DropdownMenuItem<Difficulty>(
                          value: d,
                          child: Text(
                              d.toString().split('.').last.capitalizeFirst(),
                              style: theme.textTheme.bodySmall),
                        );
                      }).toList(),
                      onChanged: onDifficultyFilterChanged,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(
              height: leaderboardContentHeight,
              child: isLoadingLeaderboard
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2.0))
                  : leaderboardData.isEmpty
                      ? Center(
                          child: Text("No data for this filter.",
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant)))
                      : Column(
                          children:
                              List.generate(numberOfLeaderboardRows, (index) {
                            if (index < leaderboardData.length) {
                              final entry = leaderboardData[index];
                              final isCurrentUser = username != null &&
                                  entry.username.toLowerCase() ==
                                      username!.toLowerCase();
                              return SizedBox(
                                height: leaderboardRowHeight,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 0.5, horizontal: 2.0),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                          width: 22,
                                          child: Text("${entry.rank}.",
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: isCurrentUser
                                                      ? FontWeight.bold
                                                      : FontWeight.normal))),
                                      Text(entry.countryEmoji ?? '🏳️',
                                          style:
                                              const TextStyle(fontSize: 18)),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          entry.username,
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: isCurrentUser
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              color: isCurrentUser
                                                  ? theme.colorScheme.tertiary
                                                  : null),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(entry.formattedTime,
                                          style:
                                              const TextStyle(fontSize: 12)),
                                    ],
                                  ),
                                ),
                              );
                            } else {
                              return SizedBox(
                                height: leaderboardRowHeight,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 1.0, horizontal: 2.0),
                                  child: Row(children: [
                                    SizedBox(
                                        width: 22,
                                        child: Text("${index + 1}.",
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey))),
                                    const SizedBox(width: 5 + 18 + 5),
                                    Expanded(
                                        child: Text("-",
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600]))),
                                    Text("--:--",
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600])),
                                  ]),
                                ),
                              );
                            }
                          }),
                        ),
            ),
            if (username != null &&
                username!.isNotEmpty &&
                !isLoadingLeaderboard)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Center(
                  child: Text(
                    userRank != null
                        ? "Your Rank for ${leaderboardDifficultyFilter.toString().split('.').last.capitalizeFirst()}: $userRank"
                        : "You are not ranked for this filter yet.",
                    style: yourRankTextStyle,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }
}