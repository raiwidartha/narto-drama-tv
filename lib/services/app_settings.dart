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
  static final Map<String, int> _providerCountCache = {};

  static final List<ProviderInfo> _allProviders = [];

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
  static List<ProviderInfo> get allProviders => List.unmodifiable(_allProviders);

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

  /// Save updated provider counts
  static Future<void> saveProviderCounts(Map<String, int> counts) async {
    _providerCountCache.addAll(counts);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyProviderStatsCache, json.encode(_providerCountCache));
  }

  /// Test connection to a given server URL
  static Future<Map<String, dynamic>> testConnection(String targetUrl) async {
    var cleanUrl = targetUrl.trim();
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    final stopwatch = Stopwatch()..start();

    try {
      final isUpstream = cleanUrl.contains('narto-drama.com');
      final testUri = isUpstream
          ? Uri.parse('$cleanUrl/search?q=balas&limit=1&lang=id-ID')
          : Uri.parse('$cleanUrl/api/providers');

      final headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
        'Cookie': _customCookie ?? NartoApiService.defaultCookie,
        'Referer': 'https://narto-drama.com/',
        'X-Requested-With': 'XMLHttpRequest',
        'Accept': 'application/json, text/plain, */*',
      };

      final response = await http.get(testUri, headers: headers).timeout(const Duration(seconds: 8));
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
    }
  }
}
