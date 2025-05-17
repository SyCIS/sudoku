// lib/services/api_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

// googleapis for updateLeaderboardScore (direct sheet write)
import 'package:googleapis/sheets/v4.dart' as gsheets;
import 'package:googleapis_auth/auth_io.dart' as auth_io;

import '../constants/app_constants.dart';
import '../models/leaderboard_entry.dart';
import '../models/user_rank_and_time.dart';
import '../game_logic/difficulty.dart';
import '../country_data.dart'; // For countryFlags map
import '../utils/logger.dart';
import '../utils/string_extensions.dart';

class ApiService {
  static const String _webAppUrl = "https://script.google.com/macros/s/AKfycbydlVbIFteo29L0Y83x9jPzEHLR84XYrB9mJO8xJUvkSVrHDEaN1L1HKkOFyMi2_DdKaw/exec";

  // ... (fetchLeaderboard method - keep as is from the version where flags were fixed) ...
  static Future<List<LeaderboardEntry>> fetchLeaderboard(
      String type, Difficulty difficultyFilter, String? selectedUserCountryName, String? currentUsername) async {
    logDebug("ApiService (Web App): fetchLeaderboard for Diff: $difficultyFilter, Type: $type, Country: $selectedUserCountryName");
    String difficultyStringForScript = difficultyFilter.toString().split('.').last.capitalizeFirst(); 
    final queryParameters = {
      'action': 'getLeaderboard',
      'difficulty': difficultyStringForScript,
      'type': type,
      if (type == 'country' && selectedUserCountryName != null && selectedUserCountryName.toLowerCase() != 'other') 
        'country': selectedUserCountryName,
    };
    final Uri uri = Uri.parse(_webAppUrl).replace(queryParameters: queryParameters);
    logDebug("ApiService (Web App): Calling URL for leaderboard: $uri");
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      logDebug("ApiService (Web App) fetchLeaderboard: Response Status: ${response.statusCode}");
      if (response.statusCode == 200) {
        final decodedResponse = jsonDecode(response.body) as Map<String, dynamic>;
        if (decodedResponse['success'] == true && decodedResponse['data'] is List) {
          final List<dynamic> leaderboardJson = decodedResponse['data'] as List<dynamic>;
          List<LeaderboardEntry> entries = leaderboardJson.map((itemJson) {
            final item = itemJson as Map<String, dynamic>;
            String responseDifficultyString = item['difficulty']?.toString() ?? difficultyStringForScript;
            Difficulty entryDifficulty = difficultyFilter; 
             try {
                entryDifficulty = Difficulty.values.firstWhere((d) => d.toString().split('.').last.capitalizeFirst() == responseDifficultyString);
            } catch (e) {
                logDebug("ApiService (Web App) fetchLeaderboard: Could not map response difficulty string '$responseDifficultyString' to enum. Using filter default. Error: $e");
            }
            String countryNameFromServer = item['countryName']?.toString() ?? 'Other';
            // logDebug("ApiService (Web App) fetchLeaderboard: Entry: User='${item['username']}', CountryName='$countryNameFromServer', MappedEmoji='${countryFlags[countryNameFromServer] ?? '🏳️'}'");
            return LeaderboardEntry(
              username: item['username']?.toString() ?? 'N/A',
              timeSeconds: (item['timeSeconds'] as num?)?.toInt() ?? 999999,
              rank: (item['rank'] as num?)?.toInt() ?? 0,
              countryName: countryNameFromServer,
              countryEmoji: countryFlags[countryNameFromServer] ?? '🏳️',
              difficulty: entryDifficulty,
            );
          }).toList();
          logDebug("ApiService (Web App) fetchLeaderboard: Parsed ${entries.length} entries.");
          return entries;
        } else {
          String errorMsg = decodedResponse['error']?.toString() ?? "Unknown error from getLeaderboard script.";
          logDebug("ApiService (Web App) fetchLeaderboard: API error: $errorMsg");
          throw Exception(errorMsg);
        }
      } else {
        logDebug("ApiService (Web App) fetchLeaderboard: HTTP Error ${response.statusCode}. Body: ${response.body.length > 200 ? response.body.substring(0,200) : response.body}");
        throw Exception("Failed to load leaderboard. HTTP Status: ${response.statusCode}");
      }
    } catch (e, s) {
      logDebug("ApiService (Web App) fetchLeaderboard: Exception: $e\n$s");
      throw Exception("Failed to connect or parse leaderboard: $e");
    }
  }

  // ... (fetchUserSpecificRanks method - keep as is from the version where mapping was fixed) ...
  static Future<Map<Difficulty, UserRankAndTime>> fetchUserSpecificRanks(String username) async {
    logDebug("ApiService (Web App): fetchUserSpecificRanks for $username called");
    if (username.isEmpty) {
      logDebug("ApiService (Web App): Username is empty, returning empty map.");
      return {};
    }
    final queryParameters = { 'action': 'getUserRanks', 'username': username, };
    final Uri uri = Uri.parse(_webAppUrl).replace(queryParameters: queryParameters);
    logDebug("ApiService (Web App): Calling URL for user ranks: $uri");
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 30));
      logDebug("ApiService (Web App) fetchUserSpecificRanks: Response Status Code: ${response.statusCode}");
      if (response.statusCode == 200) {
        final decodedResponse = jsonDecode(response.body) as Map<String, dynamic>;
        if (decodedResponse['success'] == true && decodedResponse['data'] is Map) {
          final Map<String, dynamic> ranksData = decodedResponse['data'] as Map<String, dynamic>;
          Map<Difficulty, UserRankAndTime> userRanks = {};
          ranksData.forEach((keyFromJson, value) { 
            logDebug("ApiService (Web App) fetchUserSpecificRanks: Processing JSON key: '$keyFromJson'");
            Difficulty? difficultyEnum;
            String lowerKeyFromJson = keyFromJson.toLowerCase();
            for (Difficulty dVal in Difficulty.values) {
                String enumValueString = dVal.toString().split('.').last.toLowerCase();
                if (enumValueString == lowerKeyFromJson) {
                    difficultyEnum = dVal;
                    logDebug("ApiService (Web App) fetchUserSpecificRanks: Mapped JSON key '$keyFromJson' to Difficulty '$difficultyEnum'");
                    break; 
                }
            }
            if (difficultyEnum == null) {
                 logDebug("ApiService (Web App) fetchUserSpecificRanks: FINAL: Could not map JSON key '$keyFromJson' to any Difficulty enum. This key will be SKIPPED.");
            }
            if (difficultyEnum != null && value is Map) {
              final rankInfo = value as Map<String, dynamic>;
              userRanks[difficultyEnum] = UserRankAndTime(
                rank: rankInfo['rank'] as int?,
                timeSeconds: rankInfo['timeSeconds'] as int?,
                found: rankInfo['found'] as bool? ?? false,
              );
            } else {
               if (difficultyEnum == null && value is Map) { 
                    logDebug("ApiService (Web App) fetchUserSpecificRanks: Skipped entry for unmappable key '$keyFromJson' even though value was a Map.");
               } else if (difficultyEnum != null && !(value is Map)) { 
                    logDebug("ApiService (Web App) fetchUserSpecificRanks: Skipped entry for key '$keyFromJson' (mapped to $difficultyEnum) because value was not a Map. Value: $value");
               }
            }
          });
          logDebug("ApiService (Web App) fetchUserSpecificRanks: Parsed ${userRanks.length} rank entries.");
           userRanks.forEach((key, value) { 
             logDebug("ApiService (Web App): Final Parsed Rank for ${key.toString().split('.').last}: Found=${value.found}, Rank=${value.rank}, Time=${value.timeSeconds}");
          });
          return userRanks;
        } else {
          String errorMessage = decodedResponse['error']?.toString() ?? 'Unknown API error from getUserRanks script (success flag false or data not a map).';
          logDebug("ApiService (Web App) fetchUserSpecificRanks: API call not successful: $errorMessage. Full response: $decodedResponse");
          throw Exception("Failed to fetch ranks: $errorMessage");
        }
      } else {
        logDebug("ApiService (Web App) fetchUserSpecificRanks: HTTP Error ${response.statusCode}. Body: ${response.body.length > 200 ? response.body.substring(0,200) : response.body}");
        throw Exception("Failed to fetch user ranks. HTTP Status: ${response.statusCode}");
      }
    } catch (e, s) {
      logDebug("ApiService (Web App) fetchUserSpecificRanks: Exception: $e\n$s");
      throw Exception("Failed to connect or parse user ranks: $e");
    }
  }

  // +++ ADD THIS METHOD +++
  static Future<Map<String, dynamic>> checkUsernameAvailability(String username) async {
    logDebug("ApiService (Web App): checkUsernameAvailability for '$username'");
    if (username.isEmpty) {
      return {'available': false, 'message': 'Username cannot be empty.'};
    }

    final queryParameters = {
      'action': 'checkUsername', // Ensure your Apps Script handles this action
      'username': username,
    };
    final Uri uri = Uri.parse(_webAppUrl).replace(queryParameters: queryParameters);
    logDebug("ApiService (Web App): Calling URL for username check: $uri");

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      logDebug("ApiService (Web App) checkUsername: Response Status: ${response.statusCode}");

      if (response.statusCode == 200) {
        final decodedResponse = jsonDecode(response.body) as Map<String, dynamic>;
        logDebug("ApiService (Web App) checkUsername: Decoded response: $decodedResponse");
        // Expecting script to return something like: {'available': true/false, 'message': '...'}
        // Or if script has a 'success' wrapper: {'success': true, 'data': {'available': true/false, 'message': '...'}}
        // Adjust based on your script's EXACT response structure for checkUsername.
        // The Apps Script example for checkUsernameAvailability directly returned the availability object.
        if (decodedResponse.containsKey('available')) {
            return {
                'available': decodedResponse['available'] as bool? ?? false,
                'message': decodedResponse['message']?.toString() ?? "Could not determine availability."
            };
        } else if (decodedResponse['success'] == true && decodedResponse['data'] is Map) {
            // If your script wraps it with success/data like other methods
            final data = decodedResponse['data'] as Map<String, dynamic>;
             return {
                'available': data['available'] as bool? ?? false,
                'message': data['message']?.toString() ?? "Could not determine availability."
            };
        } else {
             logDebug("ApiService (Web App) checkUsername: Unexpected response format: $decodedResponse");
             return {'available': false, 'message': 'Unexpected server response.'};
        }
      } else {
        logDebug("ApiService (Web App) checkUsername: HTTP Error ${response.statusCode}. Body: ${response.body}");
        return {'available': false, 'message': 'Error connecting to server to check username.'};
      }
    } catch (e, s) {
      logDebug("ApiService (Web App) checkUsername: Exception: $e\n$s");
      return {'available': false, 'message': 'Could not check username. Please try again.'};
    }
  }
  // +++ END OF ADDED METHOD +++


  // ... (_getAuthenticatedSheetsClient and updateLeaderboardScore methods - keep as is) ...
  static Future<auth_io.AuthClient?> _getAuthenticatedSheetsClient() async {
    logDebug("ApiService: Attempting to get authenticated Sheets client for write.");
    try {
      final jsonString = await rootBundle.loadString(SERVICE_ACCOUNT_KEY_PATH);
      final credentialsMap = jsonDecode(jsonString) as Map<String, dynamic>;
      final credentials = auth_io.ServiceAccountCredentials.fromJson(credentialsMap);
      final scopes = [gsheets.SheetsApi.spreadsheetsScope];
      final client = await auth_io.clientViaServiceAccount(credentials, scopes);
      logDebug("ApiService: Authenticated Sheets client for write obtained.");
      return client;
    } catch (e, s) {
      logDebug("ApiService: ERROR getting authenticated Sheets client for write: $e\n$s");
      rethrow;
    }
  }

  static Future<bool> updateLeaderboardScore({
    required Difficulty difficulty,
    required String username,
    required int timeSeconds,
    String? selectedUserCountryName,
  }) async {
    logDebug("ApiService (Direct Sheets): updateLeaderboardScore for $username, Diff: $difficulty, Time: $timeSeconds");
    if (username.isEmpty) return false;
    auth_io.AuthClient? client;
    try {
      client = await _getAuthenticatedSheetsClient();
      if (client == null) throw Exception("Failed to authenticate for leaderboard update.");
      var sheetsApi = gsheets.SheetsApi(client);
      String sheetName = difficulty.toString().split('.').last.capitalizeFirst();
      String readRange = "$sheetName!B2:D51"; 
      final currentScoresResponse = await sheetsApi.spreadsheets.values.get(SPREADSHEET_ID, readRange, valueRenderOption: 'UNFORMATTED_VALUE');
      List<LeaderboardEntry> currentEntries = [];
      if (currentScoresResponse.values != null) {
        for (int i = 0; i < currentScoresResponse.values!.length; i++) {
            final List<dynamic> row = currentScoresResponse.values![i] as List<dynamic>;
             if (row.length >= 3 && row[0].toString().isNotEmpty) { 
                String countryNameFromSheet = row[1].toString().trim();
                currentEntries.add(LeaderboardEntry(
                    rank: 0, 
                    username: row[0].toString().trim(),
                    countryName: countryNameFromSheet, // Store name
                    countryEmoji: countryFlags[countryNameFromSheet], 
                    timeSeconds: (row[2] is int) ? row[2] : (int.tryParse(row[2].toString().trim()) ?? 999999),
                    difficulty: difficulty,
                ));
            }
        }
      }
      String countryNameToWriteForNewEntry = selectedUserCountryName ?? 'Other';
      LeaderboardEntry newEntry = LeaderboardEntry(
        username: username,
        timeSeconds: timeSeconds,
        rank: 0, 
        countryName: countryNameToWriteForNewEntry, // Store name
        countryEmoji: countryFlags[countryNameToWriteForNewEntry],
        difficulty: difficulty,
      );
      int existingUserIndex = currentEntries.indexWhere((e) => e.username.toLowerCase() == username.toLowerCase());
      if (existingUserIndex != -1) { 
        if (currentEntries[existingUserIndex].timeSeconds > newEntry.timeSeconds) {
          currentEntries.removeAt(existingUserIndex); 
          currentEntries.add(newEntry);
        } else {
          logDebug("ApiService (Direct Sheets): User $username already on leaderboard for $difficulty with better/equal time. No update to sheet.");
          return true; 
        }
      } else { 
        currentEntries.add(newEntry);
      }
      currentEntries.sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));
      List<LeaderboardEntry> top5ToWrite = currentEntries.take(5).toList(); 
      List<List<Object?>> valuesToWrite = [];
      for (int i = 0; i < 5; i++) { 
          if (i < top5ToWrite.length) {
              LeaderboardEntry entry = top5ToWrite[i];
              // Use the countryName stored in the LeaderboardEntry object
              String countryNameForSheet = entry.countryName ?? 'Other'; 
              valuesToWrite.add([ entry.username, countryNameForSheet, entry.timeSeconds, ]);
          } else {
              valuesToWrite.add(['', '', null]); 
          }
      }
      String writeRange = "$sheetName!B2:D6"; 
      var valueRange = gsheets.ValueRange.fromJson({ "values": valuesToWrite });
      await sheetsApi.spreadsheets.values.update(valueRange, SPREADSHEET_ID, writeRange, valueInputOption: 'USER_ENTERED');
      logDebug("ApiService (Direct Sheets): Successfully updated leaderboard for $difficulty.");
      return true;
    } catch (e, s) {
      logDebug("ApiService (Direct Sheets): ERROR updating leaderboard score: $e\n$s");
      return false;
    } finally {
      client?.close();
    }
  }
}