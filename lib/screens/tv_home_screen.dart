import 'package:flutter/material.dart';
import '../models/drama.dart';
import '../models/provider_section.dart';
import '../services/narto_api_service.dart';
import '../services/app_settings.dart';
import '../services/history_bookmark_service.dart';
import '../widgets/tv_focusable.dart';
import '../widgets/tv_drama_card.dart';
import 'tv_detail_screen.dart';

class TvHomeScreen extends StatefulWidget {
  const TvHomeScreen({super.key});

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen> {
  int _selectedTabIndex = 0; // 0: Home, 1: Providers, 2: History, 3: Favorites, 4: Search, 5: Settings
  
  // Home tab state
  String _activeProvider = 'general'; // 'general' or provider key (e.g. 'dramabox')
  List<DramaItem> _homeDramas = [];
  bool _isLoadingHome = false;
  String _homeError = '';
  int _homePage = 1;
  bool _hasMoreHome = true;

  // Providers list
  List<ProviderInfo> _providers = [];
  bool _isSyncingProviders = false;

  // History & Bookmarks
  List<HistoryItem> _historyItems = [];
  List<BookmarkItem> _bookmarkItems = [];

  // Search
  final TextEditingController _searchController = TextEditingController();
  List<DramaItem> _searchResults = [];
  bool _isSearching = false;
  String _searchError = '';

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    await AppSettings.init();
    if (mounted) {
      setState(() {
        _providers = AppSettings.allProviders;
      });
      _loadHomeCatalog(reset: true);
    }
  }

  Future<void> _loadHomeCatalog({bool reset = false}) async {
    if (_isLoadingHome) return;
    if (reset) {
      setState(() {
        _homePage = 1;
        _homeDramas = [];
        _hasMoreHome = true;
        _homeError = '';
        _isLoadingHome = true;
      });
    } else {
      if (!_hasMoreHome) return;
      setState(() {
        _isLoadingHome = true;
      });
    }

    try {
      if (_activeProvider == 'general') {
        final res = await NartoApiService.fetchGeneralCatalog(page: _homePage);
        if (mounted) {
          setState(() {
            _homeDramas = reset ? res.items : [..._homeDramas, ...res.items];
            _hasMoreHome = res.hasNext;
            _homePage++;
            _isLoadingHome = false;
          });
        }
      } else {
        final res = await NartoApiService.fetchProviderSections(
          provider: _activeProvider,
          page: _homePage,
        );
        final sections = res['sections'] as List<ProviderSection>? ?? [];
        final apiProviders = res['providers'] as List<ProviderInfo>?;
        final List<DramaItem> items = [];
        for (final sec in sections) {
          items.addAll(sec.items);
        }

        // Deduplicate items by historyKey/id
        final seen = <String>{};
        final uniqueItems = <DramaItem>[];
        for (final item in items) {
          if (seen.add(item.historyKey)) {
            uniqueItems.add(item);
          }
        }

        if (mounted) {
          setState(() {
            if (apiProviders != null && apiProviders.isNotEmpty) {
              _providers = apiProviders;
            }
            _homeDramas = reset ? uniqueItems : [..._homeDramas, ...uniqueItems];
            _hasMoreHome = uniqueItems.length >= 10;
            _homePage++;
            _isLoadingHome = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingHome = false;
          _homeError = 'Gagal memuat katalog ($e)';
        });
      }
    }
  }

  Future<void> _loadHistory() async {
    final list = await HistoryBookmarkService.getHistory();
    if (mounted) {
      setState(() {
        _historyItems = list;
      });
    }
  }

  Future<void> _loadBookmarks() async {
    final list = await HistoryBookmarkService.getBookmarks();
    if (mounted) {
      setState(() {
        _bookmarkItems = list;
      });
    }
  }

  Future<void> _syncProvidersManual() async {
    if (_isSyncingProviders) return;
    setState(() => _isSyncingProviders = true);
    try {
      final res = await NartoApiService.fetchProviderSections(provider: 'general');
      final list = res['providers'] as List<ProviderInfo>?;
      if (list != null && list.isNotEmpty) {
        setState(() {
          _providers = list;
          _isSyncingProviders = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sinkronisasi sukses: ${list.length} provider aktif dimuat.'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        }
      } else {
        setState(() => _isSyncingProviders = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tidak ada perubahan daftar provider dari server.')),
          );
        }
      }
    } catch (e) {
      setState(() => _isSyncingProviders = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal sinkronisasi ($e)'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  void _onTabChanged(int index) {
    setState(() {
      _selectedTabIndex = index;
    });
    if (index == 2) {
      _loadHistory();
    } else if (index == 3) {
      _loadBookmarks();
    }
  }

  void _selectProvider(String providerKey) {
    setState(() {
      _activeProvider = providerKey;
      _selectedTabIndex = 0; // Switch to home view
    });
    _loadHomeCatalog(reset: true);
  }

  void _openDetail(DramaItem drama) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TvDetailScreen(drama: drama),
      ),
    );
    // Refresh history and bookmarks if those tabs are active
    if (_selectedTabIndex == 2) _loadHistory();
    if (_selectedTabIndex == 3) _loadBookmarks();
  }

  Future<void> _performSearch(String q) async {
    final query = q.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchError = '';
      _searchResults = [];
    });

    try {
      final res = await NartoApiService.search(query);
      if (mounted) {
        setState(() {
          _searchResults = res;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _searchError = 'Gagal mencari ($e)';
        });
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Slate 900
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation & Header Bar
            _buildTopBar(),

            // Main View
            Expanded(
              child: _buildCurrentTabContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final tabs = [
      {'icon': Icons.home_rounded, 'label': 'Beranda'},
      {'icon': Icons.grid_view_rounded, 'label': 'Provider (56)'},
      {'icon': Icons.history_rounded, 'label': 'Riwayat'},
      {'icon': Icons.favorite_rounded, 'label': 'Favorit'},
      {'icon': Icons.search_rounded, 'label': 'Cari'},
      {'icon': Icons.settings_rounded, 'label': 'Pengaturan'},
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0B1120),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B), width: 1)),
      ),
      child: Row(
        children: [
          // Logo & TV Brand Tag
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF2D55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.tv_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'NARTO DRAMA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    'TV EDITION',
                    style: TextStyle(
                      color: Color(0xFF38BDF8),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(width: 32),

          // Tabs row
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(tabs.length, (index) {
                  final t = tabs[index];
                  final isSelected = _selectedTabIndex == index;

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TvFocusable(
                      onPressed: () => _onTabChanged(index),
                      borderRadius: BorderRadius.circular(8),
                      backgroundColor: isSelected ? const Color(0xFFFF2D55) : const Color(0xFF1E293B),
                      focusedBackgroundColor: isSelected ? const Color(0xFFFF2D55) : const Color(0xFF334155),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            t['icon'] as IconData,
                            size: 16,
                            color: isSelected ? Colors.white : Colors.white70,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            t['label'] as String,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return _buildHomeTab();
      case 1:
        return _buildProvidersTab();
      case 2:
        return _buildHistoryTab();
      case 3:
        return _buildBookmarksTab();
      case 4:
        return _buildSearchTab();
      case 5:
        return _buildSettingsTab();
      default:
        return const SizedBox.shrink();
    }
  }

  // --- TAB 0: HOME ---
  Widget _buildHomeTab() {
    return Column(
      children: [
        // Horizontal Quick Provider Selector
        Container(
          height: 48,
          margin: const EdgeInsets.fromLTRB(28, 12, 28, 6),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildProviderChip('general', 'Semua Provider'),
              ..._providers.take(12).map((p) => _buildProviderChip(p.key, p.label)),
              TvFocusable(
                onPressed: () => _onTabChanged(1),
                borderRadius: BorderRadius.circular(6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                backgroundColor: const Color(0xFF1E293B),
                child: const Row(
                  children: [
                    Text('Lihat Semua 56...', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold)),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF38BDF8), size: 10),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Grid of Drama Cards
        Expanded(
          child: _homeDramas.isEmpty && _isLoadingHome
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFFFF2D55)),
                      SizedBox(height: 14),
                      Text('Memuat Drama Populer...', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  ),
                )
              : _homeError.isNotEmpty && _homeDramas.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: Color(0xFFFF2D55), size: 48),
                          const SizedBox(height: 12),
                          Text(_homeError, style: const TextStyle(color: Colors.white, fontSize: 14)),
                          const SizedBox(height: 16),
                          TvFocusable(
                            onPressed: () => _loadHomeCatalog(reset: true),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            backgroundColor: const Color(0xFFFF2D55),
                            child: const Text('Coba Lagi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(28, 10, 28, 24),
                      physics: const BouncingScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 6,
                        childAspectRatio: 0.68,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: _homeDramas.length + (_hasMoreHome ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _homeDramas.length) {
                          return Center(
                            child: TvFocusable(
                              onPressed: () => _loadHomeCatalog(reset: false),
                              padding: const EdgeInsets.all(16),
                              backgroundColor: const Color(0xFF1E293B),
                              child: _isLoadingHome
                                  ? const CircularProgressIndicator(color: Color(0xFFFF2D55))
                                  : const Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.expand_more_rounded, color: Colors.white, size: 28),
                                        SizedBox(height: 4),
                                        Text('Muat Lagi', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                            ),
                          );
                        }
                        final drama = _homeDramas[index];
                        return TvDramaCard(
                          drama: drama,
                          onTap: () => _openDetail(drama),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildProviderChip(String key, String label) {
    final isSelected = _activeProvider == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TvFocusable(
        onPressed: () => _selectProvider(key),
        borderRadius: BorderRadius.circular(6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        backgroundColor: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF1E293B),
        focusedBackgroundColor: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? const Color(0xFF0F172A) : Colors.white,
              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  // --- TAB 1: 56 PROVIDERS ---
  Widget _buildProvidersTab() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Semua Provider (${_providers.length})',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              TvFocusable(
                onPressed: _syncProvidersManual,
                borderRadius: BorderRadius.circular(6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                backgroundColor: const Color(0xFF1E293B),
                focusedBackgroundColor: const Color(0xFF38BDF8),
                child: Row(
                  children: [
                    _isSyncingProviders
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.sync_rounded, color: Color(0xFF38BDF8), size: 16),
                    const SizedBox(width: 8),
                    Text(
                      _isSyncingProviders ? 'Menyinkronkan...' : 'Sinkronkan Provider',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: GridView.builder(
              physics: const BouncingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 2.8,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: _providers.length,
              itemBuilder: (context, index) {
                final p = _providers[index];
                final isCurrent = _activeProvider == p.key;

                return TvFocusable(
                  onPressed: () => _selectProvider(p.key),
                  borderRadius: BorderRadius.circular(8),
                  backgroundColor: isCurrent ? const Color(0xFFFF2D55) : const Color(0xFF1E293B),
                  focusedBackgroundColor: isCurrent ? const Color(0xFFFF2D55) : const Color(0xFF334155),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.movie_filter_outlined, color: Color(0xFF38BDF8), size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              p.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            if (p.dramaCount > 0)
                              Text(
                                '${p.dramaCount} drama',
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- TAB 2: RIWAYAT ---
  Widget _buildHistoryTab() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Riwayat Tontonan (${_historyItems.length})',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (_historyItems.isNotEmpty)
                TvFocusable(
                  onPressed: () async {
                    await HistoryBookmarkService.clearAllHistory();
                    _loadHistory();
                  },
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  backgroundColor: const Color(0xFF1E293B),
                  child: const Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, color: Colors.white70, size: 16),
                      SizedBox(width: 6),
                      Text('Hapus Semua', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _historyItems.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history_toggle_off_rounded, color: Colors.white24, size: 56),
                        SizedBox(height: 12),
                        Text('Belum ada riwayat tontonan', style: TextStyle(color: Colors.white38, fontSize: 14)),
                      ],
                    ),
                  )
                : GridView.builder(
                    physics: const BouncingScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 6,
                      childAspectRatio: 0.68,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: _historyItems.length,
                    itemBuilder: (context, index) {
                      final item = _historyItems[index];
                      final drama = DramaItem(
                        id: item.id,
                        title: item.title,
                        posterUrl: item.posterUrl,
                        watchUrl: item.watchUrl,
                        providerKey: item.provider,
                        episodeCount: item.totalEpisodes.toString(),
                      );
                      return TvDramaCard(
                        drama: drama,
                        onTap: () => _openDetail(drama),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // --- TAB 3: BOOKMARKS ---
  Widget _buildBookmarksTab() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Favorit / Bookmark (${_bookmarkItems.length})',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Text(
                'Koleksi drama pilihan tersimpan',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _bookmarkItems.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.favorite_border_rounded, color: Colors.white24, size: 56),
                        SizedBox(height: 12),
                        Text('Belum ada drama favorit tersimpan', style: TextStyle(color: Colors.white38, fontSize: 14)),
                      ],
                    ),
                  )
                : GridView.builder(
                    physics: const BouncingScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 6,
                      childAspectRatio: 0.68,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: _bookmarkItems.length,
                    itemBuilder: (context, index) {
                      final item = _bookmarkItems[index];
                      final drama = DramaItem(
                        id: item.id,
                        title: item.title,
                        posterUrl: item.posterUrl,
                        watchUrl: item.watchUrl,
                        providerKey: item.provider,
                        episodeCount: item.totalEpisodes.toString(),
                      );
                      return TvDramaCard(
                        drama: drama,
                        onTap: () => _openDetail(drama),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // --- TAB 4: CARI ---
  Widget _buildSearchTab() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Input Bar
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Ketik judul drama (misal: CEO, Cinta, Menantu)...',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                      border: InputBorder.none,
                    ),
                    onSubmitted: _performSearch,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              TvFocusable(
                onPressed: () => _performSearch(_searchController.text),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                backgroundColor: const Color(0xFFFF2D55),
                child: const Row(
                  children: [
                    Icon(Icons.search_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 6),
                    Text('Cari', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Search Results
          Expanded(
            child: _isSearching
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Color(0xFFFF2D55)),
                        SizedBox(height: 14),
                        Text('Mencari Drama...', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      ],
                    ),
                  )
                : _searchError.isNotEmpty
                    ? Center(child: Text(_searchError, style: const TextStyle(color: Colors.white70)))
                    : _searchResults.isEmpty
                        ? const Center(
                            child: Text(
                              'Gunakan kolom pencarian di atas untuk menemukan drama.',
                              style: TextStyle(color: Colors.white38, fontSize: 14),
                            ),
                          )
                        : GridView.builder(
                            physics: const BouncingScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 6,
                              childAspectRatio: 0.68,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              final drama = _searchResults[index];
                              return TvDramaCard(
                                drama: drama,
                                onTap: () => _openDetail(drama),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  // --- TAB 5: PENGATURAN ---
  Widget _buildSettingsTab() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 20, 36, 28),
      child: ListView(
        children: [
          const Text(
            'Pengaturan Tampilan & Takarir (TV 10-Foot)',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          // Subtitle Font Size
          _buildSettingSection(
            title: 'Ukuran Font Takarir (Subtitle)',
            subtitle: 'Sesuaikan keterbacaan dari jarak sofa TV',
            child: Row(
              children: [
                _buildOptionChip(
                  label: 'Sedang (22sp)',
                  isSelected: AppSettings.subtitleFontSize == 22.0,
                  onTap: () async {
                    await AppSettings.setSubtitleFontSize(22.0);
                    setState(() {});
                  },
                ),
                const SizedBox(width: 12),
                _buildOptionChip(
                  label: 'Standar TV (26sp)',
                  isSelected: AppSettings.subtitleFontSize == 26.0,
                  onTap: () async {
                    await AppSettings.setSubtitleFontSize(26.0);
                    setState(() {});
                  },
                ),
                const SizedBox(width: 12),
                _buildOptionChip(
                  label: 'Besar (32sp)',
                  isSelected: AppSettings.subtitleFontSize == 32.0,
                  onTap: () async {
                    await AppSettings.setSubtitleFontSize(32.0);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Subtitle Position
          _buildSettingSection(
            title: 'Posisi Vertikal Takarir',
            subtitle: 'Letak teks terjemahan pada video 9:16 vertikal',
            child: Row(
              children: [
                _buildOptionChip(
                  label: 'Tengah Layar',
                  isSelected: AppSettings.subtitlePosition == 'center',
                  onTap: () async {
                    await AppSettings.setSubtitlePosition('center');
                    setState(() {});
                  },
                ),
                const SizedBox(width: 12),
                _buildOptionChip(
                  label: 'Tengah Bawah',
                  isSelected: AppSettings.subtitlePosition == 'middle_bottom',
                  onTap: () async {
                    await AppSettings.setSubtitlePosition('middle_bottom');
                    setState(() {});
                  },
                ),
                const SizedBox(width: 12),
                _buildOptionChip(
                  label: 'Bawah Penuh',
                  isSelected: AppSettings.subtitlePosition == 'bottom',
                  onTap: () async {
                    await AppSettings.setSubtitlePosition('bottom');
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Subtitle Background Toggle
          _buildSettingSection(
            title: 'Latar Belakang Takarir (Kontras Tinggi)',
            subtitle: 'Kotak gelap di balik teks agar mudah dibaca di scene terang',
            child: Row(
              children: [
                _buildOptionChip(
                  label: 'Aktif (80% Hitam)',
                  isSelected: AppSettings.subtitleBgEnabled,
                  onTap: () async {
                    await AppSettings.setSubtitleBgEnabled(true);
                    setState(() {});
                  },
                ),
                const SizedBox(width: 12),
                _buildOptionChip(
                  label: 'Nonaktif (Teks Saja)',
                  isSelected: !AppSettings.subtitleBgEnabled,
                  onTap: () async {
                    await AppSettings.setSubtitleBgEnabled(false);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // TV System Info Box
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: Color(0xFF38BDF8), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Informasi Sistem Narto Drama TV',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('• Versi: v1.0.0 (Android TV Edition)', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                const Text('• Renderer GPU: Skia OpenGL ES Universal (Anti-Glitch / Anti-Green Frame)', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                const Text('• Navigasi: Remote D-Pad 10-Foot Focus Traversal (Up/Down/Left/Right/OK)', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                const Text('• Kompatibilitas: Android TV 7.0 (API 24) s.d Android TV 15 (API 35)', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    TvFocusable(
                      onPressed: () {
                        PaintingBinding.instance.imageCache.clear();
                        PaintingBinding.instance.imageCache.clearLiveImages();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Cache gambar berhasil dibersihkan')),
                        );
                      },
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      backgroundColor: const Color(0xFF334155),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cleaning_services_rounded, color: Colors.white, size: 16),
                          SizedBox(width: 8),
                          Text('Bersihkan Cache Gambar', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    TvFocusable(
                      onPressed: _syncProvidersManual,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      backgroundColor: const Color(0xFF0284C7),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _isSyncingProviders
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.sync_rounded, color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            _isSyncingProviders ? 'Menyinkronkan...' : 'Sinkronkan Daftar Provider',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingSection({required String title, required String subtitle, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 10),
        child,
      ],
    );
  }

  Widget _buildOptionChip({required String label, required bool isSelected, required VoidCallback onTap}) {
    return TvFocusable(
      onPressed: onTap,
      borderRadius: BorderRadius.circular(6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      backgroundColor: isSelected ? const Color(0xFFFF2D55) : const Color(0xFF1E293B),
      focusedBackgroundColor: isSelected ? const Color(0xFFFF2D55) : const Color(0xFF334155),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}
