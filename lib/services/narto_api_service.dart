import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import '../models/drama.dart';
import '../models/provider_section.dart';
import 'app_settings.dart';

class CatalogPageResult {
  final List<DramaItem> items;
  final int currentPage;
  final int totalPages;
  final bool hasPrev;
  final bool hasNext;
  final String pagerText;

  const CatalogPageResult({
    required this.items,
    required this.currentPage,
    required this.totalPages,
    required this.hasPrev,
    required this.hasNext,
    required this.pagerText,
  });
}

class NartoApiService {
  static String get baseUrl => AppSettings.baseUrl;
  static bool get isProxyMode => AppSettings.isProxyMode;

  static String _generateNdCk() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final part1 = nowMs.toRadixString(36);
    const chars = '0123456789abcdefghijklmnopqrstuvwxyz';
    final rand = math.Random();
    final part2 = List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
    return '$part1$part2';
  }

  static String _cachedNdCk = '';
  static String get defaultCookie {
    if (_cachedNdCk.isEmpty) {
      _cachedNdCk = 'nd_ck=${_generateNdCk()}';
    }
    return _cachedNdCk;
  }

  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

  static Map<String, String> get _defaultHeaders {
    final headers = <String, String>{
      'User-Agent': userAgent,
      'Referer': 'https://narto-drama.com/',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,application/json,*/*;q=0.8',
    };
    if (AppSettings.customCookie != null && AppSettings.customCookie!.trim().isNotEmpty) {
      headers['Cookie'] = AppSettings.customCookie!.trim();
    }
    return headers;
  }

  static final Map<String, Map<String, String>> _dramaEdgeCache = {};

  /// Search dramas by keyword
  static Future<List<DramaItem>> search(String query, {String lang = 'id-ID'}) async {
    if (query.trim().isEmpty) return [];

    try {
      final endpoint = isProxyMode
          ? '$baseUrl/api/search?q=${Uri.encodeComponent(query)}&limit=50&lang=$lang'
          : '$baseUrl/search?q=${Uri.encodeComponent(query)}&limit=50&lang=$lang';

      final headers = Map<String, String>.from(_defaultHeaders);
      headers['X-Requested-With'] = 'XMLHttpRequest';

      final response = await http.get(Uri.parse(endpoint), headers: headers);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data['items'] is List) {
          final items = data['items'] as List;
          return items
              .whereType<Map<String, dynamic>>()
              .map((json) => DramaItem.fromJson(json))
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// Fetch General Catalog with Pagination
  static Future<CatalogPageResult> fetchGeneralCatalog({int page = 1, bool forceRefresh = false, String lang = 'id-ID'}) async {
    final safePage = page < 1 ? 1 : page;

    if (isProxyMode) {
      try {
        final uri = Uri.parse('$baseUrl/api/general?page=$safePage${forceRefresh ? '&refresh=true' : ''}');
        final res = await http.get(uri, headers: _defaultHeaders).timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          if (data is Map && data['ok'] == true) {
            final rawItems = data['items'] as List? ?? [];
            final items = rawItems
                .whereType<Map<String, dynamic>>()
                .map((j) => DramaItem.fromJson(j))
                .toList();

            return CatalogPageResult(
              items: items,
              currentPage: data['page'] is int ? data['page'] : safePage,
              totalPages: data['total_pages'] is int ? data['total_pages'] : 5,
              hasPrev: data['has_prev'] == true,
              hasNext: data['has_next'] == true,
              pagerText: data['pager_text']?.toString() ?? 'Halaman $safePage',
            );
          }
        }
      } catch (_) {}
    }

    // Fallback: Direct Upstream scraping
    try {
      final uri = Uri.parse('$baseUrl/?lang=$lang&page=$safePage');
      final res = await http.get(uri, headers: _defaultHeaders).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final html = res.body;

        final articlePattern = RegExp(
          r'''<article[^>]*class=["\'][^"\']*card[^"\']*["\'][^>]*>([\s\S]*?)</article>''',
          caseSensitive: false,
        );

        final matches = articlePattern.allMatches(html);
        final List<DramaItem> items = [];
        final Set<String> seenUrls = {};

        for (final m in matches) {
          final art = m.group(0) ?? '';
          final titleMatch = RegExp(r'''data-movie-title=["\'](.*?)["\']''').firstMatch(art) ??
              RegExp(r'''alt=["\'](.*?)["\']''').firstMatch(art);
          final urlMatch = RegExp(r'''data-watch-url=["\'](.*?)["\']''').firstMatch(art) ??
              RegExp(r'''href=["\']([^"\']*?/detail/watch/[^"\']*)["\']''').firstMatch(art);
          final imgMatch = RegExp(r'''(?:data-src|src)=["\']([^"\']+\.(?:jpg|png|webp|jpeg)[^"\']*)["\']''').firstMatch(art);
          final epMatch = RegExp(r'''class=["\']episode-badge["\'][^>]*>(.*?)</div>''').firstMatch(art);

          var title = titleMatch?.group(1)?.replaceAll('&quot;', '"').replaceAll('&#39;', "'").trim() ?? '';
          if (title.startsWith('"') && title.endsWith('"') && title.length > 2) {
            title = title.substring(1, title.length - 1);
          }
          var watchUrl = urlMatch?.group(1)?.trim() ?? '';
          if (watchUrl.startsWith('/')) watchUrl = '$baseUrl$watchUrl';
          if (watchUrl.isEmpty || seenUrls.contains(watchUrl)) continue;
          seenUrls.add(watchUrl);

          var poster = imgMatch?.group(1)?.trim() ?? '';
          if (poster.startsWith('/')) poster = '$baseUrl$poster';
          final epText = epMatch?.group(1)?.replaceAll(RegExp(r'<[^>]*>'), '').trim();

          items.add(DramaItem(
            id: watchUrl.hashCode.abs().toString(),
            title: title.isEmpty ? 'Short Drama' : title,
            posterUrl: poster,
            watchUrl: watchUrl,
            episodeCount: epText,
            providerKey: DramaItem.detectProvider(watchUrl: watchUrl),
          ));
        }

        // Parse Pager Information
        final pagerMatch = RegExp(r'''class=["\']pager-text["\'][^>]*>(.*?)</span>''').firstMatch(html);
        final pagerText = pagerMatch?.group(1)?.trim() ?? 'Halaman $safePage';

        int totalPages = safePage;
        final totalPagesMatch = RegExp(r'''Halaman\s+(\d+)\s+dari\s+(\d+)''').firstMatch(pagerText);
        if (totalPagesMatch != null) {
          totalPages = int.tryParse(totalPagesMatch.group(2) ?? '') ?? safePage;
        }

        final hasNext = html.contains('Next') && !RegExp(r'''<span[^>]*class=["\'][^"\']*disabled[^"\']*["\'][^>]*>\s*Next''').hasMatch(html);
        final hasPrev = html.contains('Prev') && !RegExp(r'''<span[^>]*class=["\'][^"\']*disabled[^"\']*["\'][^>]*>\s*Prev''').hasMatch(html);

        return CatalogPageResult(
          items: items,
          currentPage: safePage,
          totalPages: totalPages > safePage ? totalPages : (hasNext ? safePage + 1 : safePage),
          hasPrev: hasPrev,
          hasNext: hasNext,
          pagerText: pagerText,
        );
      }
    } catch (_) {}

    return CatalogPageResult(
      items: [],
      currentPage: safePage,
      totalPages: 1,
      hasPrev: safePage > 1,
      hasNext: false,
      pagerText: 'Halaman $safePage',
    );
  }

  /// Fetch providers and sections
  static Future<Map<String, dynamic>> fetchProviderSections({
    String provider = 'melolo',
    String lang = 'id-ID',
    String? onlyTab,
    int page = 1,
  }) async {
    try {
      final endpoint = isProxyMode
          ? (onlyTab != null
              ? '$baseUrl/api/sections?provider=$provider&lang=$lang&only_tab=$onlyTab&page=$page'
              : '$baseUrl/api/sections?provider=$provider&lang=$lang')
          : (onlyTab != null
              ? '$baseUrl/home/providers/sections?provider=$provider&lang=$lang&only_tab=$onlyTab&tab_pages[$onlyTab]=$page'
              : '$baseUrl/home/providers/sections?provider=$provider&lang=$lang');

      final headers = Map<String, String>.from(_defaultHeaders);
      headers['X-Requested-With'] = 'XMLHttpRequest';

      final response = await http.get(Uri.parse(endpoint), headers: headers).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data['ok'] == true) {
          final rawProviders = data['providers'];
          List<ProviderInfo> providersList = [];
          if (rawProviders is List) {
            for (final p in rawProviders) {
              if (p is Map<String, dynamic>) {
                final key = p['key']?.toString() ?? '';
                final label = p['label']?.toString() ?? key;
                final cachedCount = AppSettings.getDramaCount(key);
                final dramaCount = p['drama_count'] is int ? p['drama_count'] as int : cachedCount;
                final labelWithCount = dramaCount > 0 ? '$label ($dramaCount)' : label;

                providersList.add(ProviderInfo(
                  key: key,
                  label: label,
                  dramaCount: dramaCount,
                  labelWithCount: labelWithCount,
                ));
              }
            }
            providersList.sort((a, b) => b.dramaCount.compareTo(a.dramaCount));
          }

          final rawSections = data['sections'];
          List<ProviderSection> sectionsList = [];
          if (rawSections is List) {
            sectionsList = rawSections
                .whereType<Map<String, dynamic>>()
                .map((s) => ProviderSection.fromJson(s, providerKey: provider))
                .toList();
          }

          if (providersList.isEmpty) {
            providersList = AppSettings.allProviders;
          }

          return {
            'providers': providersList,
            'sections': sectionsList,
            'active_provider': data['active_provider']?.toString() ?? provider,
          };
        }
      }
    } catch (_) {}
    return {'providers': <ProviderInfo>[], 'sections': <ProviderSection>[]};
  }

  /// Audit all providers manually and update cached counts
  static Future<Map<String, int>> auditAllProviders({
    required List<String> providerKeys,
    Function(int current, int total, String name, int count)? onProgress,
  }) async {
    final Map<String, int> counts = {};
    for (int i = 0; i < providerKeys.length; i++) {
      final key = providerKeys[i];
      try {
        final res = await fetchProviderSections(provider: key);
        final sections = res['sections'] as List<ProviderSection>? ?? [];
        int total = 0;
        for (final sec in sections) {
          total += sec.items.length;
        }
        counts[key.toLowerCase()] = total;
        if (onProgress != null) {
          onProgress(i + 1, providerKeys.length, key, total);
        }
      } catch (_) {
        counts[key.toLowerCase()] = 0;
      }
    }
    await AppSettings.saveProviderCounts(counts);
    return counts;
  }

  /// Fetch drama details and episodes from watch page
  static Future<DramaDetail?> fetchDramaDetail(String watchUrl, {String lang = 'id-ID'}) async {
    try {
      if (isProxyMode) {
        final uri = Uri.parse('$baseUrl/api/episodes?watch_url=${Uri.encodeComponent(watchUrl)}');
        final res = await http.get(uri, headers: _defaultHeaders).timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          if (data is Map && data['ok'] == true) {
            final rawEps = data['episodes'] as List? ?? [];
            final episodes = rawEps
                .whereType<Map<String, dynamic>>()
                .map((e) => EpisodeItem.fromJson(e))
                .toList();

            return DramaDetail(
              id: data['movie_id']?.toString() ?? '0',
              title: data['title']?.toString() ?? 'Drama',
              posterUrl: data['poster_url']?.toString() ?? '',
              description: data['description']?.toString(),
              providerName: data['provider']?.toString(),
              slug: data['slug']?.toString() ?? RegExp(r'/detail/watch/([^/?#]+)').firstMatch(watchUrl)?.group(1),
              episodes: episodes,
            );
          }
        }
      }

      var targetUrl = watchUrl.replaceAll('&amp;', '&').trim();
      if (!targetUrl.startsWith('http')) {
        targetUrl = '$baseUrl$targetUrl';
      }

      final client = http.Client();
      String finalUrl = targetUrl;

      // Handle search/import redirect to obtain exact detail/watch/{slug}
      if (finalUrl.contains('/search/import')) {
        try {
          final req = http.Request('GET', Uri.parse(finalUrl))
            ..followRedirects = false
            ..headers.addAll(_defaultHeaders);
          final streamed = await client.send(req);
          if (streamed.isRedirect || streamed.statusCode == 301 || streamed.statusCode == 302) {
            final loc = streamed.headers['location'];
            if (loc != null && loc.isNotEmpty) {
              finalUrl = loc.startsWith('http') ? loc : '$baseUrl$loc';
            }
          }
        } catch (_) {}
      }

      // Ensure /1 suffix on watch URL
      final parsed = Uri.parse(finalUrl);
      var p = parsed.path.replaceAll(RegExp(r'/+$'), '');
      if (p.contains('/detail/watch/') && !RegExp(r'/\d+$').hasMatch(p)) {
        p = '$p/1';
        finalUrl = parsed.replace(path: p, queryParameters: {'lang': lang}).toString();
      }

      var response = await client.get(Uri.parse(finalUrl), headers: _defaultHeaders);

      // In case of secondary redirect
      if (response.isRedirect || response.statusCode == 301 || response.statusCode == 302) {
        final loc = response.headers['location'];
        if (loc != null && loc.isNotEmpty) {
          finalUrl = loc.startsWith('http') ? loc : '$baseUrl$loc';
          final redirParsed = Uri.parse(finalUrl);
          var redirPath = redirParsed.path.replaceAll(RegExp(r'/+$'), '');
          if (redirPath.contains('/detail/watch/') && !RegExp(r'/\d+$').hasMatch(redirPath)) {
            redirPath = '$redirPath/1';
            finalUrl = redirParsed.replace(path: redirPath, queryParameters: {'lang': lang}).toString();
          }
          response = await client.get(Uri.parse(finalUrl), headers: _defaultHeaders);
        }
      }

      final html = response.body;

      // Fast extraction of episodeItemsRaw
      List<EpisodeItem> episodes = [];
      final marker = html.indexOf('episodeItemsRaw');
      if (marker != -1) {
        final start = html.indexOf('[', marker);
        final end = html.indexOf('];', start);
        if (start != -1 && end != -1) {
          try {
            final jsonStr = html.substring(start, end + 1);
            final decoded = json.decode(jsonStr);
            if (decoded is List) {
              episodes = decoded
                  .whereType<Map<String, dynamic>>()
                  .map((e) => EpisodeItem.fromJson(e))
                  .toList();
            }
          } catch (_) {}
        }
      }

      if (episodes.isEmpty) {
        final episodeMatch = RegExp(r'episodeItemsRaw\s*=\s*(\[[\s\S]*?\]);').firstMatch(html);
        if (episodeMatch != null) {
          final rawJson = episodeMatch.group(1);
          if (rawJson != null) {
            try {
              final list = json.decode(rawJson);
              if (list is List) {
                episodes = list
                    .whereType<Map<String, dynamic>>()
                    .map((e) => EpisodeItem.fromJson(e))
                    .toList();
              }
            } catch (_) {}
          }
        }
      }

      // Cache context token and edge base for dynamic stream refresh
      final ctxMatch = RegExp(r"""refreshSourceContextToken\s*=\s*['"]([^'"]+)['"]""").firstMatch(html);
      final edgeMatch = RegExp(r"""refreshSourceEdgeBase\s*=\s*['"]([^'"]+)['"]""").firstMatch(html);
      final dramaSlug = RegExp(r'/detail/watch/([^/?#]+)').firstMatch(finalUrl)?.group(1);
      if (ctxMatch != null && dramaSlug != null) {
        final rawEdge = edgeMatch?.group(1) ?? 'https://edge.narto-drama.com';
        final edgeBase = rawEdge.replaceAll(r'\/', '/').replaceAll(r'\', '').trim();
        final token = ctxMatch.group(1);
        if (token != null) {
          _dramaEdgeCache[dramaSlug] = {
            'token': token,
            'edgeBase': edgeBase.isNotEmpty ? edgeBase : 'https://edge.narto-drama.com',
          };
        }
      }

      String title = '';
      final titleMatch = RegExp(r"""movieTitle\s*=\s*["']([^"']+)["'];""").firstMatch(html);
      if (titleMatch != null) {
        title = titleMatch.group(1) ?? '';
      }
      if (title.isEmpty) {
        final docTitleMatch = RegExp(r'<title>(.*?)<\/title>', caseSensitive: false).firstMatch(html);
        title = docTitleMatch?.group(1)?.replaceAll('- Streaming Gratis', '').trim() ?? 'Short Drama';
      }
      title = DramaItem.cleanTitle(title);

      String poster = '';
      final posterMatch = RegExp(r"""moviePosterUrl\s*=\s*["']([^"']+)["'];""").firstMatch(html);
      if (posterMatch != null) {
        poster = posterMatch.group(1)?.replaceAll(r'\/', '/').replaceAll(r'\', '').trim() ?? '';
      }
      if (poster.isEmpty) {
        final ogImgMatch = RegExp(r'<meta\s+property=["\x27]og:image["\x27]\s+content=["\x27]([^"\x27]+)["\x27]', caseSensitive: false).firstMatch(html);
        if (ogImgMatch != null) {
          poster = ogImgMatch.group(1)?.replaceAll(r'\/', '/').replaceAll(r'\', '').trim() ?? '';
        }
      }
      if (poster.startsWith('/')) {
        poster = 'https://narto-drama.com$poster';
      }

      // Extract synopsis / description: First prioritize DOM synopsis element or strong tag
      String? description;
      final strongSinopsisMatch = RegExp(
        r'<strong>\s*(?:Sinopsis|Deskripsi)[^<]*</strong>\s*([\s\S]*?)</(?:p|div)>',
        caseSensitive: false,
      ).firstMatch(html);
      if (strongSinopsisMatch != null) {
        var rawSinopsis = strongSinopsisMatch.group(1)?.replaceAll(RegExp(r'<[^>]*>'), ' ').trim() ?? '';
        rawSinopsis = rawSinopsis
            .replaceAll('&quot;', '"')
            .replaceAll('&amp;', '&')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&apos;', "'")
            .replaceAll('&#39;', "'");
        if (rawSinopsis.isNotEmpty) {
          description = rawSinopsis;
        }
      }

      if (description == null || description.isEmpty) {
        final introMatch = RegExp(
          r'<(?:div|p)[^>]*class=["\x27][^"\x27]*(?:desktop-intro|info-intro|synopsis|description)[^"\x27]*["\x27][^>]*>([\s\S]*?)</(?:div|p)>',
          caseSensitive: false,
        ).firstMatch(html);
        if (introMatch != null) {
          var rawIntro = introMatch.group(1)?.replaceAll(RegExp(r'<[^>]*>'), ' ').trim() ?? '';
          rawIntro = rawIntro
              .replaceAll('&quot;', '"')
              .replaceAll('&amp;', '&')
              .replaceAll('&lt;', '<')
              .replaceAll('&gt;', '>')
              .replaceAll('&apos;', "'")
              .replaceAll('&#39;', "'");
          if (rawIntro.isNotEmpty) {
            description = rawIntro;
          }
        }
      }

      if (description == null || description.isEmpty) {
        final descMatch = RegExp(r'<meta\s+name=["\x27]description["\x27]\s+content=["\x27]([\s\S]*?)["\x27]', caseSensitive: false).firstMatch(html);
        if (descMatch != null) {
          var rawDesc = descMatch.group(1)?.trim() ?? '';
          rawDesc = rawDesc.replaceAll(RegExp(r'\.?\s*Narto\s+Drama.*$', caseSensitive: false), '').trim();
          rawDesc = rawDesc.replaceAll(RegExp(r'^.*?\bEpisode\s+\d+/\d+\s*[-—:]\s*', caseSensitive: false), '').trim();
          rawDesc = rawDesc
              .replaceAll('&quot;', '"')
              .replaceAll('&amp;', '&')
              .replaceAll('&lt;', '<')
              .replaceAll('&gt;', '>')
              .replaceAll('&apos;', "'")
              .replaceAll('&#39;', "'");
          if (rawDesc.isNotEmpty) {
            description = rawDesc;
          }
        }
      }
      if (description == null || description.isEmpty) {
        final ogDescMatch = RegExp(r'<meta\s+property=["\x27]og:description["\x27]\s+content=["\x27]([\s\S]*?)["\x27]', caseSensitive: false).firstMatch(html);
        if (ogDescMatch != null) {
          var rawDesc = ogDescMatch.group(1)?.trim() ?? '';
          rawDesc = rawDesc.replaceAll(RegExp(r'\.?\s*Narto\s+Drama.*$', caseSensitive: false), '').trim();
          rawDesc = rawDesc.replaceAll(RegExp(r'^.*?\bEpisode\s+\d+/\d+\s*[-—:]\s*', caseSensitive: false), '').trim();
          rawDesc = rawDesc
              .replaceAll('&quot;', '"')
              .replaceAll('&amp;', '&')
              .replaceAll('&lt;', '<')
              .replaceAll('&gt;', '>')
              .replaceAll('&apos;', "'")
              .replaceAll('&#39;', "'");
          if (rawDesc.isNotEmpty) {
            description = rawDesc;
          }
        }
      }

      String? provider;
      final providerMatch = RegExp(r"""movieSourceAppName\s*=\s*["']([^"']+)["'];""").firstMatch(html);
      if (providerMatch != null) {
        provider = providerMatch.group(1);
      }

      String? movieId;
      final movieIdMatch = RegExp(r"""movieId\s*=\s*(\d+);""").firstMatch(html) ??
          RegExp(r'<meta[^>]*name=["\x27]nd-current-movie-id["\x27][^>]*content=["\x27](\d+)["\x27]').firstMatch(html);
      if (movieIdMatch != null) {
        movieId = movieIdMatch.group(1);
      }
      final parsedMovieId = int.tryParse(movieId ?? '');

      client.close();

      return DramaDetail(
        id: movieId ?? '0',
        movieId: parsedMovieId,
        title: title,
        posterUrl: poster,
        description: description,
        providerName: provider,
        slug: dramaSlug,
        episodes: episodes,
      );
    } catch (_) {
      return null;
    }
  }

  /// Dynamic edge token refresh for CDN video
  static Future<String?> refreshStreamUrl(String slug, int episode, {String lang = 'id-ID'}) async {
    if (isProxyMode) {
      try {
        final uri = Uri.parse('$baseUrl/api/refresh-stream?slug=${Uri.encodeComponent(slug)}&episode=$episode');
        final res = await http.get(uri, headers: _defaultHeaders).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          if (data is Map && data['ok'] == true && data['play_url'] != null) {
            return data['play_url'].toString().replaceAll(r'\/', '/').replaceAll(r'\', '');
          }
        }
      } catch (_) {}
      return null;
    }

    // Direct mode: call edge refresh endpoint directly
    try {
      final cached = _dramaEdgeCache[slug];
      final ctxToken = cached?['token'];
      var edgeBase = cached?['edgeBase'] ?? 'https://edge.narto-drama.com';
      edgeBase = edgeBase.replaceAll(r'\/', '/').replaceAll(r'\', '').trim();

      if (ctxToken != null && ctxToken.isNotEmpty) {
        final refreshUri = Uri.parse(
          '$edgeBase/e/rs/detail/watch/$slug/$episode/refresh-source?force=1&rs_ctx=$ctxToken&lang=$lang',
        );
        final headers = Map<String, String>.from(_defaultHeaders);
        headers['Accept'] = 'application/json, text/plain, */*';

        final res = await http.get(refreshUri, headers: headers).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          if (data is Map && data['ok'] == true && data['play_url'] != null) {
            return data['play_url'].toString().replaceAll(r'\/', '/').replaceAll(r'\', '');
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Download and parse WebVTT subtitles
  static Future<List<SubtitleCue>> fetchSubtitles(String subtitleUrl) async {
    if (subtitleUrl.isEmpty) return [];
    try {
      final cleanUrl = subtitleUrl.replaceAll(r'\/', '/').replaceAll(r'\', '').trim();
      final targetUrl = cleanUrl.startsWith('http')
          ? cleanUrl
          : '$baseUrl${cleanUrl.startsWith('/') ? '' : '/'}$cleanUrl';

      final headers = Map<String, String>.from(_defaultHeaders);
      headers['Accept'] = 'text/vtt, text/plain;q=0.9, */*;q=0.8';

      final res = await http.get(Uri.parse(targetUrl), headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 && res.body.trim().isNotEmpty) {
        return parseWebVTT(res.body);
      }
    } catch (_) {}
    return [];
  }

  /// Parse WebVTT formatted string into list of SubtitleCue with gap-bridging anti-flicker
  static List<SubtitleCue> parseWebVTT(String content) {
    final List<SubtitleCue> rawCues = [];
    final lines = const LineSplitter().convert(content);

    int i = 0;
    while (i < lines.length) {
      final line = lines[i].trim();
      if (line.contains('-->') && !line.startsWith('<!--')) {
        final timeParts = line.split('-->');
        if (timeParts.length >= 2) {
          final startPart = timeParts[0].trim();
          final endParts = timeParts[1].trim().split(RegExp(r'\s+'));
          if (endParts.isNotEmpty) {
            final endPart = endParts[0];
            final start = _parseVttTimestamp(startPart);
            final end = _parseVttTimestamp(endPart);

            i++;
            final textLines = <String>[];
            while (i < lines.length && lines[i].trim().isNotEmpty && !lines[i].contains('-->')) {
              textLines.add(lines[i].trim());
              i++;
            }

            if (start != null && end != null && textLines.isNotEmpty) {
              String rawText = textLines.join('\n');
              // Clean VTT tags like [region=...] or <c>...
              rawText = rawText.replaceAll(RegExp(r'\[region=[^\]]+\]'), '');
              rawText = rawText.replaceAll(RegExp(r'<[^>]+>'), '');
              rawText = rawText.trim();
              if (rawText.isNotEmpty) {
                rawCues.add(SubtitleCue(start: start, end: end, text: rawText));
              }
            }
            continue;
          }
        }
      }
      i++;
    }

    if (rawCues.isEmpty) return [];

    // Sort cues chronologically
    rawCues.sort((a, b) => a.start.compareTo(b.start));

    // Anti-Flicker Processing:
    // 1. Minimum duration smoothing (at least 600ms per line to prevent flash-blinks)
    // 2. Gap bridging (if gap between speech is <= 750ms, bridge it seamlessly so box doesn't flicker off and on)
    final List<SubtitleCue> smoothed = [];
    for (int j = 0; j < rawCues.length; j++) {
      var cue = rawCues[j];
      final nextCue = (j + 1 < rawCues.length) ? rawCues[j + 1] : null;

      // Minimum duration (at least 600ms, clamped if next cue starts earlier)
      var end = cue.end;
      if (nextCue != null && nextCue.start > cue.start) {
        final minEnd = cue.start + const Duration(milliseconds: 600);
        if (end < minEnd) {
          end = (minEnd <= nextCue.start) ? minEnd : nextCue.start;
        }
      }

      // Gap bridging: If gap to next cue is <= 750ms, extend current cue to next start
      if (nextCue != null && nextCue.start > end) {
        final gap = nextCue.start - end;
        if (gap <= const Duration(milliseconds: 750)) {
          end = nextCue.start;
        }
      }

      smoothed.add(SubtitleCue(
        start: cue.start,
        end: end,
        text: cue.text,
      ));
    }

    return smoothed;
  }

  static Duration? _parseVttTimestamp(String s) {
    try {
      final clean = s.trim().replaceAll(',', '.');
      final parts = clean.split(':');
      if (parts.length == 3) {
        final h = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        final secParts = parts[2].split('.');
        final sec = int.parse(secParts[0]);
        final ms = secParts.length > 1
            ? int.parse(secParts[1].padRight(3, '0').substring(0, 3))
            : 0;
        return Duration(hours: h, minutes: m, seconds: sec, milliseconds: ms);
      } else if (parts.length == 2) {
        final m = int.parse(parts[0]);
        final secParts = parts[1].split('.');
        final sec = int.parse(secParts[0]);
        final ms = secParts.length > 1
            ? int.parse(secParts[1].padRight(3, '0').substring(0, 3))
            : 0;
        return Duration(minutes: m, seconds: sec, milliseconds: ms);
      }
    } catch (_) {}
    return null;
  }

}
