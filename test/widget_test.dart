// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narto_drama_tv/main.dart';
import 'package:narto_drama_tv/models/drama.dart';
import 'package:narto_drama_tv/widgets/tv_focusable.dart';

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

  testWidgets('Narto Drama TV smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const NartoDramaTvApp());
    expect(find.byType(NartoDramaTvApp), findsOneWidget);
  });
}
