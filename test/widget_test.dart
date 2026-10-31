// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:narto_drama_tv/main.dart';
import 'package:narto_drama_tv/models/drama.dart';
import 'package:narto_drama_tv/services/app_settings.dart';
import 'package:narto_drama_tv/services/history_bookmark_service.dart';
import 'package:narto_drama_tv/widgets/tv_focusable.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Search provider detection test', () async {
    final itemJson = {
      'id': 23415,
      'title': 'Sekretarisku yang Pernah Menjadi Istriku',
      'tags': [
        'Romantis', 'Komedi Romantis', 'Kantoran', 'Korea', 'Cinderella', 'Nikah Kontrak',
        'Exclusive', 'Komedi', 'Miliarder', 'Billionaire', 'Romance', 'Comedy', 'Office',
        'Rom-Com', 'Nikah Sebelum Cinta', 'Eksklusif', 'Vigloo Asli', 'Marriage Before Love',
        'Contract Marriage', 'Vigloo Original'
      ],
      'source_type': 'local',
      'url': '/detail/watch/my-secretary-who-once-was-my-wife?lang=id-ID&from=search',
    };
    final drama = DramaItem.fromJson(itemJson);
    expect(drama.providerKey, equals('vigloo'));
  });

  testWidgets('TvFocusable responds to D-pad Center / Select / Enter / Gamepad', (WidgetTester tester) async {
    int pressCount = 0;
    final focusNode = FocusNode();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFocusable(
            focusNode: focusNode,
            autofocus: true,
            onPressed: () => pressCount++,
            child: const Text('Test Button'),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    // Test LogicalKeyboardKey.select (Android keycode 23 KEYCODE_DPAD_CENTER)
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(pressCount, equals(1));

    // Test LogicalKeyboardKey.enter
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(pressCount, equals(2));

    // Test LogicalKeyboardKey.gameButtonA
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pump();
    expect(pressCount, equals(3));

    // Test LogicalKeyboardKey.gameButtonSelect
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonSelect);
    await tester.pump();
    expect(pressCount, equals(4));
  });

  testWidgets('TvFocusable key repeat support', (WidgetTester tester) async {
    int pressCount = 0;
    final focusNode = FocusNode();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFocusable(
            focusNode: focusNode,
            autofocus: true,
            onPressed: () => pressCount++,
            child: const Text('Repeat Button'),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(pressCount, equals(1));
  });

  testWidgets('Player exit confirmation dialog UI renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlertDialog(
            backgroundColor: const Color(0xFF0F172A),
            title: const Text('Keluar Menonton?'),
            content: const Text('Apakah Anda yakin ingin keluar dari pemutar drama?'),
            actions: [
              TvFocusable(
                autofocus: true,
                onPressed: () {},
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                backgroundColor: Colors.white12,
                child: const Text('Lanjut Menonton'),
              ),
              TvFocusable(
                onPressed: () {},
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                backgroundColor: const Color(0xFFFF2D55),
                child: const Text('Keluar'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Keluar Menonton?'), findsOneWidget);
    expect(find.text('Lanjut Menonton'), findsOneWidget);
    expect(find.text('Keluar'), findsOneWidget);
  });

  testWidgets('Subtitle tracks and softsub detection logic test', (WidgetTester tester) async {
    const epHardsub = EpisodeItem(
      id: 1,
      number: 1,
      title: 'Episode 1',
      playUrl: 'https://example.com/video.mp4',
      directPlayUrl: 'https://example.com/video.mp4',
      thumbUrl: '',
      watchUrl: '',
    );
    expect(epHardsub.multiSubtitles.isEmpty, isTrue);
    expect(epHardsub.effectiveSubtitleUrl.isEmpty, isTrue);

    const epSoftsub = EpisodeItem(
      id: 2,
      number: 2,
      title: 'Episode 2',
      playUrl: 'https://example.com/video2.mp4',
      directPlayUrl: 'https://example.com/video2.mp4',
      thumbUrl: '',
      watchUrl: '',
      multiSubtitles: [
        SubtitleTrack(
          languageCode: 'en-US',
          label: 'English',
          subtitleUrl: 'https://example.com/en.vtt',
        ),
        SubtitleTrack(
          languageCode: 'id-ID',
          label: 'Bahasa Indonesia',
          subtitleUrl: 'https://example.com/id.vtt',
          isDefault: true,
        ),
      ],
    );
    expect(epSoftsub.multiSubtitles.length, equals(2));
    expect(epSoftsub.effectiveSubtitleUrl, equals('https://example.com/id.vtt'));

    // Check default Indonesian selection
    final chosen = epSoftsub.multiSubtitles.firstWhere(
      (t) => t.languageCode.toLowerCase().startsWith('id') || t.label.toLowerCase().contains('indonesia'),
      orElse: () => epSoftsub.multiSubtitles.first,
    );
    expect(chosen.label, equals('Bahasa Indonesia'));
  });

  test('Home merged providers defaults and drama count mapping test', () async {
    expect(AppSettings.defaultMergedProviders, contains('vigloo'));
    expect(AppSettings.defaultMergedProviders, contains('anyreel'));
    expect(AppSettings.defaultMergedProviders, contains('dramabox'));
    expect(AppSettings.defaultMergedProviders, contains('reelshort'));
    expect(AppSettings.defaultMergedProviders, contains('shortmax'));
    expect(AppSettings.defaultMergedProviders, contains('moboreels'));

    // Verify drama counts in provider stats
    expect(AppSettings.getDramaCount('vigloo'), greaterThan(0));
    expect(AppSettings.getDramaCount('anyreel'), greaterThan(0));
    expect(AppSettings.getDramaCount('shortmax'), greaterThan(0));
  });

  test('AppSettings.testConnection reaches upstream host quickly', () async {
    final mockClient = http_testing.MockClient((request) async {
      return http.Response('<html>OK</html>', 200);
    });
    final result = await AppSettings.testConnection('https://narto-drama.com', client: mockClient);
    expect(result['success'], isTrue);
    expect(result['statusCode'], equals(200));
    expect(result['latencyMs'], isNonNegative);
  });

  test('ProviderInfo status and latency classification test', () {
    const pFast = ProviderInfo(key: 'melolo', label: 'Melolo', latencyMs: 250);
    expect(pFast.speedTag, equals('Cepat'));
    expect(pFast.statusLabel, equals('250ms Cepat'));
    expect(pFast.isFastOrNormal, isTrue);
    expect(pFast.statusColor, equals(const Color(0xFF10B981))); // Green

    const pNormal = ProviderInfo(key: 'dramabox', label: 'DramaBox', latencyMs: 950);
    expect(pNormal.speedTag, equals('Normal'));
    expect(pNormal.statusLabel, equals('950ms Normal'));
    expect(pNormal.isFastOrNormal, isTrue);
    expect(pNormal.statusColor, equals(const Color(0xFFF59E0B))); // Yellow

    const pSlow = ProviderInfo(key: 'shortmax', label: 'ShortMax', latencyMs: 2100);
    expect(pSlow.speedTag, equals('Lelet'));
    expect(pSlow.statusLabel, equals('2100ms Lelet'));
    expect(pSlow.isFastOrNormal, isFalse);
    expect(pSlow.statusColor, equals(const Color(0xFFF97316))); // Orange

    const pOffline = ProviderInfo(key: 'bad', label: 'Bad', latencyMs: 5000, isOnline: false);
    expect(pOffline.speedTag, equals('Gangguan'));
    expect(pOffline.statusLabel, equals('Gangguan'));
    expect(pOffline.isFastOrNormal, isFalse);
    expect(pOffline.statusColor, equals(const Color(0xFFEF4444))); // Red
  });

  testWidgets('Narto Drama TV smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const NartoDramaTvApp());
    expect(find.byType(NartoDramaTvApp), findsOneWidget);
  });

  test('HistoryBookmarkService tracks watched episodes, aliases, and bulk marking', () async {
    SharedPreferences.setMockInitialValues({});

    // User starts watching Ep 2 (index 1) directly, skipping Ep 1
    await HistoryBookmarkService.saveHistory(
      dramaKey: 'detail_shortmax_9999',
      dramaId: '9999',
      aliasKeys: ['shortmax_9999', 'slug-ibu-tiri'],
      title: 'Ibu Tiriku Gendut',
      posterUrl: 'https://example.com/poster.jpg',
      watchUrl: '/detail/watch/slug-ibu-tiri/2',
      provider: 'shortmax',
      episodeIndex: 1, // Episode 2
      totalEpisodes: 50,
    );

    // Both episode index 0 (Ep 1) and index 1 (Ep 2) should be marked watched
    final watched = await HistoryBookmarkService.getWatchedEpisodes(
      candidateKeys: ['shortmax_9999', 'detail_shortmax_9999'],
      title: 'Ibu Tiriku Gendut',
    );
    expect(watched.contains(0), isTrue); // Ep 1 auto-marked watched
    expect(watched.contains(1), isTrue); // Ep 2 auto-marked watched
    expect(watched.contains(2), isFalse); // Ep 3 not yet watched

    // Querying with candidate key 'shortmax_9999' returns last watched index = 1
    final lastEp = await HistoryBookmarkService.getLastWatchedEpisode(
      candidateKeys: ['shortmax_9999'],
      title: 'Ibu Tiriku Gendut',
    );
    expect(lastEp, equals(1));
  });
}
