// lib/main.dart
import 'dart:async';
import 'dart:convert'; // For SharedPreferences GameRecord & JSON
import 'dart:math';   // For SudokuGamePage UI calculations if any, and Point
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For LengthLimitingTextInputFormatter, SystemChrome


import 'package:firebase_core/firebase_core.dart';
// Local Persistence
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sudoku/firebase_options.dart';

// Project-specific imports
import 'country_data.dart';
import 'utils/logger.dart';
import 'utils/string_extensions.dart';

import 'models/leaderboard_entry.dart'; // Ensure LeaderboardEntry has countryName and updated toJson/fromJson
import 'models/game_record.dart';
import 'models/user_rank_and_time.dart';
import 'models/sudoku_cell.dart';

import 'services/api_service.dart'; 

import 'game_logic/difficulty.dart';
import 'game_logic/sudoku_generator.dart';

import 'theme/app_themes.dart';

import 'widgets/circular_number_picker.dart';
import 'widgets/sudoku_grid_widget.dart';
import 'widgets/leaderboard_section_widget.dart';

// --- CacheService (Ideally move to lib/utils/cache_service.dart) ---
class CacheService {
  static const String _leaderboardPrefix = 'leaderboard_cache_';
  static const String _userRanksPrefix = 'user_all_ranks_cache_';
  static const String _cacheTimestampSuffix = '_timestamp';
  static const Duration defaultMaxAge = Duration(minutes: 30); 

  static String _getLeaderboardCacheKey(Difficulty difficulty, String type, String? country) {
    String key = "$_leaderboardPrefix${difficulty.toString().split('.').last}_$type";
    if (type == 'country' && country != null && country.isNotEmpty && country.toLowerCase() != 'other') {
      key += "_${country.replaceAll(' ', '_').toLowerCase()}";
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
    logDebug("CacheService: Saved leaderboard to cache. Key: $key, Count: ${leaderboard.length}");
  }

  static Future<List<LeaderboardEntry>?> getLeaderboardFromCache(
      Difficulty difficulty, String type, String? country, {Duration maxAge = defaultMaxAge}) async {
    final prefs = await SharedPreferences.getInstance();
    String key = _getLeaderboardCacheKey(difficulty, type, country);
    
    int? timestamp = prefs.getInt("$key$_cacheTimestampSuffix");
    if (timestamp == null || DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(timestamp)) > maxAge) {
        logDebug("CacheService: Leaderboard cache expired or not found for key: $key (MaxAge: $maxAge)");
        await prefs.remove(key);
        await prefs.remove("$key$_cacheTimestampSuffix");
        return null;
    }

    List<String>? jsonList = prefs.getStringList(key);
    if (jsonList == null) {
        logDebug("CacheService: No leaderboard data in cache for key: $key");
        return null;
    }
    try {
      List<LeaderboardEntry> entries = jsonList.map((s) => LeaderboardEntry.fromJson(jsonDecode(s) as Map<String, dynamic>)).toList();
      logDebug("CacheService: Loaded ${entries.length} leaderboard entries from cache. Key: $key");
      return entries;
    } catch (e) {
      logDebug("CacheService: Error decoding leaderboard from cache for key: $key. Error: $e");
      await prefs.remove(key); 
      await prefs.remove("$key$_cacheTimestampSuffix");
      return null;
    }
  }

  static String _getUserRanksCacheKey(String username) {
    return "$_userRanksPrefix${username.replaceAll(' ', '_').toLowerCase()}";
  }

  static Future<void> saveUserRanksToCache(Map<Difficulty, UserRankAndTime> ranks, String username) async {
    if (username.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    String key = _getUserRanksCacheKey(username);
    Map<String, String> jsonMap = ranks.map((k, v) => MapEntry(k.toString(), jsonEncode(v.toJson())));
    String serializedMap = jsonEncode(jsonMap);
    await prefs.setString(key, serializedMap);
    await prefs.setInt("$key$_cacheTimestampSuffix", DateTime.now().millisecondsSinceEpoch);
    logDebug("CacheService: Saved user ranks to cache for $username. Count: ${ranks.length}");
  }

  static Future<Map<Difficulty, UserRankAndTime>?> getUserRanksFromCache(String username, {Duration maxAge = defaultMaxAge}) async {
    if (username.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    String key = _getUserRanksCacheKey(username);

    int? timestamp = prefs.getInt("$key$_cacheTimestampSuffix");
     if (timestamp == null || DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(timestamp)) > maxAge) {
        logDebug("CacheService: User ranks cache expired or not found for $username (MaxAge: $maxAge)");
        await prefs.remove(key);
        await prefs.remove("$key$_cacheTimestampSuffix");
        return null;
    }

    String? serializedMap = prefs.getString(key);
    if (serializedMap == null) {
        logDebug("CacheService: No user ranks data in cache for $username.");
        return null;
    }
    try {
      Map<String, dynamic> decodedJsonMap = jsonDecode(serializedMap) as Map<String, dynamic>;
      Map<Difficulty, UserRankAndTime> ranks = {};
      decodedJsonMap.forEach((k, v) {
        Difficulty? diffKey;
        try {
            // Ensure the key 'k' (like "Difficulty.superEasy") matches the format stored by toJson
            diffKey = Difficulty.values.firstWhere((d) => d.toString() == k);
        } catch(_){
            logDebug("CacheService: Error mapping difficulty key '$k' for user ranks cache during fromJson.");
        }
        
        if (diffKey != null && v is String) { // v should be a JSON string
          ranks[diffKey] = UserRankAndTime.fromJson(jsonDecode(v) as Map<String, dynamic>);
        } else {
            logDebug("CacheService: Skipped user rank entry. Key: $k, Value type: ${v.runtimeType}");
        }
      });
      logDebug("CacheService: Loaded ${ranks.length} user rank entries from cache for $username.");
      return ranks;
    } catch (e) {
      logDebug("CacheService: Error decoding user ranks from cache for $username. Error: $e");
      await prefs.remove(key);
      await prefs.remove("$key$_cacheTimestampSuffix");
      return null;
    }
  }
}
// --- End CacheService ---

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); 

await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: currentThemeMode,
      builder: (_, mode, __) => ValueListenableBuilder<Color>(
        valueListenable: currentSeedColor,
        builder: (_, seed, __) => ValueListenableBuilder<bool>(
          valueListenable: isHighContrastMode,
          builder: (_, isHighContrast, __) => ValueListenableBuilder<bool>(
            valueListenable: isHighContrastDark,
            builder: (_, isHighContrastDarkValue, __) {
              ThemeData lightThemeToUse;
              ThemeData darkThemeToUse;
              ThemeMode themeModeToUse = mode;

              if (isHighContrast) {
                lightThemeToUse = AppThemes.highContrastLightTheme;
                darkThemeToUse = AppThemes.highContrastDarkTheme;
                themeModeToUse =
                    isHighContrastDarkValue ? ThemeMode.dark : ThemeMode.light;
              } else {
                lightThemeToUse = AppThemes.getThemeData(seed, Brightness.light);
                darkThemeToUse = AppThemes.getThemeData(seed, Brightness.dark);
              }

              return MaterialApp(
                title: 'Sudoku World League',
                theme: lightThemeToUse,
                darkTheme: darkThemeToUse,
                themeMode: themeModeToUse,
                home: const SudokuGamePage(),
                debugShowCheckedModeBanner: false,
              );
            },
          ),
        ),
      ),
    );
  }
}


class SudokuGamePage extends StatefulWidget {
  const SudokuGamePage({super.key});
  @override
  State<SudokuGamePage> createState() => _SudokuGamePageState();
}

class _SudokuGamePageState extends State<SudokuGamePage>
    with WidgetsBindingObserver {

  List<List<SudokuCell>> _board = [];
  Difficulty _currentDifficulty = Difficulty.medium;
  int? _selectedRow, _selectedCol;
  bool _showNumberPicker = false;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;
  String _elapsedTime = '00:00';
  Map<int, int> _numberCounts = {};

  static const String _gamesToAdFreeKey = 'gamesToAdFreeCount';
  static const int _initialGamesToAdFree = 3;
  int _gamesToAdFree = _initialGamesToAdFree;
  bool _adsCurrentlyEnabled = true;
  bool _isBannerAdLoaded = false;
  bool _isInterstitialAdReady = false;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _usernameController = TextEditingController();
  String? _selectedCountry;

  String? _username;
  static const String _usernameKey = 'sudokuUsername';
  static const String _userCountryKey = 'sudokuUserCountry';

  List<LeaderboardEntry> _leaderboardData = [];
  bool _showGlobalLeaderboard = true;
  bool _isLoadingLeaderboard = false; 
  int? _userRank;
  Difficulty _leaderboardDifficultyFilter = Difficulty.medium;
  Map<Difficulty, UserRankAndTime> _currentUserAllRanks = {};

  List<GameRecord> _gameHistory = [];
  static const String _gameHistoryKey = 'sudokuGameHistory';
  static const int _maxHistoryItems = 100;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeGameAndEnsimminenPeli();
  }

  Future<void> _initializeGameAndEnsimminenPeli() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    _loadAdFreeCounter();
    await _loadUserSettings(); 
    _loadGameHistory();

    logDebug("Initializing game and pre-caching leaderboards...");

    await _loadLeaderboardFromCacheOrApi(
        difficultyToLoad: _leaderboardDifficultyFilter,
        typeToLoad: _showGlobalLeaderboard ? "global" : "country",
        countryToLoad: _selectedCountry,
        isInitialDisplay: true,
        forceApi: false
    );

    _preCacheAllLeaderboards(); 

    if (_username != null && _username!.isNotEmpty) {
      await _loadUserRanksFromCacheOrApi(isInitialLoad: true, forceApi: false);
    } else {
      if(mounted) {
        _currentUserAllRanks = {}; 
        _updateUserRankDisplay(); 
      }
    }
    
    _setupNewGameBoard(isInitialSetup: true); 

    if (_adsCurrentlyEnabled) {
      _loadBannerAd();
      _loadInterstitialAd();
    }
  }
  
  Future<void> _preCacheAllLeaderboards() async {
    logDebug("Starting to pre-cache all leaderboards silently...");
    var currentlyDisplayedKey = CacheService._getLeaderboardCacheKey(_leaderboardDifficultyFilter, _showGlobalLeaderboard ? "global" : "country", _selectedCountry);

    for (Difficulty diff in Difficulty.values) {
      if (!mounted) return; 
      
      String globalKey = CacheService._getLeaderboardCacheKey(diff, "global", null);
      if (globalKey != currentlyDisplayedKey) { 
        List<LeaderboardEntry>? cachedGlobal = await CacheService.getLeaderboardFromCache(diff, "global", null);
        if (cachedGlobal == null) { 
            logDebug("Pre-caching global for $diff from API.");
            // Fire and forget, do not await these pre-cache fetches
            _fetchLeaderboardFromApiAndCache( 
                difficultyToFetch: diff, 
                typeToFetch: "global", 
                countryToFetch: null, 
                isSilent: true, 
                isPreCaching: true
            );
        }
      }

      if (_selectedCountry != null && _selectedCountry!.toLowerCase() != 'other') {
        if (!mounted) return;
        String countryKey = CacheService._getLeaderboardCacheKey(diff, "country", _selectedCountry);
         if (countryKey != currentlyDisplayedKey) {
            List<LeaderboardEntry>? cachedCountry = await CacheService.getLeaderboardFromCache(diff, "country", _selectedCountry);
            if (cachedCountry == null) {
                logDebug("Pre-caching country '$_selectedCountry' for $diff from API.");
                _fetchLeaderboardFromApiAndCache( 
                    difficultyToFetch: diff, 
                    typeToFetch: "country", 
                    countryToFetch: _selectedCountry, 
                    isSilent: true, 
                    isPreCaching: true
                );
            }
        }
      }
      // Add a small delay to avoid overwhelming the API or device resources during pre-caching
       if (mounted) await Future.delayed(const Duration(milliseconds: 300)); 
    }
    logDebug("Pre-caching requests initiated.");
  }


  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _usernameController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (_stopwatch.isRunning) _stopwatch.stop();
    } else if (state == AppLifecycleState.resumed) {
      if (!_stopwatch.isRunning && _board.isNotEmpty && !_isGameEffectivelyOver()) {
        _stopwatch.start();
      }
    }
  }

  bool _isGameEffectivelyOver() {
    if (_board.isEmpty) return false;
    return _board.every((row) => row.every((cell) => cell.value != 0));
  }
  
  Future<void> _loadUserSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _username = prefs.getString(_usernameKey);
        _usernameController.text = _username ?? "";
        _selectedCountry = prefs.getString(_userCountryKey) ??
            selectableCountries.firstWhere((c) => c == 'Other', orElse: () => selectableCountries.first);
      });
    }
  }

  Future<void> _saveUserSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String newUsername = _usernameController.text.trim();
    bool profileChanged = (_username ?? "") != newUsername || _selectedCountry != prefs.getString(_userCountryKey);

    // Username availability check (if new username and not empty)
    if (newUsername.isNotEmpty && newUsername != _username) {
        if (mounted) setState(() => _isLoadingLeaderboard = true); // Use general loader
        Map<String, dynamic> availabilityResult = await ApiService.checkUsernameAvailability(newUsername);
        if (mounted) setState(() => _isLoadingLeaderboard = false);

        if (!mounted) return;

        if (availabilityResult['available'] != true) {
            ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(availabilityResult['message'] ?? "Username not available."), backgroundColor: Colors.red),
            );
            _usernameController.text = _username ?? ""; // Revert to old username in text field
            return; 
        }
    }


    if (newUsername.isNotEmpty) {
      await prefs.setString(_usernameKey, newUsername);
    } else {
      await prefs.remove(_usernameKey);
    }

    if (_selectedCountry != null) {
      await prefs.setString(_userCountryKey, _selectedCountry!);
    } else {
      await prefs.remove(_userCountryKey);
    }
    
    if (mounted) {
      setState(() => _username = newUsername.isNotEmpty ? newUsername : null);
      
      await _loadLeaderboardFromCacheOrApi(
          difficultyToLoad: _leaderboardDifficultyFilter, 
          typeToLoad: _showGlobalLeaderboard ? "global" : "country", 
          countryToLoad: _selectedCountry,
          forceApi: profileChanged 
      ); 
      if (_username != null && _username!.isNotEmpty) {
        await _loadUserRanksFromCacheOrApi(forceApi: profileChanged || newUsername != _username);
      } else {
        if(mounted){
          _currentUserAllRanks = {};
          _updateUserRankDisplay();
        }
      }
    }
     if(mounted) Navigator.pop(context); // Close drawer
     if(mounted) ScaffoldMessenger.of(context).showSnackBar(
       const SnackBar(content: Text("Profile settings saved!"), duration: Duration(seconds: 2))
     );
  }

  // --- CACHE-AWARE DATA FETCHING ---
  Future<void> _loadLeaderboardFromCacheOrApi({
    required Difficulty difficultyToLoad,
    required String typeToLoad,
    String? countryToLoad,
    bool isInitialDisplay = false, 
    bool forceApi = false,
  }) async {
    bool isCurrentView = difficultyToLoad == _leaderboardDifficultyFilter && 
                       typeToLoad == (_showGlobalLeaderboard ? "global" : "country") &&
                       (typeToLoad != "country" || countryToLoad == _selectedCountry);

    if (mounted && isCurrentView) { 
      bool cacheExistsForThisView = await CacheService.getLeaderboardFromCache(
                                difficultyToLoad, typeToLoad, countryToLoad, 
                                maxAge: const Duration(days: 365)
                           ) != null;
      bool shouldShowLoader = forceApi || (isInitialDisplay && !cacheExistsForThisView);
      
      if (shouldShowLoader && !_isLoadingLeaderboard) {
           setState(() => _isLoadingLeaderboard = true);
      }
    }

    List<LeaderboardEntry>? cachedData;
    if (!forceApi) {
      cachedData = await CacheService.getLeaderboardFromCache(difficultyToLoad, typeToLoad, countryToLoad);
    }

    if (cachedData != null) {
      logDebug("Loaded leaderboard from CACHE for ${difficultyToLoad.toString().split('.').last} ($typeToLoad)");
      if (mounted) {
        if (isCurrentView) { 
          _leaderboardData = cachedData;
          _updateUserRankDisplay(); 
          setState(() {}); 
        }
        if (mounted && _isLoadingLeaderboard && isCurrentView && (forceApi || isInitialDisplay)) {
          setState(() => _isLoadingLeaderboard = false);
        }
      }
      if (isInitialDisplay && !forceApi && isCurrentView) { 
        _fetchLeaderboardFromApiAndCache(
          difficultyToFetch: difficultyToLoad, 
          typeToFetch: typeToLoad, 
          countryToFetch: countryToLoad, 
          isSilent: true
        );
      }
    } else {
      logDebug("Fetching leaderboard from API (cache miss/forced) for ${difficultyToLoad.toString().split('.').last} ($typeToLoad)");
      await _fetchLeaderboardFromApiAndCache(
        difficultyToFetch: difficultyToLoad, 
        typeToFetch: typeToLoad, 
        countryToFetch: countryToLoad, 
        isSilent: isInitialDisplay && !forceApi,
        showLoaderOverride: isCurrentView && (forceApi || (isInitialDisplay && cachedData == null)) 
      );
    }
  }

  Future<void> _fetchLeaderboardFromApiAndCache({
    required Difficulty difficultyToFetch,
    required String typeToFetch,
    String? countryToFetch,
    bool isSilent = false,
    bool isPreCaching = false,
    bool showLoaderOverride = false, 
  }) async {
    bool isCurrentView = difficultyToFetch == _leaderboardDifficultyFilter && 
                       typeToFetch == (_showGlobalLeaderboard ? "global" : "country") &&
                       (typeToFetch != "country" || countryToFetch == _selectedCountry);

    if (showLoaderOverride && isCurrentView && mounted && !_isLoadingLeaderboard) {
        setState(() => _isLoadingLeaderboard = true);
    }
    try {
      final data = await ApiService.fetchLeaderboard(typeToFetch, difficultyToFetch, countryToFetch, _username);
      if (mounted) {
        await CacheService.saveLeaderboardToCache(data, difficultyToFetch, typeToFetch, countryToFetch);
        // logDebug("Leaderboard API data cached for ${difficultyToFetch.toString().split('.').last} ($typeToFetch)"); // Reduced verbosity

        if (isCurrentView) { 
          bool dataChangedUI = jsonEncode(_leaderboardData.map((e)=>e.toJson()).toList()) != jsonEncode(data.map((e)=>e.toJson()).toList());
          _leaderboardData = data;
          _updateUserRankDisplay();
          
          if (dataChangedUI || (showLoaderOverride && _isLoadingLeaderboard) || (!isSilent && !isPreCaching)) { 
              setState((){}); 
          }
        }
      }
    } catch (e) {
      logDebug("Error fetching/caching leaderboard ($difficultyToFetch, $typeToFetch): $e");
      if(isCurrentView && !isSilent && !isPreCaching) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("Error loading leaderboard: ${e.toString().substring(0, min(e.toString().length, 50))}..."),
              backgroundColor: Colors.red));
      }
    } finally {
        if (showLoaderOverride && isCurrentView && mounted && _isLoadingLeaderboard) {
            setState(() => _isLoadingLeaderboard = false);
        }
    }
  }

  Future<void> _loadUserRanksFromCacheOrApi({bool isInitialLoad = false, bool forceApi = false}) async {
    if (_username == null || _username!.isEmpty) {
       if(mounted) {
         _currentUserAllRanks = {};
         _updateUserRankDisplay();
       }
       return;
    }
    
    Map<Difficulty, UserRankAndTime>? cachedRanks;
    if (!forceApi) {
        cachedRanks = await CacheService.getUserRanksFromCache(_username!);
    }

    if (cachedRanks != null) {
      logDebug("Loaded user ranks from CACHE for $_username");
      if (mounted) {
        _currentUserAllRanks = cachedRanks;
        _updateUserRankDisplay();
        if (isInitialLoad && !forceApi) { // Refresh UI if data came from cache on initial load
            setState((){}); 
        }
      }
      if (isInitialLoad && !forceApi) { 
        _fetchUserRanksFromApiAndCache(isSilent: true, isInitialLoad: true);
      }
    } else {
      logDebug("Fetching user ranks from API (cache miss/forced) for $_username");
      await _fetchUserRanksFromApiAndCache(isSilent: isInitialLoad && !forceApi, isInitialLoad: isInitialLoad);
    }
  }

  Future<void> _fetchUserRanksFromApiAndCache({bool isSilent = false, bool isInitialLoad = false}) async {
    if (_username == null || _username!.isEmpty) return;
    
    bool showLoaderForThis = !isInitialLoad && !isSilent && !_isLoadingLeaderboard;
    if(showLoaderForThis && mounted) setState(() => _isLoadingLeaderboard = true);


    try {
      final ranks = await ApiService.fetchUserSpecificRanks(_username!);
      if (mounted) {
        bool ranksChanged = jsonEncode(_currentUserAllRanks.map((k,v)=> MapEntry(k.toString(), v.toJson()))) 
                           != jsonEncode(ranks.map((k,v)=> MapEntry(k.toString(), v.toJson())));

        _currentUserAllRanks = ranks;
        _updateUserRankDisplay(); 

        await CacheService.saveUserRanksToCache(ranks, _username!);
        logDebug("User ranks API data cached for $_username");
         if ((isSilent || isInitialLoad) && ranksChanged ) {
            setState((){}); 
         }
      }
    } catch (e) {
      logDebug("Error fetching/caching user ranks: $e");
    } finally {
        if(showLoaderForThis && mounted && _isLoadingLeaderboard) {
            setState(() => _isLoadingLeaderboard = false);
        }
    }
  }
  
  void _updateUserRankDisplay() {
    // logDebug("_updateUserRankDisplay called. Current leaderboard filter: $_leaderboardDifficultyFilter. Username: $_username"); // Reduced verbosity

    if (_username == null || _username!.isEmpty) {
      // logDebug("No username, setting _userRank to null if it's not already.");
      if (mounted && _userRank != null) {
        setState(() => _userRank = null);
      }
      return;
    }

    UserRankAndTime? rankData = _currentUserAllRanks[_leaderboardDifficultyFilter];
    int? newRank;
    if (rankData != null && rankData.found && rankData.rank != null) {
      newRank = rankData.rank;
    } else {
      newRank = null;
    }

    if (mounted && _userRank != newRank) {
      logDebug("Updating _userRank from $_userRank to $newRank for filter $_leaderboardDifficultyFilter.");
      setState(() {
        _userRank = newRank;
      });
    }
  }

  void _setLeaderboardType(bool isGlobal) { 
    if (mounted && _showGlobalLeaderboard != isGlobal) { 
      final newType = isGlobal ? "global" : "country";
      setState(() => _showGlobalLeaderboard = isGlobal); 
      _loadLeaderboardFromCacheOrApi(
        difficultyToLoad: _leaderboardDifficultyFilter,
        typeToLoad: newType,
        countryToLoad: _selectedCountry,
        forceApi: false,
        isInitialDisplay: false // Not an initial display when user clicks toggle
      ); 
    } 
  }
  
  Future<void> _loadGameHistory() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? historyJson = prefs.getString(_gameHistoryKey);
    if (historyJson != null) {
      try {
        final List<dynamic> decodedList = jsonDecode(historyJson);
        if (mounted) {
          setState(() { _gameHistory = decodedList.map((item) => GameRecord.fromJson(item as Map<String,dynamic>)).toList(); });
        }
      } catch (e) { logDebug("Error loading game history: $e"); if (mounted) setState(() => _gameHistory = []); }
    }
  }

  Future<void> _saveGameHistory() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> historyToSave = _gameHistory.map((record) => record.toJson()).toList();
    await prefs.setString(_gameHistoryKey, jsonEncode(historyToSave));
  }

  void _addGameToHistory(Difficulty difficulty, int timeSeconds) { 
    final newRecord = GameRecord(difficulty: difficulty, timeSeconds: timeSeconds, date: DateTime.now()); 
    if (mounted) { setState(() { _gameHistory.insert(0, newRecord); if (_gameHistory.length > _maxHistoryItems) { _gameHistory = _gameHistory.sublist(0, _maxHistoryItems); } }); }
    _saveGameHistory(); 
  }
  
  Map<Difficulty, String> _calculateAverageTimes() { 
    Map<Difficulty, List<int>> timesByDifficulty = {}; for (var record in _gameHistory) { timesByDifficulty.putIfAbsent(record.difficulty, () => []).add(record.timeSeconds); } Map<Difficulty, String> averageTimes = {}; timesByDifficulty.forEach((difficulty, times) { if (times.isNotEmpty) { double avgSeconds = times.reduce((a, b) => a + b) / times.length; averageTimes[difficulty] = '${(avgSeconds ~/ 60).toString().padLeft(2, '0')}:${(avgSeconds % 60).round().toString().padLeft(2, '0')}'; } else { averageTimes[difficulty] = "N/A"; } }); return averageTimes; 
  }

  void _showGameHistoryDialog() { 
    Map<Difficulty, String> averageTimes = _calculateAverageTimes(); showDialog( context: context, builder: (context) => AlertDialog( title: const Text("Game History & Averages"), content: SizedBox( width: double.maxFinite, child: Column( mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [ const Text("Average Times:", style: TextStyle(fontWeight: FontWeight.bold)), ...Difficulty.values.map((d) => Text("${d.toString().split('.').last.capitalizeFirst()}: ${averageTimes[d] ?? 'N/A'}")).toList(), const SizedBox(height: 10), const Text("Last 10 Games:", style: TextStyle(fontWeight: FontWeight.bold)), _gameHistory.isEmpty ? const Text("No games played yet.") : Expanded( child: ListView.builder( shrinkWrap: true, itemCount: min(10, _gameHistory.length), itemBuilder: (ctx, index) { final record = _gameHistory[index]; return ListTile( dense: true, title: Text("${record.difficulty.toString().split('.').last.capitalizeFirst()} - ${record.formattedTime}"), subtitle: Text(record.date.toLocal().toString().substring(0, 16)), ); }, ), ), ], ), ), actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Close"))], ), ); 
  }
  
  Future<void> _loadAdFreeCounter() async { 
    try { final SharedPreferences prefs = await SharedPreferences.getInstance(); if (mounted) { setState(() { _gamesToAdFree = prefs.getInt(_gamesToAdFreeKey) ?? _initialGamesToAdFree; _adsCurrentlyEnabled = _gamesToAdFree > 0; if (!_adsCurrentlyEnabled) _isBannerAdLoaded = false; }); } } catch (e) { logDebug("Error loading ad-free counter: $e"); if (mounted) { setState(() { _gamesToAdFree = _initialGamesToAdFree; _adsCurrentlyEnabled = true; }); } } 
  }

  Future<void> _saveAdFreeCounter() async { 
    final SharedPreferences prefs = await SharedPreferences.getInstance(); await prefs.setInt(_gamesToAdFreeKey, _gamesToAdFree); 
  }

  void _decrementAdFreeCounter() { 
    if (_adsCurrentlyEnabled && _gamesToAdFree > 0) { if (mounted) { setState(() { _gamesToAdFree--; if (_gamesToAdFree <= 0) { _adsCurrentlyEnabled = false; _isBannerAdLoaded = false; } }); } _saveAdFreeCounter(); } 
  }

  void _loadBannerAd() { 
    if (_adsCurrentlyEnabled && mounted) { Future.delayed(const Duration(milliseconds: 500), () { if (mounted && _adsCurrentlyEnabled) { setState(() => _isBannerAdLoaded = true); } }); } else if (mounted) { setState(() => _isBannerAdLoaded = false); } 
  }

  void _loadInterstitialAd() { 
    if (_adsCurrentlyEnabled && !_isInterstitialAdReady && mounted) { Future.delayed(const Duration(milliseconds: 700), () { if (mounted && _adsCurrentlyEnabled) { setState(() => _isInterstitialAdReady = true); } }); } 
  }

  void _showInterstitialAd(VoidCallback onAdDismissed) { 
    if (_adsCurrentlyEnabled && _isInterstitialAdReady && mounted) { logDebug("SIMULATING: Showing Interstitial Ad..."); Future.delayed(const Duration(milliseconds: 200), () { logDebug("SIMULATING: Interstitial Ad Dismissed."); if (mounted) { setState(() => _isInterstitialAdReady = false); } _loadInterstitialAd(); onAdDismissed(); }); } else { onAdDismissed(); } 
  }

  void _startTimer() { 
    _stopwatch.reset(); _stopwatch.start(); _timer?.cancel(); _timer = Timer.periodic(const Duration(seconds: 1), (timer) { if (_stopwatch.isRunning) { if (mounted) { setState(() => _elapsedTime = '${(_stopwatch.elapsed.inMinutes % 60).toString().padLeft(2, '0')}:${(_stopwatch.elapsed.inSeconds % 60).toString().padLeft(2, '0')}'); } else { timer.cancel(); _stopwatch.stop(); } } }); 
  }
  
  void _setupNewGameBoard({bool isInitialSetup = false}) { 
    if (mounted) {
      logDebug("_setupNewGameBoard called. isInitialSetup: $isInitialSetup, currentDiff: $_currentDifficulty");
      setState(() {
        _board = SudokuGenerator.generatePuzzle(_currentDifficulty);
        _updateNumberCounts();
        _selectedRow = null; _selectedCol = null; _showNumberPicker = false; _elapsedTime = '00:00';
        // When a new game starts (either by user action or initial setup),
        // align the leaderboard filter with this new game's difficulty.
        _leaderboardDifficultyFilter = _currentDifficulty; 
        for (var row in _board) { for (var cell in row) { cell.isError = false; } }
      });
      _stopwatch.reset(); _startTimer();

      if (!isInitialSetup) {
        logDebug("_setupNewGameBoard: Not initial setup. Refreshing leaderboard view for new filter $_leaderboardDifficultyFilter.");
        // This will load from cache first for the new difficulty filter
        _loadLeaderboardFromCacheOrApi(
            difficultyToLoad: _leaderboardDifficultyFilter, // Use the now-updated filter
            typeToLoad: _showGlobalLeaderboard ? "global" : "country",
            countryToLoad: _selectedCountry,
            forceApi: false, // Usually false, rely on cache
            isInitialDisplay: false // Not an initial app display
        ); 
      }
      // Always ensure rank display is updated based on the current (possibly new) leaderboard filter
      // using the existing _currentUserAllRanks (which is refreshed at app start or after game win).
      _updateUserRankDisplay(); 
    }
  }

  Future<void> _triggerNewGameSequence() async {
    _setupNewGameBoard(isInitialSetup: false);
    // Preload interstitial for the next game completion.
    if (_adsCurrentlyEnabled) { 
        _loadInterstitialAd();
    }
  }

  void _updateNumberCounts() { 
    Map<int, int> counts = {for (var i = 1; i <= 9; i++) i: 0}; if (_board.isNotEmpty) { for (var row in _board) { for (var cell in row) { if (cell.value >= 1 && cell.value <= 9) { counts[cell.value] = (counts[cell.value] ?? 0) + 1; } } } } if (mounted) setState(() => _numberCounts = counts); 
  }

  void _onCellSelected(int r, int c) { 
    if (_board[r][c].isFixed) return; if (mounted) { setState(() { _selectedRow = r; _selectedCol = c; _showNumberPicker = true; }); } 
  }

  void _onNumberPicked(int? num) { 
    if (_selectedRow != null && _selectedCol != null) { if (mounted) { setState(() { _board[_selectedRow!][_selectedCol!].isError = false; _board[_selectedRow!][_selectedCol!].value = num ?? 0; _updateNumberCounts(); _showNumberPicker = false; }); } _checkWinCondition(); } else { if (mounted) setState(() => _showNumberPicker = false); } 
  }
  
  int _countErrorsOnBoard() {
    Set<String> errorCellCoords = {}; List<List<SudokuCell>> tempBoard = _board; for (int i = 0; i < 9; i++) { Map<int, List<int>> positions = {}; for (int j = 0; j < 9; j++) { if (tempBoard[i][j].value != 0) { positions.putIfAbsent(tempBoard[i][j].value, () => []).add(j); } } positions.forEach((num, cols) { if (cols.length > 1) { for (var col in cols) { if (!tempBoard[i][col].isFixed) errorCellCoords.add("$i,$col"); } } }); } for (int j = 0; j < 9; j++) { Map<int, List<int>> positions = {}; for (int i = 0; i < 9; i++) { if (tempBoard[i][j].value != 0) { positions.putIfAbsent(tempBoard[i][j].value, () => []).add(i); } } positions.forEach((num, rows) { if (rows.length > 1) { for (var row in rows) { if (!tempBoard[row][j].isFixed) errorCellCoords.add("$row,$j"); } } }); } for (int blockRow = 0; blockRow < 3; blockRow++) { for (int blockCol = 0; blockCol < 3; blockCol++) { Map<int, List<Point<int>>> positions = {}; for (int i = blockRow * 3; i < blockRow * 3 + 3; i++) { for (int j = blockCol * 3; j < blockCol * 3 + 3; j++) { if (tempBoard[i][j].value != 0) { positions.putIfAbsent(tempBoard[i][j].value, () => []).add(Point(i,j)); } } } positions.forEach((num, coords) { if (coords.length > 1) { for (var p in coords) { if(!tempBoard[p.x][p.y].isFixed) errorCellCoords.add("${p.x},${p.y}"); } } }); } } if (mounted) { setState(() { for (var r = 0; r < 9; r++) { for (var c = 0; c < 9; c++) { if (!_board[r][c].isFixed) _board[r][c].isError = false; } } for (String coordStr in errorCellCoords) { var parts = coordStr.split(','); int r = int.parse(parts[0]); int c = int.parse(parts[1]); if (!_board[r][c].isFixed) _board[r][c].isError = true; } }); } return errorCellCoords.length;
  }

  bool _isSetValid(List<int> numbers) { 
    Set<int> seen = {}; for (int num in numbers) { if (num == 0) return false; if (num < 1 || num > 9) return false; if (seen.contains(num)) return false; seen.add(num); } return true;
  }

  bool _validateBoard() { 
    for (int i = 0; i < 9; i++) { if (!_isSetValid(_board[i].map((cell) => cell.value).toList())) return false; } for (int j = 0; j < 9; j++) { if (!_isSetValid(_board.map((row) => row[j].value).toList())) return false; } for (int blockRow = 0; blockRow < 3; blockRow++) { for (int blockCol = 0; blockCol < 3; blockCol++) { List<int> subgridValues = []; for (int i = blockRow * 3; i < blockRow * 3 + 3; i++) { for (int j = blockCol * 3; j < blockCol * 3 + 3; j++) { subgridValues.add(_board[i][j].value); } } if (!_isSetValid(subgridValues)) return false; } } return true;
  }

  void _handleHintAction() { 
    Set<String> errorCellCoords = {}; List<List<SudokuCell>> tempBoard = _board; bool hasDuplicates(List<int> numbers, Function(int index) getCellCoords) { Map<int, List<int>> positions = {}; for (int k=0; k<numbers.length; k++) { if (numbers[k] != 0) positions.putIfAbsent(numbers[k], () => []).add(k); } bool foundErrorInSet = false; positions.forEach((num, indices) { if (indices.length > 1) { foundErrorInSet = true; for (var idx in indices) { Point<int> p = getCellCoords(idx); if (!tempBoard[p.x][p.y].isFixed) { errorCellCoords.add("${p.x},${p.y}"); } } } }); return foundErrorInSet; } for (int i = 0; i < 9; i++) { hasDuplicates(tempBoard[i].map((c) => c.value).toList(), (j) => Point(i,j)); } for (int j = 0; j < 9; j++) { hasDuplicates(tempBoard.map((row) => row[j].value).toList(), (i) => Point(i,j)); } for (int br = 0; br < 3; br++) { for (int bc = 0; bc < 3; bc++) { List<int> boxData = []; List<Point<int>> boxCoords = []; for (int r = br*3; r < br*3+3; r++) { for (int c = bc*3; c < bc*3+3; c++) { boxData.add(tempBoard[r][c].value); boxCoords.add(Point(r,c)); } } hasDuplicates(boxData, (k) => boxCoords[k]); } } if (mounted) { Navigator.of(context).pop(); if (errorCellCoords.isNotEmpty) { setState(() { for (String coordStr in errorCellCoords) { var parts = coordStr.split(','); int r = int.parse(parts[0]); int c = int.parse(parts[1]); if (!_board[r][c].isFixed) { _board[r][c].value = 0; _board[r][c].isError = false; } } _updateNumberCounts(); }); ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text("Incorrect entries cleared."), duration: Duration(seconds: 2)) ); } else { ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text("No clear errors found to remove."), duration: Duration(seconds: 2)) ); } }
  }

  void _showErrorDialog(int errorCount) { 
    showDialog( context: context, barrierDismissible: false, builder: (BuildContext context) { return AlertDialog( title: const Text('Incorrect Solution'), content: Text(errorCount == 1 ? 'You have 1 error in your solution.' : 'You have $errorCount errors in your solution.'), actions: <Widget>[ TextButton(child: const Text('OK'), onPressed: () => Navigator.of(context).pop()), TextButton(child: const Text('Hint (Clear Errors)'), onPressed: _handleHintAction), TextButton(child: const Text('End Game'), onPressed: () { Navigator.of(context).pop(); _triggerNewGameSequence(); }), ], ); }, );
  }
  
  void _checkWinCondition() async { 
    bool isFull = _board.every((row) => row.every((cell) => cell.value != 0));
    if (isFull) {
      bool isValid = _validateBoard();
      if (isValid) {
        final int timeTakenSeconds = _stopwatch.elapsed.inSeconds;
        if (_stopwatch.isRunning) _stopwatch.stop();
        _decrementAdFreeCounter();
        _addGameToHistory(_currentDifficulty, timeTakenSeconds);
        if (_username != null && _username!.isNotEmpty) {
          bool updateSuccess = await ApiService.updateLeaderboardScore( difficulty: _currentDifficulty, username: _username!, timeSeconds: timeTakenSeconds, selectedUserCountryName: _selectedCountry, );
          if (updateSuccess) {
            await _loadLeaderboardFromCacheOrApi( difficultyToLoad: _currentDifficulty, typeToLoad: _showGlobalLeaderboard ? "global" : "country", countryToLoad: _selectedCountry, forceApi: true); 
            await _loadUserRanksFromCacheOrApi(forceApi: true); 
          } else {
             if(mounted) { ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text("Failed to update leaderboard."))); }
          }
        }
        _showInterstitialAd(() { if (mounted) _showWinDialogAndRestart(); });
      } else { 
        int errorCount = _countErrorsOnBoard(); 
        if (mounted) { _showErrorDialog(errorCount > 0 ? errorCount : 1); }
      }
    }
  }

  void _showWinDialogAndRestart() { 
    showDialog(context: context, barrierDismissible: false, builder: (context) => AlertDialog( title: const Text('Congratulations!'), content: Text('Solved in $_elapsedTime!'), actions: [ TextButton(onPressed: () { Navigator.of(context).pop(); _triggerNewGameSequence(); }, child: const Text('New Game')),], ));
  }
  
  void _showContentDialog(String title, String contentText) {
    showDialog( context: context, builder: (ctx) => AlertDialog( title: Text(title), content: SingleChildScrollView(child: Text(contentText)), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],));
  }

  void _showInfoDialog(String title, String content) { 
     showDialog( context: context, builder: (ctx) => AlertDialog( title: Text(title), content: Text(content), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],),);
  }

  Widget _buildAppDrawer(BuildContext context) {
    ThemeSetting currentActiveSetting = ThemeSetting.system; if (isHighContrastMode.value) { currentActiveSetting = isHighContrastDark.value ? ThemeSetting.highContrastDark : ThemeSetting.highContrastLight; } else if (currentThemeMode.value == ThemeMode.system) { currentActiveSetting = ThemeSetting.system; } else if (currentThemeMode.value == ThemeMode.dark) { currentActiveSetting = ThemeSetting.darkMode; } else if (currentThemeMode.value == ThemeMode.light) { currentActiveSetting = ThemeSetting.lightMode; } final activeColorTheme = AppThemes.colorOptions.firstWhere((opt) => opt.color == currentSeedColor.value && !isHighContrastMode.value, orElse: () => AppThemeOption("none", ThemeSetting.system) ); if (activeColorTheme.setting != ThemeSetting.system && activeColorTheme.color != null && !isHighContrastMode.value) { currentActiveSetting = activeColorTheme.setting; }
    return Drawer( child: SafeArea( child: SingleChildScrollView( padding: const EdgeInsets.all(16.0), child: Column( mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[ Text("Settings", style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).colorScheme.primary)), const SizedBox(height: 16), Row( children: [ Text("User Profile", style: Theme.of(context).textTheme.titleMedium), IconButton( icon: Icon(Icons.help_outline, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant), onPressed: () => _showInfoDialog("Username Info", "Your username will be displayed on the leaderboards. Keep it friendly! Max 20 characters."), padding: EdgeInsets.zero, constraints: const BoxConstraints(), ) ], ), TextField( controller: _usernameController, decoration: const InputDecoration(labelText: "Username", hintText: "Enter your username"), inputFormatters: [LengthLimitingTextInputFormatter(20)], ), const SizedBox(height: 8), Row( children: [ Text("Country", style: Theme.of(context).textTheme.labelLarge), IconButton( icon: Icon(Icons.help_outline, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant), onPressed: () => _showInfoDialog("Country Info", "Selecting your country allows you to see country-specific leaderboards and helps us display your flag!"), padding: EdgeInsets.zero, constraints: const BoxConstraints(), ) ], ), DropdownButtonFormField<String>( value: _selectedCountry, isExpanded: true, items: selectableCountries.map((String country) { return DropdownMenuItem<String>( value: country, child: Row( children: [ Text(countryFlags[country] ?? ' ', style: const TextStyle(fontSize: 18)), const SizedBox(width: 8), Expanded(child: Text(country, overflow: TextOverflow.ellipsis)), ], ), ); }).toList(), onChanged: (String? newValue) { if (newValue != null && mounted) { setState(() { _selectedCountry = newValue; }); } }, ), const SizedBox(height: 12), SizedBox( width: MediaQuery.of(context).size.width * 0.9 * 0.7, child: ElevatedButton( style: ElevatedButton.styleFrom( padding: const EdgeInsets.symmetric(vertical: 12) ), onPressed: () { _saveUserSettings(); }, child: const Text("Save Profile"), ), ), const SizedBox(height: 20), Text("Theme Settings", style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 8), DropdownButtonFormField<ThemeSetting>( decoration: InputDecoration( border: InputBorder.none, filled: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0), fillColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3), ), dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh, value: currentActiveSetting, items: AppThemes.getAllThemeSettings().map((AppThemeOption option) { return DropdownMenuItem<ThemeSetting>( value: option.setting, child: Row(children: [ if (option.color != null) CircleAvatar(backgroundColor: option.color, radius: 10), if (option.color == null) Icon( option.setting == ThemeSetting.darkMode || option.setting == ThemeSetting.highContrastDark ? Icons.dark_mode_outlined : option.setting == ThemeSetting.lightMode || option.setting == ThemeSetting.highContrastLight ? Icons.light_mode_outlined : option.setting == ThemeSetting.system ? Icons.brightness_auto_outlined : Icons.color_lens_outlined, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant ), const SizedBox(width: 10), Text(option.name, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)), ]), ); }).toList(), onChanged: (ThemeSetting? newValue) { if (newValue == null) return; isHighContrastMode.value = false; if (newValue.index < AppThemes.colorOptions.length) { final selectedColorOption = AppThemes.colorOptions.firstWhere((opt) => opt.setting == newValue); currentSeedColor.value = selectedColorOption.color!; if (currentThemeMode.value == ThemeMode.system) { currentThemeMode.value = ThemeMode.light; } } else { switch (newValue) { case ThemeSetting.system: currentThemeMode.value = ThemeMode.system; break; case ThemeSetting.lightMode: currentThemeMode.value = ThemeMode.light; break; case ThemeSetting.darkMode: currentThemeMode.value = ThemeMode.dark; break; case ThemeSetting.highContrastLight: isHighContrastMode.value = true; isHighContrastDark.value = false; currentThemeMode.value = ThemeMode.light; break; case ThemeSetting.highContrastDark: isHighContrastMode.value = true; isHighContrastDark.value = true; currentThemeMode.value = ThemeMode.dark; break; default: break; } } }, ), const Divider(height: 24), _buildDrawerListItem(context, Icons.history_edu_outlined, 'Game History', () { _showGameHistoryDialog(); }), _buildDrawerListItem(context, Icons.description_outlined, 'Terms & Conditions', () { _showContentDialog("Terms & Conditions", "1. Be nice.\n2. Have fun solving Sudoku puzzles!\n3. All data is stored locally or on Google Sheets as per your game activity. Usernames on leaderboards are public.\n4. We are not responsible for any addictive puzzle-solving behavior (just kidding, mostly!)."); }), _buildDrawerListItem(context, Icons.question_answer_outlined, 'FAQs', () { _showContentDialog("FAQs", "Q: How does the leaderboard work?\nA: Scores are submitted to a Google Sheet. Top scores for each difficulty are displayed.\n\nQ: Can I play offline?\nA: Yes, core gameplay is offline. Leaderboard features require internet.\n\nQ: How are puzzles generated?\nA: Puzzles are generated by removing numbers from a pre-solved master board. Difficulty determines how many numbers are removed.\n\nQ: What are 'Games to Ad-free'?\nA: After playing a few games, ads will be disabled for a better experience as a thank you!"); }), _buildDrawerListItem(context, Icons.privacy_tip_outlined, 'Privacy Policy', () { _showContentDialog("Privacy Policy", "Sudoku World League collects minimal data. Your username and game scores are stored on Google Sheets for leaderboard functionality if you provide a username. Country selection is also stored for country-specific leaderboards. All other game data (history, settings) is stored locally on your device using SharedPreferences. We do not collect personal identification information beyond your chosen username for the leaderboard. The app uses simulated ads; no ad-tracking data is collected by this simulation."); }), _buildDrawerListItem(context, Icons.info_outline, 'About', () { _showContentDialog("About Sudoku World League", "Version: 1.2.1 (Cache Logic Refined)\n\nA classic Sudoku game with global and country-specific leaderboards.\n\nDeveloped with Flutter.\n\nEnjoy the challenge!"); }), ], ), ), ), );
  }

  Widget _buildDrawerListItem(BuildContext context, IconData icon, String title, VoidCallback onTap) {
    return ListTile( leading: Icon(icon, color: Theme.of(context).colorScheme.primary), title: Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)), onTap: () { Navigator.pop(context); onTap(); }, dense: true, );
  }

  Widget _buildTopInfoBar(ThemeData theme, double screenWidth) {
    final TextStyle topBarTextStyle = theme.textTheme.titleMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.bold) ?? const TextStyle(fontSize: 12, fontWeight: FontWeight.bold); return Card( elevation: 1, margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0), child: Padding( padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 6.0), child: SizedBox( height: 30.0, child: Row( children: [ Expanded( flex: 1, child: Row( mainAxisAlignment: MainAxisAlignment.center, children: [ Text("Difficulty:", style: topBarTextStyle), const SizedBox(width: 4), Flexible( child: SizedBox( width: screenWidth * 0.22, child: _buildDifficultySelector(theme), ), ), ], ), ), Expanded( flex: 1, child: Center( child: Text('Time: $_elapsedTime', style: topBarTextStyle, textAlign: TextAlign.center) ), ), ], ), ), ), );
  }

  Widget _buildNumberCompletionIndicator(ThemeData theme, double availableWidth) {
    if (_board.isEmpty && _numberCounts.isEmpty) { return const SizedBox.shrink(); } const double minGap = 2.0; double cellWidth = (availableWidth - (8 * minGap)) / 9; cellWidth = max(20.0, cellWidth); double cellHeight = cellWidth * 0.8; List<Widget> indicators = []; for (int i = 1; i <= 9; i++) { bool isComplete = (_numberCounts[i] ?? 0) >= 9; indicators.add( Container( width: cellWidth, height: cellHeight, margin: const EdgeInsets.symmetric(horizontal: minGap / 2), decoration: BoxDecoration( color: isComplete ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.primaryContainer.withOpacity(0.7), borderRadius: BorderRadius.circular(4), border: Border.all(color: theme.colorScheme.outlineVariant, width: 0.5), ), alignment: Alignment.center, child: Text( i.toString(), style: TextStyle( fontSize: cellWidth * 0.5, fontWeight: FontWeight.bold, color: isComplete ? theme.colorScheme.onSurfaceVariant.withOpacity(0.5) : theme.colorScheme.onPrimaryContainer, decoration: isComplete ? TextDecoration.lineThrough : null, decorationColor: isComplete ? theme.colorScheme.onSurfaceVariant.withOpacity(0.7) : null, ), ), ), ); } return Padding( padding: const EdgeInsets.only(top: 8.0, bottom: 8.0), child: Row( mainAxisAlignment: MainAxisAlignment.center, children: indicators, ), );
  }

  Widget _buildDifficultySelector(ThemeData theme) {
    final TextStyle dropdownTextStyle = Theme.of(context).textTheme.titleMedium?.copyWith( fontSize: 11, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.normal ) ?? const TextStyle(fontSize: 11); 
    return DropdownButtonHideUnderline( 
      child: DropdownButton<Difficulty>( 
        isExpanded: true, 
        value: _currentDifficulty, 
        dropdownColor: theme.colorScheme.surfaceContainerHigh, 
        icon: Icon(Icons.arrow_drop_down, color: theme.colorScheme.onSurfaceVariant, size: 20), 
        isDense: true, 
        style: dropdownTextStyle, 
        items: Difficulty.values.map((diff) { 
          return DropdownMenuItem( 
            value: diff, 
            child: Padding( 
              padding: const EdgeInsets.only(left: 4.0), 
              child: Text( 
                diff.toString().split('.').last.replaceAllMapped( RegExp(r'([A-Z])'), (match) => ' ${match.group(1)}').trim().capitalizeFirst(), 
                overflow: TextOverflow.ellipsis, 
                style: dropdownTextStyle, 
              ), 
            ), 
          ); 
        }).toList(), 
        onChanged: (Difficulty? newValue) { 
          if (newValue != null && newValue != _currentDifficulty) { 
            if (mounted) { 
              setState(() { _currentDifficulty = newValue; });
              _triggerNewGameSequence(); 
            } 
          } 
        }, 
      ), 
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final theme = Theme.of(context);
    final pickerSize = screenWidth * 0.7; 

    Widget mainContentColumn = Column(
      children: [
        _buildTopInfoBar(theme, screenWidth),
        Expanded(
          child: SingleChildScrollView( 
            child: Column(
              mainAxisSize: MainAxisSize.min, 
              children: [
                LeaderboardSectionWidget(
                  isLoadingLeaderboard: _isLoadingLeaderboard,
                  leaderboardData: _leaderboardData,
                  showGlobalLeaderboard: _showGlobalLeaderboard,
                  leaderboardDifficultyFilter: _leaderboardDifficultyFilter,
                  username: _username,
                  userRank: _userRank,
                  onSetLeaderboardType: _setLeaderboardType,
                  onDifficultyFilterChanged: (Difficulty? newValue) {
                    if (newValue != null && mounted && _leaderboardDifficultyFilter != newValue) {
                      setState(() { _leaderboardDifficultyFilter = newValue; });
                      _loadLeaderboardFromCacheOrApi(
                          difficultyToLoad: newValue,
                          typeToLoad: _showGlobalLeaderboard ? "global" : "country",
                          countryToLoad: _selectedCountry,
                          forceApi: false,
                          isInitialDisplay: false // Not initial when user changes filter
                      ); 
                    }
                  },
                  theme: theme,
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: SizedBox(
                    width: screenWidth * 0.95, 
                    child: AspectRatio(
                      aspectRatio: 1.0, 
                      child: SudokuGridWidget(
                        gridSize: screenWidth * 0.95,
                        board: _board,
                        selectedRow: _selectedRow,
                        selectedCol: _selectedCol,
                        theme: theme,
                        onCellSelected: _onCellSelected,
                      ),
                    ),
                  ),
                ),
                _buildNumberCompletionIndicator(theme, screenWidth * 0.95),
              ],
            ),
          ),
        ),
        if (_adsCurrentlyEnabled && _gamesToAdFree > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0, top: 8.0),
            child: Text('Games to Ad-free: $_gamesToAdFree',
                style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.normal)),
          ),
        if (_adsCurrentlyEnabled && _isBannerAdLoaded)
          Container(
            width: 320, 
            height: 50, 
            margin: const EdgeInsets.only(bottom: 4.0),
            color: Colors.grey[300],
            alignment: Alignment.center,
            child: Text("Simulated Banner Ad (320x50)",
                style: TextStyle(color: Colors.grey[700])),
          ),
      ],
    );

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Menu',
            onPressed: () {
              if (_scaffoldKey.currentState != null) {
                _scaffoldKey.currentState?.openDrawer();
              }
            }),
        title: const Text('Sudoku World League'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _triggerNewGameSequence,
              tooltip: 'New Game')
        ],
      ),
      drawer: _buildAppDrawer(context),
      body: SafeArea( 
        child: Stack( 
          children: [
            mainContentColumn,
            if (_showNumberPicker)
              Positioned.fill( 
                child: GestureDetector(
                  onTap: () => setState(() { _showNumberPicker = false; }), 
                  child: Container(
                    color: Colors.black.withOpacity(0.5), 
                    child: Center(
                        child: CircularNumberPicker(
                            size: pickerSize,
                            onNumberSelected: _onNumberPicked,
                            theme: theme)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}