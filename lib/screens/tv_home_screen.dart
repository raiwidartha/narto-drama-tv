import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final List<FocusNode> _tabFocusNodes = List.generate(6, (_) => FocusNode());

  // Dedicated remote entry focus nodes
  final FocusNode _firstHomeFocusNode = FocusNode();
  final FocusNode _firstProviderFocusNode = FocusNode();
  final FocusNode _firstHistoryFocusNode = FocusNode();
  final FocusNode _firstBookmarkFocusNode = FocusNode();
  final FocusNode _searchInputFocusNode = FocusNode();
  final FocusNode _searchClearFocusNode = FocusNode();
  final FocusNode _searchSubmitBtnFocusNode = FocusNode();
  final FocusNode _settingsFirstFocusNode = FocusNode();
  final ScrollController _settingsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _tabFocusNodes.isNotEmpty) {
        _tabFocusNodes[0].requestFocus();
      }
    });
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
      final res = await NartoApiService.fetchProviderSections(provider: 'melolo');
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
        setState(() {
          _providers = AppSettings.allProviders;
          _isSyncingProviders = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Daftar provider dimuat dari database: ${_providers.length} provider.'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _providers = AppSettings.allProviders;
        _isSyncingProviders = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sinkronisasi memakai database lokal: ${_providers.length} provider.'),
            backgroundColor: const Color(0xFF38BDF8),
          ),
        );
      }
    }
  }

  void _onTabChanged(int index) {
    setState(() {
      _selectedTabIndex = index;
    });
    if (index >= 0 && index < _tabFocusNodes.length) {
      _tabFocusNodes[index].requestFocus();
    }
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
    for (final node in _tabFocusNodes) {
      node.dispose();
    }
    _firstHomeFocusNode.dispose();
    _firstProviderFocusNode.dispose();
    _firstHistoryFocusNode.dispose();
    _firstBookmarkFocusNode.dispose();
    _searchInputFocusNode.dispose();
    _searchClearFocusNode.dispose();
    _searchSubmitBtnFocusNode.dispose();
    _settingsFirstFocusNode.dispose();
    _settingsScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<bool> _showExitConfirmationDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.power_settings_new_rounded, color: Color(0xFFFF2D55), size: 28),
              SizedBox(width: 12),
              Text(
                'Keluar dari Narto Drama TV?',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Text(
            'Apakah Anda yakin ingin menutup aplikasi Narto Drama TV?',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
          ),
          actions: [
            TvFocusable(
              autofocus: true,
              onPressed: () => Navigator.of(ctx).pop(false),
              borderRadius: BorderRadius.circular(8),
              backgroundColor: const Color(0xFF334155),
              focusedBackgroundColor: const Color(0xFF475569),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: const Text('Batal / Tetap di Aplikasi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            TvFocusable(
              onPressed: () => Navigator.of(ctx).pop(true),
              borderRadius: BorderRadius.circular(8),
              backgroundColor: const Color(0xFFFF2D55),
              focusedBackgroundColor: const Color(0xFFFF5377),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              child: const Text('Keluar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_selectedTabIndex != 0) {
          _onTabChanged(0);
          return;
        }
        final shouldExit = await _showExitConfirmationDialog();
        if (shouldExit == true) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
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
                      focusNode: index < _tabFocusNodes.length ? _tabFocusNodes[index] : null,
                      autofocus: index == 0,
                      onPressed: () {
                        if (_selectedTabIndex == index) {
                          if (index == 4) {
                            _searchInputFocusNode.requestFocus();
                            _openTvSearchDialog();
                          } else if (index == 5) {
                            _settingsFirstFocusNode.requestFocus();
                          }
                        } else {
                          _onTabChanged(index);
                        }
                      },
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          if (index == 0) {
                            _firstHomeFocusNode.requestFocus();
                            return KeyEventResult.handled;
                          } else if (index == 1) {
                            _firstProviderFocusNode.requestFocus();
                            return KeyEventResult.handled;
                          } else if (index == 2) {
                            _firstHistoryFocusNode.requestFocus();
                            return KeyEventResult.handled;
                          } else if (index == 3) {
                            _firstBookmarkFocusNode.requestFocus();
                            return KeyEventResult.handled;
                          } else if (index == 4) {
                            _searchInputFocusNode.requestFocus();
                            return KeyEventResult.handled;
                          } else if (index == 5) {
                            _settingsFirstFocusNode.requestFocus();
                            _settingsScrollController.animateTo(
                              0.0,
                              duration: const Duration(milliseconds: 150),
                              curve: Curves.easeOut,
                            );
                            return KeyEventResult.handled;
                          }
                        }
                        return KeyEventResult.ignored;
                      },
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
              _buildProviderChip('general', 'Semua Provider', count: 0),
              ..._providers.take(16).map((p) => _buildProviderChip(p.key, p.label, count: p.dramaCount)),
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
                          focusNode: index == 0 ? _firstHomeFocusNode : null,
                          onTap: () => _openDetail(drama),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildProviderChip(String key, String label, {int count = 0}) {
    final isSelected = _activeProvider == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TvFocusable(
        onPressed: () => _selectProvider(key),
        borderRadius: BorderRadius.circular(6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        backgroundColor: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF1E293B),
        focusedBackgroundColor: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF0F172A) : Colors.white,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                fontSize: 12,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.black26 : const Color(0xFF38BDF8).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF38BDF8),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
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
                  focusNode: index == 0 ? _firstProviderFocusNode : null,
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
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    p.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                if (p.dramaCount > 0) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: isCurrent ? Colors.white24 : const Color(0xFF38BDF8).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${p.dramaCount}',
                                      style: TextStyle(
                                        color: isCurrent ? Colors.white : const Color(0xFF38BDF8),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              p.dramaCount > 0 ? '${p.dramaCount} drama' : 'Katalog drama',
                              style: TextStyle(color: isCurrent ? Colors.white70 : const Color(0xFF94A3B8), fontSize: 11),
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
                        focusNode: index == 0 ? _firstHistoryFocusNode : null,
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
                        focusNode: index == 0 ? _firstBookmarkFocusNode : null,
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
  void _openTvSearchDialog() {
    final dialogController = TextEditingController(text: _searchController.text);
    final focusNode = FocusNode();
    final cancelBtnFocus = FocusNode();
    final submitBtnFocus = FocusNode();

    showDialog(
      context: context,
      builder: (ctx) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          focusNode.requestFocus();
        });

        return AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.search_rounded, color: Color(0xFFFF2D55), size: 24),
              SizedBox(width: 10),
              Text(
                'Ketik Judul Drama',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFF2D55), width: 1.5),
                  ),
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        submitBtnFocus.requestFocus();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: dialogController,
                      focusNode: focusNode,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      decoration: const InputDecoration(
                        hintText: 'Masukkan judul drama...',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                        border: InputBorder.none,
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (val) {
                        Navigator.of(ctx).pop();
                        _searchController.text = val;
                        _performSearch(val);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Ketik dengan keyboard virtual remote TV, lalu tekan Cari / Submit.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TvFocusable(
              focusNode: cancelBtnFocus,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    focusNode.requestFocus();
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                    submitBtnFocus.requestFocus();
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              onPressed: () => Navigator.of(ctx).pop(),
              borderRadius: BorderRadius.circular(8),
              backgroundColor: const Color(0xFF1E293B),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: const Text('Batal', style: TextStyle(color: Colors.white70)),
            ),
            TvFocusable(
              focusNode: submitBtnFocus,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    focusNode.requestFocus();
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                    cancelBtnFocus.requestFocus();
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              onPressed: () {
                final query = dialogController.text.trim();
                Navigator.of(ctx).pop();
                _searchController.text = query;
                _performSearch(query);
              },
              borderRadius: BorderRadius.circular(8),
              backgroundColor: const Color(0xFFFF2D55),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: const Text('Cari Sekarang', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchTab() {
    final queryText = _searchController.text.trim();
    final quickKeywords = [
      'CEO',
      'Cinta',
      'Menantu',
      'Balas Dendam',
      'Presiden',
      'Pernikahan',
      'Miliarder',
      'Dokter',
      'Keluarga',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Input Bar (Focusable D-Pad Card)
          Row(
            children: [
              Expanded(
                child: TvFocusable(
                  focusNode: _searchInputFocusNode,
                  autofocus: true,
                  onPressed: _openTvSearchDialog,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        _tabFocusNodes[4].requestFocus();
                        return KeyEventResult.handled;
                      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                        if (queryText.isNotEmpty) {
                          _searchClearFocusNode.requestFocus();
                        } else {
                          _searchSubmitBtnFocusNode.requestFocus();
                        }
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  borderRadius: BorderRadius.circular(10),
                  backgroundColor: const Color(0xFF1E293B),
                  focusedBackgroundColor: const Color(0xFF334155),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, color: Color(0xFFFF2D55), size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          queryText.isNotEmpty ? queryText : 'Tekan OK di sini untuk mengetik judul drama...',
                          style: TextStyle(
                            color: queryText.isNotEmpty ? Colors.white : Colors.white38,
                            fontSize: 14,
                            fontWeight: queryText.isNotEmpty ? FontWeight.w600 : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (queryText.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Ubah', style: TextStyle(color: Colors.white70, fontSize: 11)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (queryText.isNotEmpty) ...[
                TvFocusable(
                  focusNode: _searchClearFocusNode,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        _tabFocusNodes[4].requestFocus();
                        return KeyEventResult.handled;
                      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                        _searchInputFocusNode.requestFocus();
                        return KeyEventResult.handled;
                      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                        _searchSubmitBtnFocusNode.requestFocus();
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _searchResults = [];
                      _searchError = '';
                    });
                  },
                  borderRadius: BorderRadius.circular(10),
                  backgroundColor: const Color(0xFF1E293B),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: const Row(
                    children: [
                      Icon(Icons.clear_rounded, color: Colors.white70, size: 18),
                      SizedBox(width: 6),
                      Text('Hapus', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
              ],
              TvFocusable(
                focusNode: _searchSubmitBtnFocusNode,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      _tabFocusNodes[4].requestFocus();
                      return KeyEventResult.handled;
                    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                      if (queryText.isNotEmpty) {
                        _searchClearFocusNode.requestFocus();
                      } else {
                        _searchInputFocusNode.requestFocus();
                      }
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                onPressed: () {
                  if (_searchController.text.trim().isNotEmpty) {
                    _performSearch(_searchController.text);
                  } else {
                    _openTvSearchDialog();
                  }
                },
                borderRadius: BorderRadius.circular(10),
                backgroundColor: const Color(0xFFFF2D55),
                focusedBackgroundColor: const Color(0xFFFF5377),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: const Row(
                  children: [
                    Icon(Icons.search_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Cari', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Quick Keywords Row (D-Pad remote friendly)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Row(
                  children: [
                    Icon(Icons.bolt_rounded, color: Color(0xFFFBBF24), size: 16),
                    SizedBox(width: 4),
                    Text('Saran Cepat: ', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(width: 8),
                ...quickKeywords.map((kw) {
                  final isCurrent = queryText.toLowerCase() == kw.toLowerCase();
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TvFocusable(
                      onPressed: () {
                        setState(() {
                          _searchController.text = kw;
                        });
                        _performSearch(kw);
                      },
                      borderRadius: BorderRadius.circular(6),
                      backgroundColor: isCurrent ? const Color(0xFFFF2D55) : const Color(0xFF1E293B),
                      focusedBackgroundColor: isCurrent ? const Color(0xFFFF2D55) : const Color(0xFF334155),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Text(
                        kw,
                        style: TextStyle(
                          color: isCurrent ? Colors.white : Colors.white70,
                          fontSize: 11,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
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
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_rounded, size: 48, color: Colors.white.withValues(alpha: 0.15)),
                                const SizedBox(height: 12),
                                Text(
                                  queryText.isNotEmpty
                                      ? 'Tidak ada hasil untuk "$queryText"'
                                      : 'Pilih kolom di atas atau tekan saran kata kunci untuk mencari drama.',
                                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                                ),
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
  void _showHostConfigDialog() {
    final textController = TextEditingController(text: AppSettings.baseUrl);
    bool isTesting = false;
    String testResult = '';
    bool? testSuccess;

    final preset1Focus = FocusNode();
    final preset2Focus = FocusNode();
    final hostFieldFocus = FocusNode();
    final testBtnFocus = FocusNode();
    final cancelBtnFocus = FocusNode();
    final saveBtnFocus = FocusNode();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.dns_rounded, color: Color(0xFF38BDF8), size: 26),
                  SizedBox(width: 10),
                  Text('Konfigurasi API Host Upstream', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Pilih Preset Host:', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TvFocusable(
                          focusNode: preset1Focus,
                          onKeyEvent: (node, event) {
                            if (event is KeyDownEvent) {
                              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                hostFieldFocus.requestFocus();
                                return KeyEventResult.handled;
                              } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                                preset2Focus.requestFocus();
                                return KeyEventResult.handled;
                              }
                            }
                            return KeyEventResult.ignored;
                          },
                          onPressed: () {
                            textController.text = 'https://narto-drama.com';
                            setDialogState(() {
                              testResult = '';
                              testSuccess = null;
                            });
                          },
                          borderRadius: BorderRadius.circular(6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          backgroundColor: textController.text == 'https://narto-drama.com' ? const Color(0xFF0284C7) : const Color(0xFF334155),
                          child: const Text('Resmi (narto-drama.com)', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        TvFocusable(
                          focusNode: preset2Focus,
                          onKeyEvent: (node, event) {
                            if (event is KeyDownEvent) {
                              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                hostFieldFocus.requestFocus();
                                return KeyEventResult.handled;
                              } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                                preset1Focus.requestFocus();
                                return KeyEventResult.handled;
                              }
                            }
                            return KeyEventResult.ignored;
                          },
                          onPressed: () {
                            textController.text = 'https://narto-drama.vercel.app';
                            setDialogState(() {
                              testResult = '';
                              testSuccess = null;
                            });
                          },
                          borderRadius: BorderRadius.circular(6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          backgroundColor: textController.text == 'https://narto-drama.vercel.app' ? const Color(0xFF0284C7) : const Color(0xFF334155),
                          child: const Text('Mirror Edge Vercel', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('URL Endpoint Upstream:', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TvFocusable(
                      focusNode: hostFieldFocus,
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent) {
                          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                            testBtnFocus.requestFocus();
                            return KeyEventResult.handled;
                          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                            preset1Focus.requestFocus();
                            return KeyEventResult.handled;
                          }
                        }
                        return KeyEventResult.ignored;
                      },
                      onPressed: () async {
                        final editController = TextEditingController(text: textController.text);
                        final customUrl = await showDialog<String>(
                          context: dialogCtx,
                          builder: (editCtx) {
                            return AlertDialog(
                              backgroundColor: const Color(0xFF0F172A),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              title: const Text('Ketik URL Endpoint Host', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                              content: TextField(
                                controller: editController,
                                autofocus: true,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: const InputDecoration(
                                  hintText: 'https://...',
                                  hintStyle: TextStyle(color: Colors.white38),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(editCtx).pop(),
                                  child: const Text('Batal', style: TextStyle(color: Colors.white54)),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.of(editCtx).pop(editController.text.trim()),
                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF2D55)),
                                  child: const Text('Gunakan URL Ini', style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            );
                          },
                        );
                        if (customUrl != null && customUrl.isNotEmpty) {
                          textController.text = customUrl;
                          setDialogState(() {
                            testResult = '';
                            testSuccess = null;
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      backgroundColor: const Color(0xFF0F172A),
                      focusedBackgroundColor: const Color(0xFF1E293B),
                      focusBorderColor: const Color(0xFF38BDF8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              textController.text.isNotEmpty ? textController.text : 'https://...',
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.edit_rounded, color: Color(0xFF38BDF8), size: 16),
                          const SizedBox(width: 4),
                          const Text('Ubah', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TvFocusable(
                          focusNode: testBtnFocus,
                          onKeyEvent: (node, event) {
                            if (event is KeyDownEvent) {
                              if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                hostFieldFocus.requestFocus();
                                return KeyEventResult.handled;
                              } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                saveBtnFocus.requestFocus();
                                return KeyEventResult.handled;
                              }
                            }
                            return KeyEventResult.ignored;
                          },
                          onPressed: isTesting
                              ? null
                              : () async {
                                  setDialogState(() {
                                    isTesting = true;
                                    testResult = 'Menguji respon host...';
                                    testSuccess = null;
                                  });
                                  final res = await AppSettings.testConnection(textController.text);
                                  setDialogState(() {
                                    isTesting = false;
                                    testSuccess = res['success'] == true;
                                    testResult = res['message']?.toString() ?? '';
                                  });
                                },
                          borderRadius: BorderRadius.circular(6),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          backgroundColor: const Color(0xFF334155),
                          focusedBackgroundColor: const Color(0xFF475569),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              isTesting
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.speed_rounded, color: Color(0xFF38BDF8), size: 16),
                              const SizedBox(width: 6),
                              const Text('Uji Latensi & Respon', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (testResult.isNotEmpty)
                          Expanded(
                            child: Text(
                              testResult,
                              style: TextStyle(
                                color: testSuccess == true ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TvFocusable(
                  focusNode: cancelBtnFocus,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        testBtnFocus.requestFocus();
                        return KeyEventResult.handled;
                      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                        saveBtnFocus.requestFocus();
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  onPressed: () => Navigator.of(ctx).pop(),
                  borderRadius: BorderRadius.circular(8),
                  backgroundColor: const Color(0xFF334155),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: const Text('Batal', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                TvFocusable(
                  focusNode: saveBtnFocus,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        testBtnFocus.requestFocus();
                        return KeyEventResult.handled;
                      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                        cancelBtnFocus.requestFocus();
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  onPressed: () async {
                    final target = textController.text.trim();
                    if (target.isNotEmpty) {
                      await AppSettings.setBaseUrl(target);
                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }
                      if (mounted) {
                        setState(() {});
                        _loadHomeCatalog(reset: true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Host berhasil diubah ke: $target'),
                            backgroundColor: const Color(0xFF10B981),
                          ),
                        );
                      }
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  backgroundColor: const Color(0xFFFF2D55),
                  focusedBackgroundColor: const Color(0xFFFF5377),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: const Text('Simpan & Terapkan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSettingsTab() {
    final isCustomHost = AppSettings.isCustomBaseUrl;

    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 16, 36, 28),
      child: SingleChildScrollView(
        controller: _settingsScrollController,
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pengaturan Narto Drama TV',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // 1. API Host Configuration Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isCustomHost ? const Color(0xFF38BDF8) : Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.dns_rounded, color: Color(0xFF38BDF8), size: 22),
                      const SizedBox(width: 10),
                      const Text('API Host Upstream', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isCustomHost ? const Color(0xFF0284C7).withValues(alpha: 0.2) : const Color(0xFF10B981).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: isCustomHost ? const Color(0xFF38BDF8) : const Color(0xFF10B981)),
                        ),
                        child: Text(
                          isCustomHost ? 'Mirror Kustom' : 'Resmi Default',
                          style: TextStyle(
                            color: isCustomHost ? const Color(0xFF38BDF8) : const Color(0xFF10B981),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    AppSettings.baseUrl,
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      TvFocusable(
                        focusNode: _settingsFirstFocusNode,
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp) {
                            _tabFocusNodes[5].requestFocus();
                            _settingsScrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        onPressed: _showHostConfigDialog,
                        borderRadius: BorderRadius.circular(6),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        backgroundColor: const Color(0xFF0284C7),
                        focusedBackgroundColor: const Color(0xFF38BDF8),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit_rounded, color: Colors.white, size: 16),
                            SizedBox(width: 8),
                            Text('Ganti Host Upstream', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    if (isCustomHost) ...[
                      const SizedBox(width: 12),
                      TvFocusable(
                        onPressed: () async {
                          await AppSettings.resetToDefault();
                          setState(() {});
                          _loadHomeCatalog(reset: true);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Host dikembalikan ke upstream resmi (narto-drama.com)'),
                                backgroundColor: Color(0xFF10B981),
                              ),
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(6),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        backgroundColor: const Color(0xFF334155),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.restore_rounded, color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text('Kembalikan ke Default', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 2. Subtitle Live Preview Box
          Container(
            height: 90,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Stack(
              children: [
                const Positioned(
                  left: 12,
                  top: 8,
                  child: Text(
                    'Pratinjau Takarir Langsung (Live Preview)',
                    style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppSettings.subtitleBgEnabled
                          ? Color(AppSettings.subtitleBgColor).withValues(alpha: AppSettings.subtitleBgOpacity)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Tampilan takarir di layar TV Anda saat menonton drama',
                      style: TextStyle(
                        fontSize: AppSettings.subtitleFontSize * 0.8,
                        color: Color(AppSettings.subtitleFontColor),
                        fontWeight: AppSettings.effectiveFontWeight,
                        fontFamily: AppSettings.effectiveFontFamily,
                        shadows: [
                          Shadow(
                            offset: const Offset(1.5, 1.5),
                            blurRadius: 4.0,
                            color: Colors.black.withValues(alpha: 0.9),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 3. Subtitle Font Size (Default: Sedang 24sp)
          _buildSettingSection(
            title: 'Ukuran Font Takarir (Subtitle)',
            subtitle: 'Sesuaikan keterbacaan dari jarak sofa TV (Default: Sedang 24sp)',
            child: Row(
              children: [
                _buildOptionChip(
                  label: 'Kecil (18sp)',
                  isSelected: AppSettings.subtitleFontSize == 18.0,
                  onTap: () async {
                    await AppSettings.setSubtitleFontSize(18.0);
                    setState(() {});
                  },
                ),
                const SizedBox(width: 10),
                _buildOptionChip(
                  label: 'Sedang (24sp) • Default',
                  isSelected: AppSettings.subtitleFontSize == 24.0,
                  onTap: () async {
                    await AppSettings.setSubtitleFontSize(24.0);
                    setState(() {});
                  },
                ),
                const SizedBox(width: 10),
                _buildOptionChip(
                  label: 'Besar (28sp)',
                  isSelected: AppSettings.subtitleFontSize == 28.0,
                  onTap: () async {
                    await AppSettings.setSubtitleFontSize(28.0);
                    setState(() {});
                  },
                ),
                const SizedBox(width: 10),
                _buildOptionChip(
                  label: 'Sangat Besar (34sp)',
                  isSelected: AppSettings.subtitleFontSize == 34.0,
                  onTap: () async {
                    await AppSettings.setSubtitleFontSize(34.0);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 4. Subtitle Font Weight (Bold)
          _buildSettingSection(
            title: 'Ketebalan Huruf (Font Weight)',
            subtitle: 'Pilih ketebalan teks takarir agar lebih tegas di TV',
            child: Row(
              children: [
                _buildOptionChip(
                  label: 'Normal (w400)',
                  isSelected: AppSettings.subtitleFontWeight == 'normal',
                  onTap: () async {
                    await AppSettings.setSubtitleFontWeight('normal');
                    setState(() {});
                  },
                ),
                const SizedBox(width: 10),
                _buildOptionChip(
                  label: 'Sedang (w500)',
                  isSelected: AppSettings.subtitleFontWeight == 'medium',
                  onTap: () async {
                    await AppSettings.setSubtitleFontWeight('medium');
                    setState(() {});
                  },
                ),
                const SizedBox(width: 10),
                _buildOptionChip(
                  label: 'Tebal (Bold) • Default',
                  isSelected: AppSettings.subtitleFontWeight == 'bold',
                  onTap: () async {
                    await AppSettings.setSubtitleFontWeight('bold');
                    setState(() {});
                  },
                ),
                const SizedBox(width: 10),
                _buildOptionChip(
                  label: 'Sangat Tebal (Black)',
                  isSelected: AppSettings.subtitleFontWeight == 'black',
                  onTap: () async {
                    await AppSettings.setSubtitleFontWeight('black');
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 5. Subtitle Font Family
          _buildSettingSection(
            title: 'Jenis Huruf (Font Family)',
            subtitle: 'Gaya tipografi teks takarir',
            child: Row(
              children: [
                _buildOptionChip(
                  label: 'Sans-serif (Standar)',
                  isSelected: AppSettings.subtitleFontFamily == 'sans-serif',
                  onTap: () async {
                    await AppSettings.setSubtitleFontFamily('sans-serif');
                    setState(() {});
                  },
                ),
                const SizedBox(width: 10),
                _buildOptionChip(
                  label: 'Monospace (Mesin Ketik)',
                  isSelected: AppSettings.subtitleFontFamily == 'monospace',
                  onTap: () async {
                    await AppSettings.setSubtitleFontFamily('monospace');
                    setState(() {});
                  },
                ),
                const SizedBox(width: 10),
                _buildOptionChip(
                  label: 'Serif (Klasik)',
                  isSelected: AppSettings.subtitleFontFamily == 'serif',
                  onTap: () async {
                    await AppSettings.setSubtitleFontFamily('serif');
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 6. Subtitle Color
          _buildSettingSection(
            title: 'Warna Teks Takarir',
            subtitle: 'Pilih warna teks terjemahan yang nyaman di mata',
            child: Row(
              children: [
                _buildColorChip('Putih', 0xFFFFFFFF),
                const SizedBox(width: 10),
                _buildColorChip('Kuning Terang', 0xFFFACC15),
                const SizedBox(width: 10),
                _buildColorChip('Hijau Neon', 0xFF4ADE80),
                const SizedBox(width: 10),
                _buildColorChip('Sian Biru', 0xFF38BDF8),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 7. Subtitle Background
          _buildSettingSection(
            title: 'Latar Belakang Takarir (Kontras Layar)',
            subtitle: 'Kotak pelindung teks di belakang subtitle untuk keterbacaan tinggi',
            child: Row(
              children: [
                _buildOptionChip(
                  label: 'Hitam Transparan (80%)',
                  isSelected: AppSettings.subtitleBgEnabled && AppSettings.subtitleBgOpacity < 0.9,
                  onTap: () async {
                    await AppSettings.setSubtitleBgEnabled(true);
                    await AppSettings.setSubtitleBgOpacity(0.80);
                    setState(() {});
                  },
                ),
                const SizedBox(width: 10),
                _buildOptionChip(
                  label: 'Hitam Pekat (100%)',
                  isSelected: AppSettings.subtitleBgEnabled && AppSettings.subtitleBgOpacity >= 0.9,
                  onTap: () async {
                    await AppSettings.setSubtitleBgEnabled(true);
                    await AppSettings.setSubtitleBgOpacity(1.0);
                    setState(() {});
                  },
                ),
                const SizedBox(width: 10),
                _buildOptionChip(
                  label: 'Bayangan Saja (Tanpa Kotak)',
                  isSelected: !AppSettings.subtitleBgEnabled,
                  onTap: () async {
                    await AppSettings.setSubtitleBgEnabled(false);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 8. Preset Subtitle Vertical Position
          _buildSettingSection(
            title: 'Preset Posisi Vertikal Takarir',
            subtitle: 'Pilih posisi standar teks terjemahan di layar TV',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildOptionChip(
                  label: 'Atas (15%)',
                  isSelected: AppSettings.subtitlePosition == 'top',
                  onTap: () async {
                    await AppSettings.setSubtitlePosition('top');
                    setState(() {});
                  },
                ),
                _buildOptionChip(
                  label: 'Tengah Atas (32%)',
                  isSelected: AppSettings.subtitlePosition == 'middle_top',
                  onTap: () async {
                    await AppSettings.setSubtitlePosition('middle_top');
                    setState(() {});
                  },
                ),
                _buildOptionChip(
                  label: 'Tengah Layar (50%) • Default',
                  isSelected: AppSettings.subtitlePosition == 'center',
                  onTap: () async {
                    await AppSettings.setSubtitlePosition('center');
                    setState(() {});
                  },
                ),
                _buildOptionChip(
                  label: 'Tengah Bawah (65%)',
                  isSelected: AppSettings.subtitlePosition == 'middle_bottom',
                  onTap: () async {
                    await AppSettings.setSubtitlePosition('middle_bottom');
                    setState(() {});
                  },
                ),
                _buildOptionChip(
                  label: 'Bawah Penuh (85%)',
                  isSelected: AppSettings.subtitlePosition == 'bottom',
                  onTap: () async {
                    await AppSettings.setSubtitlePosition('bottom');
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 9. Manual Vertical Position Stepper (5% - 95%)
          _buildSettingSection(
            title: 'Atur Posisi Vertikal Manual (Stepper Nudge)',
            subtitle: 'Geser posisi subtitle naik/turun per 5% agar pas dengan subtitle bawaan video',
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF38BDF8)),
                  ),
                  child: Text(
                    'Posisi: ${(AppSettings.subtitleVerticalOffset * 100).toInt()}% dari batas atas',
                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 14),
                TvFocusable(
                  onPressed: () async {
                    final cur = AppSettings.subtitleVerticalOffset;
                    await AppSettings.setSubtitleVerticalOffset(cur - 0.05);
                    setState(() {});
                  },
                  borderRadius: BorderRadius.circular(6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  backgroundColor: const Color(0xFF334155),
                  focusedBackgroundColor: const Color(0xFF38BDF8),
                  child: const Row(
                    children: [
                      Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text('Naikkan (-5%)', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                TvFocusable(
                  onPressed: () async {
                    final cur = AppSettings.subtitleVerticalOffset;
                    await AppSettings.setSubtitleVerticalOffset(cur + 0.05);
                    setState(() {});
                  },
                  borderRadius: BorderRadius.circular(6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  backgroundColor: const Color(0xFF334155),
                  focusedBackgroundColor: const Color(0xFF38BDF8),
                  child: const Row(
                    children: [
                      Icon(Icons.arrow_downward_rounded, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text('Turunkan (+5%)', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                TvFocusable(
                  onPressed: () async {
                    await AppSettings.setSubtitleVerticalOffset(0.50);
                    setState(() {});
                  },
                  borderRadius: BorderRadius.circular(6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  backgroundColor: const Color(0xFF334155),
                  focusedBackgroundColor: const Color(0xFFFF2D55),
                  child: const Text('Reset Tengah (50%)', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // 10. TV System Info Box
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
                const Text('• Versi: v1.0.1 (Android TV Edition)', style: TextStyle(color: Colors.white70, fontSize: 12)),
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
    ),
  );
}

  Widget _buildColorChip(String label, int colorValue) {
    final isSelected = AppSettings.subtitleFontColor == colorValue;
    return TvFocusable(
      onPressed: () async {
        await AppSettings.setSubtitleFontColor(colorValue);
        setState(() {});
      },
      borderRadius: BorderRadius.circular(6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      backgroundColor: isSelected ? const Color(0xFFFF2D55) : const Color(0xFF1E293B),
      focusedBackgroundColor: isSelected ? const Color(0xFFFF5277) : const Color(0xFF334155),
      focusBorderColor: isSelected ? Colors.white : const Color(0xFFFF2D55),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: Color(colorValue),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white70, width: 1.5),
            ),
          ),
          const SizedBox(width: 8),
          if (isSelected) ...[
            const Icon(Icons.check_circle_rounded, size: 14, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
              fontSize: 12,
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
      focusedBackgroundColor: isSelected ? const Color(0xFFFF5277) : const Color(0xFF334155),
      focusBorderColor: isSelected ? Colors.white : const Color(0xFFFF2D55),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSelected) ...[
            const Icon(Icons.check_circle_rounded, size: 14, color: Colors.white),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
