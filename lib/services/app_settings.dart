import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/drama.dart';
import 'narto_api_service.dart';

class AppSettings {
  static const String keyApiUrl = 'config_api_url';
  static const String keyCustomCookie = 'config_custom_cookie';
  static const String keyProviderStatsCache = 'config_provider_stats_cache';
  static const String keyProviderLatencyCache = 'config_provider_latency_cache';
  static const String keySubtitlePosition = 'config_subtitle_position';
  static const String keySubtitleFontSize = 'config_subtitle_font_size';
  static const String keySubtitleFontColor = 'config_subtitle_font_color';
  static const String keySubtitleFontWeight = 'config_subtitle_font_weight';
  static const String keySubtitleFontFamily = 'config_subtitle_font_family';
  static const String keySubtitleBgEnabled = 'config_subtitle_bg_enabled';
  static const String keySubtitleBgOpacity = 'config_subtitle_bg_opacity';
  static const String keySubtitleBgColor = 'config_subtitle_bg_color';
  static const String keySubtitleVerticalOffset = 'config_subtitle_vertical_offset';

  static const String defaultBaseUrl = 'https://narto-drama.com';

  static String _currentBaseUrl = defaultBaseUrl;
  static String? _customCookie;
  static final Map<String, int> _providerCountCache = {
    'anyreel': 1475,
    'melolo': 248,
    'vigloo': 247,
    'dramabox': 1121,
    'reelshort': 890,
    'moboreels': 350,
    'shortmax': 1632,
  };
  static final Map<String, int> _providerLatencyMap = {};
  static final Map<String, bool> _providerOnlineMap = {};

  static final List<ProviderInfo> _allProviders = [
    ProviderInfo(key: 'anyreel', label: 'AnyReel', dramaCount: 1475, labelWithCount: 'AnyReel (1475)'),
    ProviderInfo(key: 'melolo', label: 'Melolo', dramaCount: 248, labelWithCount: 'Melolo (248)'),
    ProviderInfo(key: 'vigloo', label: 'Vigloo', dramaCount: 247, labelWithCount: 'Vigloo (247)'),
    ProviderInfo(key: 'dramabox', label: 'DramaBox', dramaCount: 1121, labelWithCount: 'DramaBox (1121)'),
    ProviderInfo(key: 'reelshort', label: 'ReelShort', dramaCount: 890, labelWithCount: 'ReelShort (890)'),
    ProviderInfo(key: 'moboreels', label: 'MoboReels', dramaCount: 350, labelWithCount: 'MoboReels (350)'),
    ProviderInfo(key: 'shortmax', label: 'ShortMax', dramaCount: 1632, labelWithCount: 'ShortMax (1632)'),
  ];

  // Merged Home Providers setting
  static const String keyHomeMergedProviders = 'config_home_merged_providers';
  static const List<String> defaultMergedProviders = [
    'anyreel',
    'dramabox',
    'reelshort',
    'shortmax',
    'vigloo',
    'moboreels',
  ];
  static List<String> _homeMergedProviders = List.from(defaultMergedProviders);

  // Subtitle preferences (TV default: center & sedang 24sp, tebal, sans-serif)
  static String _subtitlePosition = 'center'; // 'bottom', 'middle_bottom', 'center', 'middle_top', 'top', 'custom'
  static double _subtitleVerticalOffset = 0.50; // 0.05 (top) to 0.95 (bottom), default 0.50 (center)
  static double _subtitleFontSize = 24.0; // 18.0 (kecil), 24.0 (sedang - default), 28.0 (besar), 34.0 (sangat besar)
  static int _subtitleFontColor = 0xFFFFFFFF; // White, Yellow, Cyan, Green
  static String _subtitleFontWeight = 'bold'; // 'normal', 'medium', 'bold', 'black'
  static String _subtitleFontFamily = 'sans-serif'; // 'sans-serif', 'serif', 'monospace', 'sans-serif-condensed'
  static bool _subtitleBgEnabled = true; // Toggle background
  static double _subtitleBgOpacity = 0.80; // 0.0 - 1.0
  static int _subtitleBgColor = 0xFF000000; // Hitam, Abu Gelap, Biru Gelap, Coklat Gelap

  static String get baseUrl => _currentBaseUrl;
  static bool get isCustomHost => _currentBaseUrl != defaultBaseUrl;
  static bool get isCustomBaseUrl => isCustomHost;
  static bool get isProxyMode => !_currentBaseUrl.contains('narto-drama.com');
  static String? get customCookie => _customCookie;
  static List<ProviderInfo> get allProviders {
    return List.unmodifiable(_allProviders.map((p) {
      final k = p.key.toLowerCase();
      final lat = _providerLatencyMap[k] ?? p.latencyMs;
      final onl = _providerOnlineMap[k] ?? p.isOnline;
      if (lat != p.latencyMs || onl != p.isOnline) {
        return p.copyWith(latencyMs: lat, isOnline: onl);
      }
      return p;
    }));
  }
  static List<String> get homeMergedProviders => List.unmodifiable(_homeMergedProviders);

  static Future<void> setHomeMergedProviders(List<String> providers) async {
    _homeMergedProviders = List.from(providers);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(keyHomeMergedProviders, _homeMergedProviders);
  }

  static String get subtitlePosition => _subtitlePosition;
  static double get subtitleVerticalOffset => _subtitleVerticalOffset;
  static double get subtitleFontSize {
    if (_subtitleFontSize != 18.0 && _subtitleFontSize != 24.0 && _subtitleFontSize != 28.0 && _subtitleFontSize != 34.0) {
      return 24.0;
    }
    return _subtitleFontSize;
  }
  static int get subtitleFontColor => _subtitleFontColor;
  static String get subtitleFontWeight => _subtitleFontWeight;
  static String get subtitleFontFamily => _subtitleFontFamily;
  static bool get subtitleBgEnabled => _subtitleBgEnabled;
  static double get subtitleBgOpacity => _subtitleBgOpacity;
  static int get subtitleBgColor => _subtitleBgColor;

  static FontWeight get effectiveFontWeight {
    switch (_subtitleFontWeight) {
      case 'normal':
        return FontWeight.w400;
      case 'medium':
        return FontWeight.w500;
      case 'black':
        return FontWeight.w900;
      case 'bold':
      default:
        return FontWeight.bold;
    }
  }

  static String? get effectiveFontFamily {
    if (_subtitleFontFamily == 'sans-serif' || _subtitleFontFamily == 'default') {
      return null;
    }
    return _subtitleFontFamily;
  }

  /// Initialize stored preferences
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load custom upstream host if set
    final savedUrl = prefs.getString(keyApiUrl);
    if (savedUrl != null && savedUrl.trim().isNotEmpty) {
      _currentBaseUrl = savedUrl.trim();
    } else {
      _currentBaseUrl = defaultBaseUrl;
    }
    _customCookie = prefs.getString(keyCustomCookie);

    // Load subtitle preferences with new defaults (center & besar 21.0)
    _subtitlePosition = prefs.getString(keySubtitlePosition) ?? 'center';
    if (prefs.containsKey(keySubtitleVerticalOffset)) {
      _subtitleVerticalOffset = prefs.getDouble(keySubtitleVerticalOffset) ?? 0.50;
    } else {
      switch (_subtitlePosition) {
        case 'top':
          _subtitleVerticalOffset = 0.15;
          break;
        case 'middle_top':
          _subtitleVerticalOffset = 0.32;
          break;
        case 'center':
          _subtitleVerticalOffset = 0.50;
          break;
        case 'middle_bottom':
          _subtitleVerticalOffset = 0.65; // Significantly higher than before
          break;
        case 'bottom':
          _subtitleVerticalOffset = 0.85;
          break;
        default:
          _subtitleVerticalOffset = 0.50;
      }
    }
    final savedFontSize = prefs.getDouble(keySubtitleFontSize);
    if (savedFontSize == null || ![18.0, 24.0, 28.0, 34.0].contains(savedFontSize)) {
      _subtitleFontSize = 24.0;
    } else {
      _subtitleFontSize = savedFontSize;
    }
    _subtitleFontColor = prefs.getInt(keySubtitleFontColor) ?? 0xFFFFFFFF;
    _subtitleFontWeight = prefs.getString(keySubtitleFontWeight) ?? 'bold';
    _subtitleFontFamily = prefs.getString(keySubtitleFontFamily) ?? 'sans-serif';
    _subtitleBgEnabled = prefs.getBool(keySubtitleBgEnabled) ?? true;
    _subtitleBgOpacity = prefs.getDouble(keySubtitleBgOpacity) ?? 0.80;
    _subtitleBgColor = prefs.getInt(keySubtitleBgColor) ?? 0xFF000000;

    // Load preloaded provider stats from assets/data/provider_stats.json
    try {
      final jsonStr = await rootBundle.loadString('assets/data/provider_stats.json');
      final data = json.decode(jsonStr);
      if (data is List) {
        _allProviders.clear();
        for (final item in data) {
          if (item is Map) {
            final slug = item['slug']?.toString() ?? '';
            final label = item['label']?.toString() ?? slug;
            final count = (item['count'] as num?)?.toInt() ?? 0;
            if (slug.isNotEmpty) {
              _providerCountCache[slug.toLowerCase()] = count;
              final labelWithCount = count > 0 ? '$label ($count)' : label;
              _allProviders.add(ProviderInfo(
                key: slug,
                label: label,
                dramaCount: count,
                labelWithCount: labelWithCount,
              ));
            }
          }
        }
        _allProviders.sort((a, b) => b.dramaCount.compareTo(a.dramaCount));
      }
    } catch (_) {}

    // Override with any user-audited cache in SharedPreferences
    final cachedStr = prefs.getString(keyProviderStatsCache);
    if (cachedStr != null && cachedStr.isNotEmpty) {
      try {
        final Map<String, dynamic> decoded = json.decode(cachedStr);
        for (final entry in decoded.entries) {
          _providerCountCache[entry.key.toLowerCase()] = (entry.value as num).toInt();
        }
      } catch (_) {}
    }

    // Load provider latency cache in SharedPreferences
    final cachedLatencyStr = prefs.getString(keyProviderLatencyCache);
    if (cachedLatencyStr != null && cachedLatencyStr.isNotEmpty) {
      try {
        final Map<String, dynamic> decoded = json.decode(cachedLatencyStr);
        for (final entry in decoded.entries) {
          final val = entry.value;
          if (val is Map) {
            final lat = (val['latencyMs'] as num?)?.toInt();
            final onl = val['isOnline'] == true;
            if (lat != null) {
              _providerLatencyMap[entry.key.toLowerCase()] = lat;
            }
            _providerOnlineMap[entry.key.toLowerCase()] = onl;
          } else if (val is num) {
            _providerLatencyMap[entry.key.toLowerCase()] = val.toInt();
            _providerOnlineMap[entry.key.toLowerCase()] = true;
          }
        }
      } catch (_) {}
    }

    final savedMerged = prefs.getStringList(keyHomeMergedProviders);
    if (savedMerged != null && savedMerged.isNotEmpty) {
      _homeMergedProviders = savedMerged;
    } else {
      _homeMergedProviders = List.from(defaultMergedProviders);
    }
  }

  /// Set and persist base API URL
  static Future<void> setBaseUrl(String url) async {
    var cleanUrl = url.trim();
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    if (cleanUrl.isEmpty) cleanUrl = defaultBaseUrl;
    _currentBaseUrl = cleanUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyApiUrl, cleanUrl);
  }

  /// Reset to default upstream
  static Future<void> resetToDefault() async {
    await setBaseUrl(defaultBaseUrl);
  }

  /// Set custom cookie override
  static Future<void> setCustomCookie(String? cookie) async {
    _customCookie = cookie?.trim().isEmpty == true ? null : cookie?.trim();
    final prefs = await SharedPreferences.getInstance();
    if (_customCookie != null) {
      await prefs.setString(keyCustomCookie, _customCookie!);
    } else {
      await prefs.remove(keyCustomCookie);
    }
  }

  /// Subtitle position preset: 'top', 'middle_top', 'center', 'middle_bottom', 'bottom'
  static Future<void> setSubtitlePosition(String position) async {
    _subtitlePosition = position;
    switch (position) {
      case 'top':
        _subtitleVerticalOffset = 0.15;
        break;
      case 'middle_top':
        _subtitleVerticalOffset = 0.32;
        break;
      case 'center':
        _subtitleVerticalOffset = 0.50;
        break;
      case 'middle_bottom':
        _subtitleVerticalOffset = 0.65; // Naik lebih tinggi
        break;
      case 'bottom':
        _subtitleVerticalOffset = 0.85;
        break;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keySubtitlePosition, position);
    await prefs.setDouble(keySubtitleVerticalOffset, _subtitleVerticalOffset);
  }

  /// Subtitle manual vertical offset: 0.05 (top) to 0.95 (bottom)
  static Future<void> setSubtitleVerticalOffset(double offset) async {
    _subtitleVerticalOffset = offset.clamp(0.05, 0.95);
    if ((_subtitleVerticalOffset - 0.50).abs() < 0.04) {
      _subtitlePosition = 'center';
    } else if ((_subtitleVerticalOffset - 0.32).abs() < 0.04) {
      _subtitlePosition = 'middle_top';
    } else if ((_subtitleVerticalOffset - 0.65).abs() < 0.04) {
      _subtitlePosition = 'middle_bottom';
    } else if ((_subtitleVerticalOffset - 0.85).abs() < 0.04) {
      _subtitlePosition = 'bottom';
    } else if ((_subtitleVerticalOffset - 0.15).abs() < 0.04) {
      _subtitlePosition = 'top';
    } else {
      _subtitlePosition = 'custom';
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(keySubtitleVerticalOffset, _subtitleVerticalOffset);
    await prefs.setString(keySubtitlePosition, _subtitlePosition);
  }

  /// Subtitle font size: e.g. 13.0, 16.0, 20.0, 24.0
  static Future<void> setSubtitleFontSize(double size) async {
    _subtitleFontSize = size;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(keySubtitleFontSize, size);
  }

  /// Subtitle font color: e.g. 0xFFFFFFFF
  static Future<void> setSubtitleFontColor(int color) async {
    _subtitleFontColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keySubtitleFontColor, color);
  }

  /// Subtitle font weight: 'normal', 'medium', 'bold', 'black'
  static Future<void> setSubtitleFontWeight(String weight) async {
    _subtitleFontWeight = weight;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keySubtitleFontWeight, weight);
  }

  /// Subtitle font family: 'sans-serif', 'serif', 'monospace', 'sans-serif-condensed'
  static Future<void> setSubtitleFontFamily(String family) async {
    _subtitleFontFamily = family;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keySubtitleFontFamily, family);
  }

  /// Toggle subtitle background
  static Future<void> setSubtitleBgEnabled(bool enabled) async {
    _subtitleBgEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keySubtitleBgEnabled, enabled);
  }

  /// Subtitle background opacity: e.g. 0.0 to 1.0
  static Future<void> setSubtitleBgOpacity(double opacity) async {
    _subtitleBgOpacity = opacity;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(keySubtitleBgOpacity, opacity);
  }

  /// Subtitle background color: e.g. 0xFF000000
  static Future<void> setSubtitleBgColor(int color) async {
    _subtitleBgColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keySubtitleBgColor, color);
  }

  /// Get cached drama count for a given provider
  static int getDramaCount(String providerKey) {
    return _providerCountCache[providerKey.toLowerCase()] ?? 0;
  }

  /// Get cached latency in ms for a provider
  static int? getProviderLatency(String providerKey) {
    return _providerLatencyMap[providerKey.toLowerCase()];
  }

  /// Check if provider is currently online
  static bool isProviderOnline(String providerKey) {
    return _providerOnlineMap[providerKey.toLowerCase()] ?? true;
  }

  /// Record measured latency and health status for a provider
  static Future<void> recordProviderLatency(String providerKey, int latencyMs, bool isOnline) async {
    final keyLower = providerKey.toLowerCase();
    _providerLatencyMap[keyLower] = latencyMs;
    _providerOnlineMap[keyLower] = isOnline;

    for (int i = 0; i < _allProviders.length; i++) {
      if (_allProviders[i].key.toLowerCase() == keyLower) {
        _allProviders[i] = _allProviders[i].copyWith(
          latencyMs: latencyMs,
          isOnline: isOnline,
        );
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> exportMap = {};
      for (final k in _providerLatencyMap.keys) {
        exportMap[k] = {
          'latencyMs': _providerLatencyMap[k],
          'isOnline': _providerOnlineMap[k] ?? true,
        };
      }
      await prefs.setString(keyProviderLatencyCache, json.encode(exportMap));
    } catch (_) {}
  }

  /// Save updated provider counts
  static Future<void> saveProviderCounts(Map<String, int> counts) async {
    _providerCountCache.addAll(counts);
    for (int i = 0; i < _allProviders.length; i++) {
      final p = _allProviders[i];
      final keyLower = p.key.toLowerCase();
      if (counts.containsKey(keyLower)) {
        final newCount = counts[keyLower]!;
        _allProviders[i] = p.copyWith(
          dramaCount: newCount,
          labelWithCount: newCount > 0 ? '${p.label} ($newCount)' : p.label,
          latencyMs: _providerLatencyMap[keyLower] ?? p.latencyMs,
          isOnline: _providerOnlineMap[keyLower] ?? p.isOnline,
        );
      }
    }
    _allProviders.sort((a, b) => b.dramaCount.compareTo(a.dramaCount));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyProviderStatsCache, json.encode(_providerCountCache));
  }

  /// Test connection to a given server URL
  static Future<Map<String, dynamic>> testConnection(String targetUrl, {http.Client? client}) async {
    var cleanUrl = targetUrl.trim();
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    final stopwatch = Stopwatch()..start();

    final httpClient = client ?? http.Client();
    try {
      final isUpstream = cleanUrl.contains('narto-drama.com');
      final testUri = isUpstream
          ? Uri.parse('$cleanUrl/')
          : Uri.parse('$cleanUrl/api/general?page=1');

      final headers = <String, String>{
        'User-Agent': NartoApiService.userAgent,
        'Referer': '$cleanUrl/',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,application/json,*/*;q=0.8',
      };
      if (_customCookie != null && _customCookie!.trim().isNotEmpty) {
        headers['Cookie'] = _customCookie!.trim();
      }

      final response = await httpClient.get(testUri, headers: headers).timeout(const Duration(seconds: 8));
      stopwatch.stop();

      final isSuccess = response.statusCode >= 200 && response.statusCode < 400;
      return {
        'success': isSuccess,
        'statusCode': response.statusCode,
        'latencyMs': stopwatch.elapsedMilliseconds,
        'message': isSuccess
            ? 'Terhubung (Status ${response.statusCode}, ${stopwatch.elapsedMilliseconds}ms)'
            : 'Gagal terhubung (Status ${response.statusCode})',
      };
    } catch (e) {
      stopwatch.stop();
      return {
        'success': false,
        'statusCode': 0,
        'latencyMs': stopwatch.elapsedMilliseconds,
        'message': 'Koneksi gagal: ${e.toString().replaceAll('Exception:', '').trim()}',
      };
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }
}
