// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:narto_drama_tv/main.dart';
import 'package:narto_drama_tv/models/drama.dart';

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

  testWidgets('Narto Drama TV smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const NartoDramaTvApp());
    expect(find.byType(NartoDramaTvApp), findsOneWidget);
  });
}
