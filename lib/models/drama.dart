import 'package:flutter/material.dart';
import '../services/app_settings.dart';

class DramaItem {
  final String id;
  final String title;
  final String posterUrl;
  final String watchUrl;
  final String? episodeCount;
  final String? description;
  final List<String> tags;
  final String? providerKey;

  DramaItem({
    required this.id,
    required String title,
    required this.posterUrl,
    required this.watchUrl,
    this.episodeCount,
    this.description,
    this.tags = const [],
    this.providerKey,
  }) : title = cleanTitle(title);

  static String cleanTitle(String raw) {
    var t = raw.replaceAll('&quot;', '"').replaceAll('&#39;', "'");
    // Replace bracketed and unbracketed sulih/silih suara / dubbing variants
    final pattern = RegExp(
      r'(?:[\(\[]\s*)?(?:di)?s[ui]lih\s*suara(?:kan)?(?:\s*[\)\]])?|(?:[\(\[]\s*)?dub(?:bing)?(?:\s*[\)\]])?',
      caseSensitive: false,
    );
    t = t.replaceAll(pattern, ' __SULIH__ ');
    t = t.replaceAll(RegExp(r'(\s*__SULIH__\s*)+'), ' __SULIH__ ');
    t = t.replaceAll('__SULIH__', '(Sulih Suara)');
    t = t.replaceAllMapped(
      RegExp(r'([^\s])\s*\((Sulih Suara)\)', caseSensitive: false),
      (m) => '${m[1]} (${m[2]})',
    );
    t = t.replaceAllMapped(
      RegExp(r'\((Sulih Suara)\)\s*([^\s])', caseSensitive: false),
      (m) => '(${m[1]}) ${m[2]}',
    );
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String get slug {
    final match = RegExp(r'/detail/watch/([^/?#]+)').firstMatch(watchUrl);
    if (match != null) return match.group(1)!;
    final match2 = RegExp(r'[?&]title=([^&]+)').firstMatch(watchUrl);
    if (match2 != null) {
      return Uri.decodeComponent(match2.group(1)!).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-');
    }
    return id;
  }

  String get historyKey {
    final s = slug;
    if (s.isNotEmpty) return s;
    if (id.isNotEmpty && id != '0') return id;
    return cleanTitle(title).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
  }

  static const List<String> knownProviders = [
    'anyreel', 'bibishort', 'bilitv', 'candyjar', 'cubetv', 'dotdrama', 'dotdrama2', 'dramabite',
    'dramabox', 'dramanova', 'dramashorts', 'dramatv', 'gorogoro', 'dramawave', 'dreameshort',
    'flareflow', 'flextv', 'flickreels', 'freedrama', 'freereels', 'fundrama', 'goodshort',
    'happyshort', 'idrama', 'joyreels', 'kalostv', 'melolo', 'microdrama', 'minishorts',
    'minutedrama', 'moboreels', 'moviebox', 'mydrama', 'myrelle', 'netshort', 'ohmytv',
    'pinedrama', 'playlet', 'rapidtv', 'rapidtv2', 'raptdrama', 'reelala', 'reelbuzz',
    'reelife', 'reelshort', 'sarostv', 'serealplus', 'shortical', 'shortmax', 'sixthshort',
    'stardusttv', 'starshort', 'storeel', 'storyreel', 'topdrama', 'velolo', 'vibeshort',
    'vigloo', 'vyntage'
  ];

  static String detectProvider({
    String? explicitProvider,
    String? providerKey,
    String? categoryName,
    String? sourceType,
    String? watchUrl,
    List<String>? tags,
    String? defaultProvider,
  }) {
    if (explicitProvider != null && explicitProvider.trim().isNotEmpty) {
      final p = explicitProvider.trim().toLowerCase();
      if (p != 'local' && p != 'narto' && p != 'all') {
        return explicitProvider.trim();
      }
    }
    if (providerKey != null && providerKey.trim().isNotEmpty) {
      final p = providerKey.trim().toLowerCase();
      if (p != 'local' && p != 'narto' && p != 'all') {
        return providerKey.trim();
      }
    }

    if (categoryName != null && categoryName.trim().isNotEmpty) {
      final cleanCat = categoryName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      for (final prov in knownProviders) {
        if (cleanCat.contains(prov)) {
          return prov;
        }
      }
      if (cleanCat != 'local' && cleanCat != 'narto' && cleanCat != 'all' && cleanCat.isNotEmpty) {
        return categoryName.trim();
      }
    }

    if (tags != null && tags.isNotEmpty) {
      for (final t in tags) {
        final cleanTag = t.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        for (final prov in knownProviders) {
          if (cleanTag.contains(prov)) {
            return prov;
          }
        }
      }
    }

    if (sourceType != null && sourceType.trim().isNotEmpty) {
      final st = sourceType.trim().toLowerCase();
      if (st != 'local' && st != 'narto' && st != 'all') {
        return sourceType.trim();
      }
    }

    if (watchUrl != null && watchUrl.isNotEmpty) {
      final cleanUrl = watchUrl.toLowerCase();
      for (final prov in knownProviders) {
        if (cleanUrl.contains('provider=$prov') ||
            cleanUrl.contains('/$prov/') ||
            cleanUrl.contains('-$prov-') ||
            cleanUrl.contains('$prov-stream') ||
            cleanUrl.contains('asset.$prov')) {
          return prov;
        }
      }
    }

    if (defaultProvider != null && defaultProvider.trim().isNotEmpty) {
      final dp = defaultProvider.trim().toLowerCase();
      if (dp != 'all' && dp != 'narto' && dp != 'general' && dp != 'local') {
        return defaultProvider.trim();
      }
    }

    return '';
  }

  String get displayProvider {
    if (providerKey != null &&
        providerKey!.trim().isNotEmpty &&
        providerKey!.trim().toLowerCase() != 'narto' &&
        providerKey!.trim().toLowerCase() != 'local') {
      return providerKey!.trim().toUpperCase();
    }
    final detected = detectProvider(watchUrl: watchUrl, tags: tags);
    if (detected.isNotEmpty && detected.toLowerCase() != 'narto' && detected.toLowerCase() != 'local') {
      return detected.toUpperCase();
    }
    return '';
  }

  factory DramaItem.fromJson(Map<String, dynamic> json, {String? defaultProvider}) {
    final idVal = json['id']?.toString() ?? json['book_id']?.toString() ?? '';
    final rawTitle = json['title']?.toString() ?? '';
    final titleVal = cleanTitle(rawTitle);
    
    // Poster URL normalization
    var posterVal = json['poster_url']?.toString() ??
        json['cover']?.toString() ??
        json['thumb']?.toString() ??
        '';
    if (posterVal.startsWith('/')) {
      posterVal = '${AppSettings.baseUrl}$posterVal';
    }

    // Watch URL normalization
    var urlVal = json['url']?.toString() ?? json['watch_url']?.toString() ?? '';
    if (urlVal.startsWith('/')) {
      urlVal = '${AppSettings.baseUrl}$urlVal';
    }

    final rawTags = json['tags'] ?? json['tag_names'];
    List<String> tagsList = [];
    if (rawTags is List) {
      tagsList = rawTags.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }

    final catVal = json['category_name']?.toString() ?? json['category']?.toString();

    final epCount = json['episode_count']?.toString() ??
        json['chapter_count']?.toString() ??
        json['total_episodes']?.toString();

    final descVal = json['description']?.toString() ??
        json['intro']?.toString() ??
        json['summary']?.toString();

    final detectedProv = detectProvider(
      explicitProvider: json['provider']?.toString(),
      providerKey: json['provider_key']?.toString(),
      categoryName: catVal,
      sourceType: json['source_type']?.toString(),
      watchUrl: urlVal,
      tags: tagsList,
      defaultProvider: defaultProvider,
    );

    return DramaItem(
      id: idVal,
      title: titleVal,
      posterUrl: posterVal,
      watchUrl: urlVal,
      episodeCount: epCount,
      description: descVal,
      tags: tagsList,
      providerKey: detectedProv,
    );
  }
}

class SubtitleTrack {
  final String languageCode;
  final String label;
  final String subtitleUrl;
  final bool isDefault;

  const SubtitleTrack({
    required this.languageCode,
    required this.label,
    required this.subtitleUrl,
    this.isDefault = false,
  });

  factory SubtitleTrack.fromJson(Map<String, dynamic> json) {
    String cleanUrl(dynamic val) {
      if (val == null) return '';
      return val.toString().replaceAll(r'\/', '/').replaceAll(r'\\', '').trim();
    }
    return SubtitleTrack(
      languageCode: json['language_code']?.toString() ?? '',
      label: json['label']?.toString() ?? json['language_code']?.toString() ?? 'Subtitle',
      subtitleUrl: cleanUrl(json['subtitle_url']),
      isDefault: json['is_default'] == true,
    );
  }
}

class SubtitleCue {
  final Duration start;
  final Duration end;
  final String text;

  const SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });
}

class EpisodeItem {
  final int id;
  final int number;
  final String title;
  final String playUrl;
  final String directPlayUrl;
  final String thumbUrl;
  final String watchUrl;
  final String subtitleUrl;
  final String directSubtitleUrl;
  final List<SubtitleTrack> multiSubtitles;

  const EpisodeItem({
    required this.id,
    required this.number,
    required this.title,
    required this.playUrl,
    required this.directPlayUrl,
    required this.thumbUrl,
    required this.watchUrl,
    this.subtitleUrl = '',
    this.directSubtitleUrl = '',
    this.multiSubtitles = const [],
  });

  factory EpisodeItem.fromJson(Map<String, dynamic> json) {
    String cleanUrl(dynamic val) {
      if (val == null) return '';
      return val.toString().replaceAll(r'\/', '/').replaceAll(r'\\', '').trim();
    }

    final play = cleanUrl(json['play_url']);
    final direct = cleanUrl(json['direct_play_url']);
    final rawSubs = json['multi_subtitles'];
    List<SubtitleTrack> subs = [];
    if (rawSubs is List) {
      subs = rawSubs
          .whereType<Map<String, dynamic>>()
          .map((s) => SubtitleTrack.fromJson(s))
          .toList();
    }

    return EpisodeItem(
      id: json['id'] is int ? json['id'] as int : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      number: json['number'] is int ? json['number'] as int : int.tryParse(json['number']?.toString() ?? '0') ?? 0,
      title: json['title']?.toString() ?? 'Episode',
      playUrl: play,
      directPlayUrl: direct.isNotEmpty ? direct : play,
      thumbUrl: cleanUrl(json['thumb_url']),
      watchUrl: cleanUrl(json['watch_url']),
      subtitleUrl: cleanUrl(json['subtitle_url']),
      directSubtitleUrl: cleanUrl(json['direct_subtitle_url']),
      multiSubtitles: subs,
    );
  }

  String get effectiveStreamUrl {
    if (directPlayUrl.isNotEmpty && directPlayUrl.startsWith('http')) {
      return directPlayUrl;
    }
    return playUrl;
  }

  String get effectiveSubtitleUrl {
    if (multiSubtitles.isNotEmpty) {
      final idTrack = multiSubtitles.firstWhere(
        (t) => t.languageCode.toLowerCase().startsWith('id'),
        orElse: () => multiSubtitles.firstWhere(
          (t) => t.isDefault,
          orElse: () => multiSubtitles.first,
        ),
      );
      if (idTrack.subtitleUrl.isNotEmpty) {
        return idTrack.subtitleUrl;
      }
    }
    if (subtitleUrl.isNotEmpty) return subtitleUrl;
    if (directSubtitleUrl.isNotEmpty) return directSubtitleUrl;
    return '';
  }

  String get slug {
    final match = RegExp(r'/detail/watch/([^/?#]+)').firstMatch(watchUrl);
    return match?.group(1) ?? '';
  }
}

class ProviderInfo {
  final String key;
  final String label;
  final int dramaCount;
  final String labelWithCount;
  final int? latencyMs;
  final bool isOnline;

  const ProviderInfo({
    required this.key,
    required this.label,
    this.dramaCount = 0,
    String? labelWithCount,
    this.latencyMs,
    this.isOnline = true,
  }) : labelWithCount = labelWithCount ?? (dramaCount > 0 ? '$label ($dramaCount)' : label);

  ProviderInfo copyWith({
    String? key,
    String? label,
    int? dramaCount,
    String? labelWithCount,
    int? latencyMs,
    bool? isOnline,
  }) {
    return ProviderInfo(
      key: key ?? this.key,
      label: label ?? this.label,
      dramaCount: dramaCount ?? this.dramaCount,
      labelWithCount: labelWithCount ?? this.labelWithCount,
      latencyMs: latencyMs ?? this.latencyMs,
      isOnline: isOnline ?? this.isOnline,
    );
  }

  Color get statusColor {
    if (!isOnline && latencyMs != null) return const Color(0xFFEF4444);
    if (latencyMs == null) return const Color(0xFF64748B);
    if (latencyMs! < 600) return const Color(0xFF10B981);
    if (latencyMs! < 1500) return const Color(0xFFF59E0B);
    return const Color(0xFFF97316);
  }

  String get speedTag {
    if (!isOnline && latencyMs != null) return 'Gangguan';
    if (latencyMs == null) return 'Belum Diuji';
    if (latencyMs! < 600) return 'Cepat';
    if (latencyMs! < 1500) return 'Normal';
    return 'Lelet';
  }

  String get statusLabel {
    if (!isOnline && latencyMs != null) return 'Gangguan';
    if (latencyMs == null) return 'Belum Diuji';
    if (latencyMs! < 600) return '${latencyMs}ms Cepat';
    if (latencyMs! < 1500) return '${latencyMs}ms Normal';
    return '${latencyMs}ms Lelet';
  }

  bool get isFastOrNormal => isOnline && (latencyMs == null || latencyMs! < 1500);

  factory ProviderInfo.fromJson(Map<String, dynamic> json) {
    final keyVal = json['key']?.toString() ?? '';
    final labelVal = json['label']?.toString() ?? keyVal;
    final count = json['drama_count'] is int
        ? json['drama_count'] as int
        : (int.tryParse(json['drama_count']?.toString() ?? '0') ?? 0);
    final lwc = json['label_with_count']?.toString() ?? (count > 0 ? '$labelVal ($count)' : labelVal);
    final latency = json['latency_ms'] is int
        ? json['latency_ms'] as int
        : int.tryParse(json['latency_ms']?.toString() ?? '');
    final online = json['is_online'] is bool
        ? json['is_online'] as bool
        : (json['is_online']?.toString() != 'false');
    return ProviderInfo(
      key: keyVal,
      label: labelVal,
      dramaCount: count,
      labelWithCount: lwc,
      latencyMs: latency,
      isOnline: online,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'label': label,
      'drama_count': dramaCount,
      'label_with_count': labelWithCount,
      'latency_ms': latencyMs,
      'is_online': isOnline,
    };
  }
}

class DramaDetail {
  final String id;
  final int? movieId;
  final String title;
  final String posterUrl;
  final String? description;
  final String? providerName;
  final String? slug;
  final List<EpisodeItem> episodes;

  DramaDetail({
    required this.id,
    this.movieId,
    required String title,
    required this.posterUrl,
    this.description,
    this.providerName,
    this.slug,
    required this.episodes,
  }) : title = DramaItem.cleanTitle(title);

  int get effectiveMovieId {
    if (movieId != null && movieId! > 0) return movieId!;
    final parsed = int.tryParse(id);
    if (parsed != null && parsed > 0) return parsed;
    return 0;
  }

  String get historyKey {
    if (slug != null && slug!.isNotEmpty) return slug!;
    if (id.isNotEmpty && id != '0') return id;
    return DramaItem.cleanTitle(title).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
  }

  DramaDetail copyWith({
    String? id,
    int? movieId,
    String? title,
    String? posterUrl,
    String? description,
    String? providerName,
    String? slug,
    List<EpisodeItem>? episodes,
  }) {
    return DramaDetail(
      id: id ?? this.id,
      movieId: movieId ?? this.movieId,
      title: title ?? this.title,
      posterUrl: posterUrl ?? this.posterUrl,
      description: description ?? this.description,
      providerName: providerName ?? this.providerName,
      slug: slug ?? this.slug,
      episodes: episodes ?? this.episodes,
    );
  }
}
