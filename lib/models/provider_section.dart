import 'drama.dart';

class ProviderSection {
  final String title;
  final String tabKey;
  final List<DramaItem> items;

  const ProviderSection({
    required this.title,
    required this.tabKey,
    required this.items,
  });

  factory ProviderSection.fromJson(Map<String, dynamic> json, {String? providerKey}) {
    final titleVal = json['tab_label']?.toString() ?? json['title']?.toString() ?? 'Rekomendasi';
    final tabKeyVal = json['tab_key']?.toString() ?? 'home';
    final rawItems = json['items'];
    List<DramaItem> dramaItems = [];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map<String, dynamic>) {
          dramaItems.add(DramaItem.fromJson(item, defaultProvider: providerKey));
        }
      }
    }

    return ProviderSection(
      title: titleVal,
      tabKey: tabKeyVal,
      items: dramaItems,
    );
  }
}
