import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/drama.dart';

class HistoryItem {
  final String key;
  final String id;
  final int? movieId;
  final String title;
  final String posterUrl;
  final String watchUrl;
  final String provider;
  final int lastEpisodeIndex;
  final int totalEpisodes;
  final int updatedAt; // ms timestamp

  HistoryItem({
    required this.key,
    required this.id,
    this.movieId,
    required this.title,
    required this.posterUrl,
    required this.watchUrl,
    required this.provider,
    required this.lastEpisodeIndex,
    required this.totalEpisodes,
    required this.updatedAt,
  });

  int get effectiveMovieId {
    if (movieId != null && movieId! > 0) return movieId!;
    final parsed = int.tryParse(id);
    if (parsed != null && parsed > 0) return parsed;
    return 0;
  }

  DramaItem toDramaItem() {
    final effectiveProv = (provider.isNotEmpty &&
            provider.toLowerCase() != 'narto' &&
            provider.toLowerCase() != 'local')
        ? provider
        : DramaItem.detectProvider(watchUrl: watchUrl);
    return DramaItem(
      id: id.isNotEmpty ? id : key,
      title: title,
      posterUrl: posterUrl,
      watchUrl: watchUrl.isNotEmpty ? watchUrl : '/detail/watch/$key/1',
      providerKey: (effectiveProv.isNotEmpty && effectiveProv.toLowerCase() != 'narto') ? effectiveProv : null,
      episodeCount: totalEpisodes > 0 ? '$totalEpisodes' : null,
    );
  }

  Map<String, dynamic> toNartoSyncPayload() {
    return {
      'movie_id': effectiveMovieId,
      'movie_title': title,
      'watch_url': watchUrl,
      'movie_language': 'id-ID',
      'movie_poster': posterUrl,
      'movie_share_image_url': posterUrl,
      'episode_number': lastEpisodeIndex + 1,
      'single_full': 0,
      'updated_at': (updatedAt / 1000).round(),
    };
  }

  factory HistoryItem.fromNartoSyncPayload(Map<String, dynamic> json) {
    final mId = json['movie_id'] is int
        ? json['movie_id'] as int
        : (int.tryParse(json['movie_id']?.toString() ?? '0') ?? 0);
    final epNum = json['episode_number'] is int
        ? json['episode_number'] as int
        : (int.tryParse(json['episode_number']?.toString() ?? '1') ?? 1);
    final updatedAtSec = json['updated_at'] is int
        ? json['updated_at'] as int
        : (int.tryParse(json['updated_at']?.toString() ?? '0') ?? 0);
    final watchUrl = json['watch_url']?.toString() ?? '';
    final slugMatch = RegExp(r'/detail/watch/([^/?]+)').firstMatch(watchUrl);
    final key = slugMatch != null ? slugMatch.group(1)! : (mId > 0 ? '$mId' : 'drama_$mId');

    return HistoryItem(
      key: key,
      id: mId > 0 ? '$mId' : key,
      movieId: mId > 0 ? mId : null,
      title: json['movie_title']?.toString() ?? 'Drama',
      posterUrl: json['movie_poster']?.toString() ?? (json['movie_share_image_url']?.toString() ?? ''),
      watchUrl: watchUrl,
      provider: '',
      lastEpisodeIndex: epNum > 0 ? epNum - 1 : 0,
      totalEpisodes: epNum,
      updatedAt: updatedAtSec > 0 ? (updatedAtSec * 1000) : DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'id': id,
    'movieId': movieId,
    'title': title,
    'posterUrl': posterUrl,
    'watchUrl': watchUrl,
    'provider': provider,
    'lastEpisodeIndex': lastEpisodeIndex,
    'totalEpisodes': totalEpisodes,
    'updatedAt': updatedAt,
  };

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
    key: json['key']?.toString() ?? '',
    id: json['id']?.toString() ?? '',
    movieId: json['movieId'] is int
        ? json['movieId'] as int
        : int.tryParse(json['movieId']?.toString() ?? '0'),
    title: json['title']?.toString() ?? '',
    posterUrl: json['posterUrl']?.toString() ?? '',
    watchUrl: json['watchUrl']?.toString() ?? '',
    provider: json['provider']?.toString() ?? '',
    lastEpisodeIndex: json['lastEpisodeIndex'] is int
        ? json['lastEpisodeIndex'] as int
        : (int.tryParse(json['lastEpisodeIndex']?.toString() ?? '0') ?? 0),
    totalEpisodes: json['totalEpisodes'] is int
        ? json['totalEpisodes'] as int
        : (int.tryParse(json['totalEpisodes']?.toString() ?? '0') ?? 0),
    updatedAt: json['updatedAt'] is int
        ? json['updatedAt'] as int
        : (int.tryParse(json['updatedAt']?.toString() ?? '0') ?? 0),
  );
}

class BookmarkItem {
  final String key;
  final String id;
  final String title;
  final String posterUrl;
  final String watchUrl;
  final String provider;
  final int totalEpisodes;
  final int createdAt; // ms timestamp

  BookmarkItem({
    required this.key,
    required this.id,
    required this.title,
    required this.posterUrl,
    required this.watchUrl,
    required this.provider,
    required this.totalEpisodes,
    required this.createdAt,
  });

  DramaItem toDramaItem() {
    final effectiveProv = (provider.isNotEmpty &&
            provider.toLowerCase() != 'narto' &&
            provider.toLowerCase() != 'local')
        ? provider
        : DramaItem.detectProvider(watchUrl: watchUrl);
    return DramaItem(
      id: id.isNotEmpty ? id : key,
      title: title,
      posterUrl: posterUrl,
      watchUrl: watchUrl.isNotEmpty ? watchUrl : '/detail/watch/$key/1',
      providerKey: (effectiveProv.isNotEmpty && effectiveProv.toLowerCase() != 'narto') ? effectiveProv : null,
      episodeCount: totalEpisodes > 0 ? '$totalEpisodes' : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'id': id,
    'title': title,
    'posterUrl': posterUrl,
    'watchUrl': watchUrl,
    'provider': provider,
    'totalEpisodes': totalEpisodes,
    'createdAt': createdAt,
  };

  factory BookmarkItem.fromJson(Map<String, dynamic> json) => BookmarkItem(
    key: json['key']?.toString() ?? '',
    id: json['id']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    posterUrl: json['posterUrl']?.toString() ?? '',
    watchUrl: json['watchUrl']?.toString() ?? '',
    provider: json['provider']?.toString() ?? '',
    totalEpisodes: json['totalEpisodes'] is int
        ? json['totalEpisodes'] as int
        : (int.tryParse(json['totalEpisodes']?.toString() ?? '0') ?? 0),
    createdAt: json['createdAt'] is int
        ? json['createdAt'] as int
        : (int.tryParse(json['createdAt']?.toString() ?? '0') ?? 0),
  );
}

class HistoryBookmarkService {
  static const String _historyKey = 'narto_user_history_v1';
  static const String _bookmarksKey = 'narto_user_bookmarks_v1';

  static Future<int> getHistoryCount() async {
    final list = await getHistory();
    return list.length;
  }

  static Future<int> getBookmarkCount() async {
    final list = await getBookmarks();
    return list.length;
  }

  // --- HISTORY ---
  static Future<List<HistoryItem>> getHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var raw = prefs.getString(_historyKey);
      
      // Fallback/migration for legacy keys if _historyKey is empty
      if (raw == null || raw.isEmpty) {
        final legacyString = prefs.getString('user_history') ?? prefs.getString('narto_history');
        if (legacyString != null && legacyString.isNotEmpty) {
          raw = legacyString;
          await prefs.setString(_historyKey, legacyString);
        }
      }

      if (raw == null || raw.isEmpty) return [];
      final List decoded = jsonDecode(raw) as List;
      final list = decoded.map((e) => HistoryItem.fromJson(e as Map<String, dynamic>)).toList();
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveHistory({
    required String dramaKey,
    required String dramaId,
    int? movieId,
    required String title,
    required String posterUrl,
    required String watchUrl,
    required String provider,
    required int episodeIndex,
    required int totalEpisodes,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Legacy keys compatibility for DetailScreen / PlayerScreen
      await prefs.setInt('last_ep_$dramaKey', episodeIndex);
      await prefs.setString('last_title_$dramaKey', title);
      if (dramaId.isNotEmpty && dramaId != '0') {
        await prefs.setInt('last_ep_$dramaId', episodeIndex);
      }
      final prevMax = prefs.getInt('max_ep_$dramaKey') ?? -1;
      if (episodeIndex > prevMax) {
        await prefs.setInt('max_ep_$dramaKey', episodeIndex);
        if (dramaId.isNotEmpty && dramaId != '0') {
          await prefs.setInt('max_ep_$dramaId', episodeIndex);
        }
      }

      // JSON history list: deduplicate safely without wiping entries with blank/0 ids
      final list = await getHistory();
      list.removeWhere((item) =>
          (item.key.isNotEmpty && item.key == dramaKey) ||
          (dramaId.isNotEmpty && dramaId != '0' && item.id.isNotEmpty && item.id != '0' && item.id == dramaId));

      final newItem = HistoryItem(
        key: dramaKey,
        id: dramaId,
        movieId: movieId,
        title: title,
        posterUrl: posterUrl,
        watchUrl: watchUrl,
        provider: provider,
        lastEpisodeIndex: episodeIndex,
        totalEpisodes: totalEpisodes,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      list.insert(0, newItem);
      // Keep up to 1000 items so user history never gets trimmed or lost
      if (list.length > 1000) list.removeRange(1000, list.length);

      final encoded = jsonEncode(list.map((e) => e.toJson()).toList());
      await prefs.setString(_historyKey, encoded);
    } catch (_) {}
  }

  static Future<void> removeHistory(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = await getHistory();
      list.removeWhere((item) =>
          (item.key.isNotEmpty && item.key == key) ||
          (item.id.isNotEmpty && item.id != '0' && item.id == key));
      final encoded = jsonEncode(list.map((e) => e.toJson()).toList());
      await prefs.setString(_historyKey, encoded);
    } catch (_) {}
  }

  static Future<void> clearAllHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_historyKey);
      final keys = prefs.getKeys().where((k) => k.startsWith('last_ep_') || k.startsWith('max_ep_')).toList();
      for (final k in keys) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }

  // --- BOOKMARKS ---
  static Future<List<BookmarkItem>> getBookmarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var raw = prefs.getString(_bookmarksKey);

      // Fallback/migration for legacy keys if _bookmarksKey is empty
      if (raw == null || raw.isEmpty) {
        final legacyString = prefs.getString('user_bookmarks') ?? prefs.getString('bookmarks');
        if (legacyString != null && legacyString.isNotEmpty) {
          raw = legacyString;
          await prefs.setString(_bookmarksKey, legacyString);
        }
      }

      if (raw == null || raw.isEmpty) return [];
      final List decoded = jsonDecode(raw) as List;
      final list = decoded.map((e) => BookmarkItem.fromJson(e as Map<String, dynamic>)).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<bool> isBookmarked(String key) async {
    try {
      final list = await getBookmarks();
      return list.any((item) =>
          (item.key.isNotEmpty && item.key == key) ||
          (item.id.isNotEmpty && item.id != '0' && item.id == key));
    } catch (_) {
      return false;
    }
  }

  static Future<bool> toggleBookmark({
    required String dramaKey,
    required String dramaId,
    required String title,
    required String posterUrl,
    required String watchUrl,
    required String provider,
    required int totalEpisodes,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = await getBookmarks();
      final existingIndex = list.indexWhere((item) =>
          (item.key.isNotEmpty && item.key == dramaKey) ||
          (dramaId.isNotEmpty && dramaId != '0' && item.id.isNotEmpty && item.id != '0' && item.id == dramaId));

      if (existingIndex >= 0) {
        // Remove
        list.removeAt(existingIndex);
        await prefs.setString(_bookmarksKey, jsonEncode(list.map((e) => e.toJson()).toList()));
        return false;
      } else {
        // Add
        final item = BookmarkItem(
          key: dramaKey,
          id: dramaId,
          title: title,
          posterUrl: posterUrl,
          watchUrl: watchUrl,
          provider: provider,
          totalEpisodes: totalEpisodes,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );
        list.insert(0, item);
        await prefs.setString(_bookmarksKey, jsonEncode(list.map((e) => e.toJson()).toList()));
        return true;
      }
    } catch (_) {
      return false;
    }
  }

  static Future<void> removeBookmark(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = await getBookmarks();
      list.removeWhere((item) =>
          (item.key.isNotEmpty && item.key == key) ||
          (item.id.isNotEmpty && item.id != '0' && item.id == key));
      await prefs.setString(_bookmarksKey, jsonEncode(list.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  static Future<void> clearAllBookmarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_bookmarksKey);
    } catch (_) {}
  }
}
