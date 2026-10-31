import 'dart:async';
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

  // Home tab state (independent feed & pagination)
  List<DramaItem> _homeDramas = [];
  List<DramaItem> _allHomeDramas = [];
  bool _isLoadingHome = false;
  String _homeError = '';
  int _homePage = 1;
  int _homeCurrentPage = 1;
  int _homeTotalPages = 1;
  static const int _homePageSize = 18;
  bool _hasMoreHome = true;

  // Topbar ping indicator state
  int? _pingMs;
  bool _isTestingPing = false;
  bool _pingSuccess = true;
  Timer? _pingAutoTimer;
  final FocusNode _pingFocusNode = FocusNode();

  // Home pagination focus nodes
  final FocusNode _homePrevPageFocusNode = FocusNode();
  final FocusNode _homeNextPageFocusNode = FocusNode();
  final FocusNode _homeBottomPrevFocusNode = FocusNode();
  final FocusNode _homeBottomNextFocusNode = FocusNode();

  // Provider tab state (independent feed)
  String _selectedProviderKey = 'melolo';
  List<DramaItem> _providerDramas = [];
  bool _isLoadingProviderDramas = false;
  String _providerError = '';
  int _providerPage = 1;
  bool _hasMoreProviderDramas = true;

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
  final FocusNode _firstHomeDramaFocusNode = FocusNode();
  final FocusNode _homeRefreshFocusNode = FocusNode();
  final FocusNode _homeFilterFocusNode = FocusNode();
  final FocusNode _firstProviderFocusNode = FocusNode();
  final FocusNode _firstProviderDramaFocusNode = FocusNode();
  final FocusNode _providerSyncFocusNode = FocusNode();
  final Map<String, FocusNode> _providerChipFocusNodes = {};
  final FocusNode _firstHistoryFocusNode = FocusNode();
  final FocusNode _firstBookmarkFocusNode = FocusNode();
  final FocusNode _searchInputFocusNode = FocusNode();
  final FocusNode _searchClearFocusNode = FocusNode();
  final FocusNode _searchSubmitBtnFocusNode = FocusNode();
  final FocusNode _firstQuickKeywordFocusNode = FocusNode();
  final FocusNode _firstSearchResultFocusNode = FocusNode();
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
        if (_providers.isNotEmpty) {
          _selectedProviderKey = _providers.first.key;
        }
      });
      _loadHomeCatalog(reset: true);
      _runPingTest();
      _pingAutoTimer?.cancel();
      _pingAutoTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        if (mounted) _runPingTest();
      });
    }
  }

  Future<void> _runPingTest() async {
    if (_isTestingPing) return;
    if (mounted) setState(() => _isTestingPing = true);
    try {
      final res = await AppSettings.testConnection(AppSettings.baseUrl);
      if (mounted) {
        setState(() {
          _isTestingPing = false;
          _pingSuccess = res['success'] == true;
          _pingMs = res['latencyMs'] as int?;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isTestingPing = false;
          _pingSuccess = false;
          _pingMs = null;
        });
      }
    }
  }

  String _getActiveMergedProviderNames() {
    final active = AppSettings.homeMergedProviders.isNotEmpty
        ? AppSettings.homeMergedProviders
        : AppSettings.defaultMergedProviders;
    final all = _providers.isNotEmpty ? _providers : AppSettings.allProviders;
    final labels = <String>[];
    for (final key in active) {
      final match = all.firstWhere((p) => p.key.toLowerCase() == key.toLowerCase(),
          orElse: () => ProviderInfo(key: key, label: key));
      labels.add(match.label);
    }
    if (labels.length <= 4) {
      return labels.join(', ');
    }
    return '${labels.take(3).join(', ')} +${labels.length - 3} lainnya';
  }

  int _getMergedProviderCount() {
    return AppSettings.homeMergedProviders.isNotEmpty
        ? AppSettings.homeMergedProviders.length
        : AppSettings.defaultMergedProviders.length;
  }

  void _showProviderFilterModal() {
    final availableProviders = _providers.isNotEmpty ? _providers : AppSettings.allProviders;
    final Set<String> selectedKeys = Set<String>.from(
      AppSettings.homeMergedProviders.isNotEmpty
          ? AppSettings.homeMergedProviders
          : AppSettings.defaultMergedProviders,
    );

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF334155)),
              ),
              title: Row(
                children: [
                  const Icon(Icons.checklist_rounded, color: Color(0xFF00E5FF), size: 24),
                  const SizedBox(width: 10),
                  const Text(
                    'Pilih Provider Beranda',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF38BDF8)),
                    ),
                    child: Text(
                      '${selectedKeys.length} / ${availableProviders.length} Terpilih',
                      style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 720,
                height: 420,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pilih provider mana saja yang ingin digabung menjadi satu di feed Beranda:',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    // Quick Action Buttons
                    Row(
                      children: [
                        TvFocusable(
                          onPressed: () {
                            setDialogState(() {
                              selectedKeys.clear();
                              selectedKeys.addAll(availableProviders.map((p) => p.key));
                            });
                          },
                          borderRadius: BorderRadius.circular(6),
                          backgroundColor: const Color(0xFF1E293B),
                          focusedBackgroundColor: const Color(0xFF0284C7),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.select_all_rounded, color: Color(0xFF38BDF8), size: 15),
                              SizedBox(width: 6),
                              Text('Pilih Semua', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        TvFocusable(
                          onPressed: () {
                            setDialogState(() {
                              selectedKeys.clear();
                              selectedKeys.addAll(AppSettings.defaultMergedProviders);
                            });
                          },
                          borderRadius: BorderRadius.circular(6),
                          backgroundColor: const Color(0xFF1E293B),
                          focusedBackgroundColor: const Color(0xFF0284C7),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star_rounded, color: Colors.amberAccent, size: 15),
                              SizedBox(width: 6),
                              Text('Hanya Populer (Top 6)', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        TvFocusable(
                          onPressed: () {
                            setDialogState(() {
                              selectedKeys.clear();
                            });
                          },
                          borderRadius: BorderRadius.circular(6),
                          backgroundColor: const Color(0xFF1E293B),
                          focusedBackgroundColor: const Color(0xFF475569),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.clear_rounded, color: Colors.white54, size: 15),
                              SizedBox(width: 6),
                              Text('Bersihkan', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Colors.white12, height: 1),
                    const SizedBox(height: 12),
                    // Providers Checklist Grid
                    Expanded(
                      child: GridView.builder(
                        physics: const BouncingScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 3.4,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: availableProviders.length,
                        itemBuilder: (context, idx) {
                          final p = availableProviders[idx];
                          final isChecked = selectedKeys.contains(p.key);
                          final dramaCount = p.dramaCount > 0 ? p.dramaCount : AppSettings.getDramaCount(p.key);

                          return TvFocusable(
                            onPressed: () {
                              setDialogState(() {
                                if (isChecked) {
                                  selectedKeys.remove(p.key);
                                } else {
                                  selectedKeys.add(p.key);
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            backgroundColor: isChecked ? const Color(0xFF1E293B) : const Color(0xFF0B132B),
                            focusBorderColor: const Color(0xFF00E5FF),
                            focusedBackgroundColor: isChecked ? const Color(0xFF0369A1) : const Color(0xFF1E293B),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            child: Row(
                              children: [
                                Icon(
                                  isChecked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                  color: isChecked ? const Color(0xFF00E5FF) : Colors.white38,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    p.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isChecked ? Colors.white : Colors.white70,
                                      fontSize: 13,
                                      fontWeight: isChecked ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isChecked ? const Color(0xFF0284C7).withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: isChecked ? const Color(0xFF38BDF8).withValues(alpha: 0.6) : Colors.white12,
                                    ),
                                  ),
                                  child: Text(
                                    dramaCount > 0 ? '$dramaCount drama' : '0 drama',
                                    style: TextStyle(
                                      color: isChecked ? const Color(0xFF38BDF8) : Colors.white54,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
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
              ),
              actions: [
                TvFocusable(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  borderRadius: BorderRadius.circular(8),
                  backgroundColor: const Color(0xFF1E293B),
                  focusedBackgroundColor: const Color(0xFF334155),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                  child: const Text('Batal', style: TextStyle(color: Colors.white70, fontSize: 13)),
                ),
                TvFocusable(
                  autofocus: true,
                  onPressed: () async {
                    if (selectedKeys.isEmpty) {
                      selectedKeys.addAll(AppSettings.defaultMergedProviders);
                    }
                    await AppSettings.setHomeMergedProviders(selectedKeys.toList());
                    if (context.mounted) {
                      Navigator.of(dialogCtx).pop();
                      _loadHomeCatalog(reset: true);
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  backgroundColor: const Color(0xFFFF2D55),
                  focusedBackgroundColor: const Color(0xFFFF5377),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_rounded, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text('Terapkan & Simpan', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _updateDisplayedHomeDramas() {
    if (_allHomeDramas.isEmpty) {
      _homeDramas = [];
      return;
    }
    final start = (_homeCurrentPage - 1) * _homePageSize;
    if (start >= _allHomeDramas.length) {
      _homeDramas = [];
      return;
    }
    final end = (start + _homePageSize).clamp(0, _allHomeDramas.length);
    _homeDramas = _allHomeDramas.sublist(start, end);
  }

  Future<void> _changeHomePage(int targetPage) async {
    if (targetPage < 1 || targetPage > _homeTotalPages) return;
    if (targetPage == _homeCurrentPage) return;

    if (_allHomeDramas.isNotEmpty) {
      setState(() {
        _homeCurrentPage = targetPage;
        _updateDisplayedHomeDramas();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_firstHomeDramaFocusNode.canRequestFocus) {
          _firstHomeDramaFocusNode.requestFocus();
        }
      });
    } else {
      // General catalog fallback
      setState(() {
        _homeCurrentPage = targetPage;
        _isLoadingHome = true;
      });
      try {
        final res = await NartoApiService.fetchGeneralCatalog(page: targetPage);
        if (mounted) {
          setState(() {
            _homeDramas = res.items;
            _homeTotalPages = res.totalPages;
            _isLoadingHome = false;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_firstHomeDramaFocusNode.canRequestFocus) {
              _firstHomeDramaFocusNode.requestFocus();
            }
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoadingHome = false;
            _homeError = 'Gagal memuat halaman $targetPage ($e)';
          });
        }
      }
    }
  }

  Future<void> _loadHomeCatalog({bool reset = false}) async {
    if (_isLoadingHome) return;
    if (reset) {
      setState(() {
        _homePage = 1;
        _homeCurrentPage = 1;
        _homeDramas = [];
        _allHomeDramas = [];
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
      final activeProviders = AppSettings.homeMergedProviders.isNotEmpty
          ? AppSettings.homeMergedProviders
          : AppSettings.defaultMergedProviders;

      // Fetch sections for all selected providers in parallel
      final results = await Future.wait(
        activeProviders.map((p) => NartoApiService.fetchProviderSections(
              provider: p,
              page: _homePage,
            )),
      );

      final List<List<DramaItem>> providerLists = [];
      List<ProviderInfo>? collectedProviders;

      for (final res in results) {
        final sections = res['sections'] as List<ProviderSection>? ?? [];
        final apiProviders = res['providers'] as List<ProviderInfo>?;
        if (apiProviders != null && apiProviders.isNotEmpty && collectedProviders == null) {
          collectedProviders = apiProviders;
        }
        final List<DramaItem> pItems = [];
        for (final sec in sections) {
          pItems.addAll(sec.items);
        }
        if (pItems.isNotEmpty) {
          providerLists.add(pItems);
        }
      }

      // Interleave items round-robin across selected providers
      final List<DramaItem> mergedItems = [];
      final seen = <String>{};
      int maxLen = 0;
      for (final list in providerLists) {
        if (list.length > maxLen) maxLen = list.length;
      }
      for (int i = 0; i < maxLen; i++) {
        for (final list in providerLists) {
          if (i < list.length) {
            final item = list[i];
            if (seen.add(item.historyKey)) {
              mergedItems.add(item);
            }
          }
        }
      }

      if (mergedItems.isNotEmpty) {
        if (mounted) {
          setState(() {
            if (collectedProviders != null && collectedProviders.isNotEmpty) {
              _providers = collectedProviders;
            }
            _allHomeDramas = reset ? mergedItems : [..._allHomeDramas, ...mergedItems];
            _homeTotalPages = (_allHomeDramas.length / _homePageSize).ceil();
            if (_homeTotalPages < 1) _homeTotalPages = 1;
            if (reset) _homeCurrentPage = 1;
            if (_homeCurrentPage > _homeTotalPages) _homeCurrentPage = _homeTotalPages;
            _updateDisplayedHomeDramas();
            _hasMoreHome = _homeCurrentPage < _homeTotalPages;
            _isLoadingHome = false;
          });
        }
        return;
      }

      // Fallback: general catalog if providers returned empty
      final res = await NartoApiService.fetchGeneralCatalog(page: reset ? 1 : _homeCurrentPage);
      if (mounted) {
        setState(() {
          _allHomeDramas = [];
          _homeDramas = res.items;
          _homeTotalPages = res.totalPages;
          if (_homeTotalPages < 1) _homeTotalPages = 1;
          if (reset) _homeCurrentPage = 1;
          _hasMoreHome = res.hasNext;
          _isLoadingHome = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingHome = false;
          _homeError = 'Gagal memuat beranda ($e)';
        });
      }
    }
  }

  Future<void> _loadProviderCatalog({bool reset = false}) async {
    if (_isLoadingProviderDramas) return;
    if (reset) {
      setState(() {
        _providerPage = 1;
        _providerDramas = [];
        _hasMoreProviderDramas = true;
        _providerError = '';
        _isLoadingProviderDramas = true;
      });
    } else {
      if (!_hasMoreProviderDramas) return;
      setState(() {
        _isLoadingProviderDramas = true;
      });
    }

    try {
      final res = await NartoApiService.fetchProviderSections(
        provider: _selectedProviderKey,
        page: _providerPage,
      );
      final sections = res['sections'] as List<ProviderSection>? ?? [];
      final apiProviders = res['providers'] as List<ProviderInfo>?;
      final List<DramaItem> items = [];
      for (final sec in sections) {
        items.addAll(sec.items);
      }

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
          _providerDramas = reset ? uniqueItems : [..._providerDramas, ...uniqueItems];
          _hasMoreProviderDramas = uniqueItems.length >= 10;
          _providerPage++;
          _isLoadingProviderDramas = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingProviderDramas = false;
          _providerError = 'Gagal memuat drama provider ($e)';
        });
      }
    }
  }

  void _selectProviderInProviderTab(String providerKey) {
    if (_selectedProviderKey == providerKey && _providerDramas.isNotEmpty) {
      if (_firstProviderDramaFocusNode.canRequestFocus) {
        _firstProviderDramaFocusNode.requestFocus();
      }
      return;
    }
    setState(() {
      _selectedProviderKey = providerKey;
    });
    _loadProviderCatalog(reset: true);
  }

  String _getProviderLabel(String key) {
    final match = _providers.where((p) => p.key.toLowerCase() == key.toLowerCase());
    if (match.isNotEmpty) return match.first.label;
    return key.toUpperCase();
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

    List<String> keys = _providers.map((p) => p.key).toList();
    if (keys.isEmpty) {
      keys = AppSettings.allProviders.map((p) => p.key).toList();
    }
    keys = keys.where((k) => k != 'all' && k != 'general').toList();
    if (keys.isEmpty) {
      keys = ['melolo', 'candyjar', 'reelshort', 'minutedrama', 'stardusttv', 'moboreels', 'shortmax', 'dramabox'];
    }

    setState(() => _isSyncingProviders = true);

    int currentStep = 0;
    int totalSteps = keys.length;
    double progress = 0.0;
    String statusText = 'Menghubungkan ke upstream API...';
    int lastFoundCount = 0;
    bool isAuditComplete = false;
    String? auditError;
    StateSetter? dialogSetState;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            dialogSetState = setDialogState;
            return AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(
                    isAuditComplete ? Icons.check_circle_rounded : Icons.sync_rounded,
                    color: isAuditComplete ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isAuditComplete ? 'Sinkronisasi Selesai' : 'Sinkronisasi Provider',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusText,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: isAuditComplete ? 1.0 : (progress > 0 ? progress : null),
                        minHeight: 10,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isAuditComplete ? const Color(0xFF10B981) : const Color(0xFFFF2D55),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${(progress * 100).toInt()}% selesai ($currentStep / $totalSteps)',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        if (lastFoundCount > 0)
                          Text(
                            'Drama terdeteksi: $lastFoundCount',
                            style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                    if (auditError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        auditError,
                        style: const TextStyle(color: Color(0xFFFF2D55), fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                if (!isAuditComplete)
                  TvFocusable(
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    borderRadius: BorderRadius.circular(8),
                    backgroundColor: const Color(0xFF1E293B),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: const Text('Latar Belakang', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ),
                if (isAuditComplete)
                  TvFocusable(
                    autofocus: true,
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    borderRadius: BorderRadius.circular(8),
                    backgroundColor: const Color(0xFFFF2D55),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    child: const Text('Tutup', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
              ],
            );
          },
        );
      },
    );

    try {
      try {
        final secRes = await NartoApiService.fetchProviderSections(provider: 'melolo');
        final apiProviders = secRes['providers'] as List<ProviderInfo>?;
        if (apiProviders != null && apiProviders.isNotEmpty) {
          final newKeys = apiProviders.map((p) => p.key).where((k) => k != 'all' && k != 'general').toList();
          if (newKeys.isNotEmpty) {
            keys = newKeys;
            totalSteps = keys.length;
          }
        }
      } catch (_) {}

      await NartoApiService.auditAllProviders(
        providerKeys: keys,
        onProgress: (current, total, name, count) {
          currentStep = current;
          totalSteps = total;
          progress = current / total;
          statusText = '[$current/$total] ${name.toUpperCase()}: $count drama';
          lastFoundCount = count;
          if (dialogSetState != null) {
            dialogSetState!(() {});
          }
        },
      );

      final updated = AppSettings.allProviders;
      if (mounted) {
        setState(() {
          _providers = updated;
          _isSyncingProviders = false;
        });
        _loadHomeCatalog(reset: true);
      }

      isAuditComplete = true;
      statusText = 'Audit selesai! ${keys.length} provider berhasil diverifikasi dari API.';
      if (dialogSetState != null) {
        dialogSetState!(() {});
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sinkronisasi provider selesai! Total ${keys.length} provider terverifikasi.'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSyncingProviders = false;
        });
      }
      isAuditComplete = true;
      auditError = 'Terjadi kendala saat sinkronisasi: $e';
      statusText = 'Sinkronisasi selesai dengan catatan.';
      if (dialogSetState != null) {
        dialogSetState!(() {});
      }
    }
  }

  void _onTabChanged(int index) {
    setState(() {
      _selectedTabIndex = index;
    });
    if (index >= 0 && index < _tabFocusNodes.length) {
      _tabFocusNodes[index].requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && index < _tabFocusNodes.length) {
          _tabFocusNodes[index].requestFocus();
        }
      });
    }
    if (index == 1) {
      if (_providerDramas.isEmpty && !_isLoadingProviderDramas) {
        _loadProviderCatalog(reset: true);
      }
    } else if (index == 2) {
      _loadHistory();
    } else if (index == 3) {
      _loadBookmarks();
    }
  }

  void _focusTabContent(int tabIndex) {
    if (_selectedTabIndex != tabIndex) {
      _onTabChanged(tabIndex);
    }
    // Attempt focus immediately and ensure in postFrameCallback
    void requestTargetFocus() {
      if (!mounted) return;
      switch (tabIndex) {
        case 0:
          if (_homeDramas.isNotEmpty && _firstHomeDramaFocusNode.canRequestFocus) {
            _firstHomeDramaFocusNode.requestFocus();
          } else if (_firstHomeFocusNode.canRequestFocus) {
            _firstHomeFocusNode.requestFocus();
          }
          break;
        case 1:
          if (_firstProviderFocusNode.canRequestFocus) {
            _firstProviderFocusNode.requestFocus();
          } else if (_firstProviderDramaFocusNode.canRequestFocus) {
            _firstProviderDramaFocusNode.requestFocus();
          }
          break;
        case 2:
          if (_firstHistoryFocusNode.canRequestFocus) {
            _firstHistoryFocusNode.requestFocus();
          }
          break;
        case 3:
          if (_firstBookmarkFocusNode.canRequestFocus) {
            _firstBookmarkFocusNode.requestFocus();
          }
          break;
        case 4:
          if (_searchInputFocusNode.canRequestFocus) {
            _searchInputFocusNode.requestFocus();
          }
          break;
        case 5:
          if (_settingsFirstFocusNode.canRequestFocus) {
            _settingsFirstFocusNode.requestFocus();
          }
          break;
      }
    }

    requestTargetFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      requestTargetFocus();
    });
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

  FocusNode _getProviderChipFocusNode(String key) {
    final cleanKey = key.toLowerCase();
    if (_providers.isNotEmpty && cleanKey == _providers.first.key.toLowerCase()) {
      return _firstProviderFocusNode;
    }
    return _providerChipFocusNodes.putIfAbsent(cleanKey, () => FocusNode());
  }

  @override
  void dispose() {
    for (final node in _tabFocusNodes) {
      node.dispose();
    }
    for (final node in _providerChipFocusNodes.values) {
      node.dispose();
    }
    _providerChipFocusNodes.clear();
    _pingAutoTimer?.cancel();
    _pingFocusNode.dispose();
    _homePrevPageFocusNode.dispose();
    _homeNextPageFocusNode.dispose();
    _homeBottomPrevFocusNode.dispose();
    _homeBottomNextFocusNode.dispose();
    _firstHomeFocusNode.dispose();
    _firstHomeDramaFocusNode.dispose();
    _homeRefreshFocusNode.dispose();
    _homeFilterFocusNode.dispose();
    _firstProviderFocusNode.dispose();
    _firstProviderDramaFocusNode.dispose();
    _providerSyncFocusNode.dispose();
    _firstHistoryFocusNode.dispose();
    _firstBookmarkFocusNode.dispose();
    _searchInputFocusNode.dispose();
    _searchClearFocusNode.dispose();
    _searchSubmitBtnFocusNode.dispose();
    _firstQuickKeywordFocusNode.dispose();
    _firstSearchResultFocusNode.dispose();
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

  DateTime _lastBackPressTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isHandlingBack = false;

  Future<void> _handleBackPress() async {
    final now = DateTime.now();
    if (now.difference(_lastBackPressTime) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastBackPressTime = now;

    if (_isHandlingBack) return;
    _isHandlingBack = true;
    try {
      if (_selectedTabIndex == 0 && (_homeRefreshFocusNode.hasFocus || _homeFilterFocusNode.hasFocus)) {
        _tabFocusNodes[0].requestFocus();
        return;
      }

      if (_selectedTabIndex == 1) {
        if (_providerSyncFocusNode.hasFocus) {
          final activeChipNode = _getProviderChipFocusNode(_selectedProviderKey);
          if (activeChipNode.canRequestFocus) {
            activeChipNode.requestFocus();
          } else {
            _firstProviderFocusNode.requestFocus();
          }
          return;
        }

        final isNavbarFocused = _tabFocusNodes[1].hasFocus;
        final isAnyChipFocused = _providerChipFocusNodes.values.any((n) => n.hasFocus) || _firstProviderFocusNode.hasFocus;

        if (!isNavbarFocused && !isAnyChipFocused) {
          // Focus is down in drama grid or below provider chips -> return to provider chip first
          final activeChipNode = _getProviderChipFocusNode(_selectedProviderKey);
          if (activeChipNode.canRequestFocus) {
            activeChipNode.requestFocus();
          } else {
            _firstProviderFocusNode.requestFocus();
          }
          return;
        } else if (isAnyChipFocused) {
          // Focus is on provider chip -> return to navbar tab Provider
          _tabFocusNodes[1].requestFocus();
          return;
        }
      }

      final isAnyTabFocused = _tabFocusNodes.any((n) => n.hasFocus);
      if (!isAnyTabFocused) {
        // Return focus to the currently active tab in navbar
        final targetIndex = (_selectedTabIndex >= 0 && _selectedTabIndex < _tabFocusNodes.length)
            ? _selectedTabIndex
            : 0;
        _tabFocusNodes[targetIndex].requestFocus();
        return;
      }

      // If already on the navbar but not on Beranda (tab 0), return to Beranda
      if (_selectedTabIndex != 0) {
        _onTabChanged(0);
        return;
      }

      // If already on Beranda tab in navbar, show exit confirmation dialog
      final shouldExit = await _showExitConfirmationDialog();
      if (shouldExit == true) {
        SystemNavigator.pop();
      }
    } finally {
      _isHandlingBack = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBackPress();
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
                      onPressed: () {
                        if (_selectedTabIndex == index) {
                          _focusTabContent(index);
                        } else {
                          _onTabChanged(index);
                        }
                      },
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent || event is KeyRepeatEvent) {
                          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                            if (index < _tabFocusNodes.length - 1) {
                              _onTabChanged(index + 1);
                              return KeyEventResult.handled;
                            } else if (index == _tabFocusNodes.length - 1) {
                              _pingFocusNode.requestFocus();
                              return KeyEventResult.handled;
                            }
                          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                            if (index > 0) {
                              _onTabChanged(index - 1);
                              return KeyEventResult.handled;
                            }
                          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                            _focusTabContent(index);
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
          const SizedBox(width: 12),
          _buildPingIndicator(),
        ],
      ),
    );
  }

  Widget _buildPingIndicator() {
    Color statusColor;
    String pingText;
    IconData iconData;

    if (_isTestingPing) {
      statusColor = const Color(0xFF38BDF8);
      pingText = '...';
      iconData = Icons.sync_rounded;
    } else if (!_pingSuccess || _pingMs == null) {
      statusColor = const Color(0xFFEF4444);
      pingText = 'Offline';
      iconData = Icons.wifi_off_rounded;
    } else if (_pingMs! < 500) {
      statusColor = const Color(0xFF10B981);
      pingText = '${_pingMs}ms';
      iconData = Icons.wifi_rounded;
    } else if (_pingMs! < 1000) {
      statusColor = const Color(0xFFF59E0B);
      pingText = '${_pingMs}ms';
      iconData = Icons.wifi_rounded;
    } else {
      statusColor = const Color(0xFFEF4444);
      pingText = '${_pingMs}ms';
      iconData = Icons.wifi_rounded;
    }

    return TvFocusable(
      focusNode: _pingFocusNode,
      onPressed: _runPingTest,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            if (_tabFocusNodes.isNotEmpty) {
              _tabFocusNodes.last.requestFocus();
            }
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _focusTabContent(_selectedTabIndex);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      borderRadius: BorderRadius.circular(8),
      backgroundColor: const Color(0xFF1E293B),
      focusedBackgroundColor: const Color(0xFF334155),
      focusBorderColor: statusColor,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isTestingPing)
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 2, color: statusColor),
            )
          else
            Icon(iconData, size: 14, color: statusColor),
          const SizedBox(width: 6),
          Text(
            pingText,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.3,
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

  // --- TAB 0: HOME (BERANDA MANDIRI) ---
  Widget _buildHomeTab() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Beranda Drama',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Gabungan ${_getActiveMergedProviderNames()} • Halaman $_homeCurrentPage dari $_homeTotalPages (${_allHomeDramas.isNotEmpty ? _allHomeDramas.length : _homeDramas.length} drama)',
                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TvFocusable(
                    focusNode: _homeFilterFocusNode,
                    onPressed: _showProviderFilterModal,
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent) {
                        if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                            event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                          _tabFocusNodes[0].requestFocus();
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                          _homeRefreshFocusNode.requestFocus();
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          if (_firstHomeDramaFocusNode.canRequestFocus) {
                            _firstHomeDramaFocusNode.requestFocus();
                          }
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    borderRadius: BorderRadius.circular(6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    focusBorderColor: const Color(0xFF00E5FF),
                    backgroundColor: const Color(0xFF1E293B),
                    focusedBackgroundColor: const Color(0xFF0284C7),
                    child: Row(
                      children: [
                        const Icon(Icons.tune_rounded, color: Color(0xFF38BDF8), size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Pilih Provider (${_getMergedProviderCount()})',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  TvFocusable(
                    focusNode: _homeRefreshFocusNode,
                    onPressed: () => _loadHomeCatalog(reset: true),
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent) {
                        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                          _tabFocusNodes[0].requestFocus();
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                          _homeFilterFocusNode.requestFocus();
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                          _homePrevPageFocusNode.requestFocus();
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          if (_firstHomeDramaFocusNode.canRequestFocus) {
                            _firstHomeDramaFocusNode.requestFocus();
                          }
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    borderRadius: BorderRadius.circular(6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    focusBorderColor: const Color(0xFF00E5FF),
                    backgroundColor: const Color(0xFF1E293B),
                    focusedBackgroundColor: const Color(0xFF38BDF8),
                    child: Row(
                      children: [
                        _isLoadingHome
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.refresh_rounded, color: Color(0xFF38BDF8), size: 16),
                        const SizedBox(width: 8),
                        Text(
                          _isLoadingHome ? 'Menyegarkan...' : 'Segarkan',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildHomeHeaderPagination(),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _isLoadingHome && _homeDramas.isEmpty
                ? Center(
                    child: SingleChildScrollView(
                      child: TvFocusable(
                        focusNode: _firstHomeFocusNode,
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp) {
                            _tabFocusNodes[0].requestFocus();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Color(0xFFFF2D55)),
                            SizedBox(height: 16),
                            Text(
                              'Memuat drama beranda...',
                              style: TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : _homeDramas.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.inbox_outlined, color: Colors.white24, size: 56),
                              const SizedBox(height: 12),
                              Text(
                                _homeError.isNotEmpty ? _homeError : 'Belum ada drama ditemukan di beranda',
                                style: const TextStyle(color: Colors.white54, fontSize: 14),
                              ),
                              const SizedBox(height: 16),
                              TvFocusable(
                                focusNode: _firstHomeFocusNode,
                                onPressed: () => _loadHomeCatalog(reset: true),
                                borderRadius: BorderRadius.circular(8),
                                backgroundColor: const Color(0xFF1E293B),
                                focusedBackgroundColor: const Color(0xFFFF2D55),
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.refresh, color: Colors.white, size: 18),
                                    SizedBox(width: 8),
                                    Text(
                                      'Muat Ulang',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          Expanded(
                            child: GridView.builder(
                              physics: const BouncingScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 6,
                                childAspectRatio: 0.68,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                              ),
                              itemCount: _homeDramas.length,
                              itemBuilder: (context, index) {
                                final drama = _homeDramas[index];
                                final isTopRow = index < 6;
                                final isBottomRow = index >= (_homeDramas.length - 6);

                                return TvDramaCard(
                                  drama: drama,
                                  focusNode: index == 0 ? _firstHomeDramaFocusNode : null,
                                  onKeyEvent: (node, event) {
                                    if (event is KeyDownEvent) {
                                      if (event.logicalKey == LogicalKeyboardKey.arrowUp && isTopRow) {
                                        if (index < 2) {
                                          _homeFilterFocusNode.requestFocus();
                                        } else if (index < 4) {
                                          _homeRefreshFocusNode.requestFocus();
                                        } else if (index < 5) {
                                          _homePrevPageFocusNode.requestFocus();
                                        } else {
                                          _homeNextPageFocusNode.requestFocus();
                                        }
                                        return KeyEventResult.handled;
                                      }
                                      if (event.logicalKey == LogicalKeyboardKey.arrowDown && isBottomRow) {
                                        if (_homeTotalPages > 1) {
                                          if (index % 6 < 3) {
                                            _homeBottomPrevFocusNode.requestFocus();
                                          } else {
                                            _homeBottomNextFocusNode.requestFocus();
                                          }
                                          return KeyEventResult.handled;
                                        }
                                      }
                                    }
                                    return KeyEventResult.ignored;
                                  },
                                  onTap: () => _openDetail(drama),
                                );
                              },
                            ),
                          ),
                          _buildHomeBottomPagination(),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeHeaderPagination() {
    final canPrev = _homeCurrentPage > 1;
    final canNext = _homeCurrentPage < _homeTotalPages;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF334155), width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TvFocusable(
            focusNode: _homePrevPageFocusNode,
            onPressed: canPrev ? () => _changeHomePage(_homeCurrentPage - 1) : null,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  _homeRefreshFocusNode.requestFocus();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  _homeNextPageFocusNode.requestFocus();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  _tabFocusNodes[0].requestFocus();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  if (_firstHomeDramaFocusNode.canRequestFocus) {
                    _firstHomeDramaFocusNode.requestFocus();
                  }
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            borderRadius: BorderRadius.circular(4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            backgroundColor: Colors.transparent,
            focusedBackgroundColor: const Color(0xFFFF2D55),
            child: Icon(
              Icons.chevron_left_rounded,
              color: canPrev ? Colors.white : Colors.white24,
              size: 18,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Hal $_homeCurrentPage / $_homeTotalPages',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TvFocusable(
            focusNode: _homeNextPageFocusNode,
            onPressed: canNext ? () => _changeHomePage(_homeCurrentPage + 1) : null,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  _homePrevPageFocusNode.requestFocus();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  _tabFocusNodes[0].requestFocus();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  if (_firstHomeDramaFocusNode.canRequestFocus) {
                    _firstHomeDramaFocusNode.requestFocus();
                  }
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            borderRadius: BorderRadius.circular(4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            backgroundColor: Colors.transparent,
            focusedBackgroundColor: const Color(0xFFFF2D55),
            child: Icon(
              Icons.chevron_right_rounded,
              color: canNext ? Colors.white : Colors.white24,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeBottomPagination() {
    if (_homeTotalPages <= 1 && _allHomeDramas.length <= _homePageSize) {
      return const SizedBox.shrink();
    }
    final canPrev = _homeCurrentPage > 1;
    final canNext = _homeCurrentPage < _homeTotalPages;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TvFocusable(
            focusNode: _homeBottomPrevFocusNode,
            onPressed: canPrev ? () => _changeHomePage(_homeCurrentPage - 1) : null,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  _homeBottomNextFocusNode.requestFocus();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  if (_firstHomeDramaFocusNode.canRequestFocus) {
                    _firstHomeDramaFocusNode.requestFocus();
                  }
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            borderRadius: BorderRadius.circular(8),
            backgroundColor: canPrev ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
            focusedBackgroundColor: const Color(0xFFFF2D55),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_rounded, size: 16, color: canPrev ? Colors.white : Colors.white24),
                const SizedBox(width: 8),
                Text(
                  'Halaman Sebelumnya',
                  style: TextStyle(
                    color: canPrev ? Colors.white : Colors.white24,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Text(
              'Halaman $_homeCurrentPage dari $_homeTotalPages (${_allHomeDramas.isNotEmpty ? _allHomeDramas.length : _homeDramas.length} Drama)',
              style: const TextStyle(
                color: Color(0xFF38BDF8),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 16),
          TvFocusable(
            focusNode: _homeBottomNextFocusNode,
            onPressed: canNext ? () => _changeHomePage(_homeCurrentPage + 1) : null,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  _homeBottomPrevFocusNode.requestFocus();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  if (_firstHomeDramaFocusNode.canRequestFocus) {
                    _firstHomeDramaFocusNode.requestFocus();
                  }
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            borderRadius: BorderRadius.circular(8),
            backgroundColor: canNext ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
            focusedBackgroundColor: const Color(0xFFFF2D55),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Halaman Berikutnya',
                  style: TextStyle(
                    color: canNext ? Colors.white : Colors.white24,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded, size: 16, color: canNext ? Colors.white : Colors.white24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- TAB 1: PROVIDER (MANDIRI) ---
  Widget _buildProvidersTab() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Jelajahi Provider (${_providers.length})',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              TvFocusable(
                focusNode: _providerSyncFocusNode,
                onPressed: _syncProvidersManual,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                      _tabFocusNodes[1].requestFocus();
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      final activeChipNode = _getProviderChipFocusNode(_selectedProviderKey);
                      if (activeChipNode.canRequestFocus) {
                        activeChipNode.requestFocus();
                      } else {
                        _firstProviderFocusNode.requestFocus();
                      }
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                borderRadius: BorderRadius.circular(6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                focusBorderColor: const Color(0xFF00E5FF),
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
          const SizedBox(height: 12),

          // Provider Horizontal Selector Bar
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _providers.length,
              itemBuilder: (context, index) {
                final p = _providers[index];
                final isSelected = _selectedProviderKey.toLowerCase() == p.key.toLowerCase();
                final chipNode = _getProviderChipFocusNode(p.key);

                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: TvFocusable(
                    focusNode: chipNode,
                    onPressed: () => _selectProviderInProviderTab(p.key),
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent) {
                        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          if (_firstProviderDramaFocusNode.canRequestFocus) {
                            _firstProviderDramaFocusNode.requestFocus();
                          }
                          return KeyEventResult.handled;
                        } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                          _providerSyncFocusNode.requestFocus();
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    borderRadius: BorderRadius.circular(8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    focusBorderColor: isSelected ? const Color(0xFF00E5FF) : const Color(0xFFFF2D55),
                    backgroundColor: isSelected ? const Color(0xFFFF2D55) : const Color(0xFF1E293B),
                    focusedBackgroundColor: isSelected ? const Color(0xFFFF5377) : const Color(0xFF334155),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.movie_filter_outlined,
                          size: 16,
                          color: isSelected ? Colors.white : const Color(0xFF38BDF8),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          p.label,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                        if (p.dramaCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.black26 : Colors.white12,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${p.dramaCount}',
                              style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Provider Drama Grid Title
          Row(
            children: [
              Text(
                'Koleksi Drama: ${_getProviderLabel(_selectedProviderKey)}',
                style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              if (_providerDramas.isNotEmpty)
                Text(
                  '(${_providerDramas.length} drama)',
                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 13, fontWeight: FontWeight.bold),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Provider Drama Grid Content
          Expanded(
            child: _isLoadingProviderDramas && _providerDramas.isEmpty
                ? Center(
                    child: TvFocusable(
                      focusNode: _firstProviderDramaFocusNode,
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp) {
                          _firstProviderFocusNode.requestFocus();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Color(0xFFFF2D55)),
                          SizedBox(height: 16),
                          Text(
                            'Memuat drama provider...',
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  )
                : _providerDramas.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.movie_outlined, color: Colors.white24, size: 56),
                            const SizedBox(height: 12),
                            Text(
                              _providerError.isNotEmpty
                                  ? _providerError
                                  : 'Belum ada drama ditemukan untuk provider ${_getProviderLabel(_selectedProviderKey)}',
                              style: const TextStyle(color: Colors.white54, fontSize: 14),
                            ),
                            const SizedBox(height: 16),
                            TvFocusable(
                              focusNode: _firstProviderDramaFocusNode,
                              onPressed: () => _loadProviderCatalog(reset: true),
                              onKeyEvent: (node, event) {
                                if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                  _firstProviderFocusNode.requestFocus();
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              },
                              borderRadius: BorderRadius.circular(8),
                              backgroundColor: const Color(0xFF1E293B),
                              focusedBackgroundColor: const Color(0xFFFF2D55),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.refresh, color: Colors.white, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'Muat Ulang Provider',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
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
                        itemCount: _providerDramas.length + (_hasMoreProviderDramas ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _providerDramas.length) {
                            return Center(
                              child: TvFocusable(
                                onPressed: () => _loadProviderCatalog(reset: false),
                                borderRadius: BorderRadius.circular(10),
                                backgroundColor: const Color(0xFF1E293B),
                                focusedBackgroundColor: const Color(0xFFFF2D55),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                                child: _isLoadingProviderDramas
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
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
                          final drama = _providerDramas[index];
                          final activeChipNode = _getProviderChipFocusNode(_selectedProviderKey);
                          return TvDramaCard(
                            drama: drama,
                            focusNode: index == 0 ? _firstProviderDramaFocusNode : null,
                            onKeyEvent: (node, event) {
                              if (event is KeyDownEvent) {
                                if (index < 6 && event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                  if (activeChipNode.canRequestFocus) {
                                    activeChipNode.requestFocus();
                                  } else {
                                    _firstProviderFocusNode.requestFocus();
                                  }
                                  return KeyEventResult.handled;
                                }
                              }
                              return KeyEventResult.ignored;
                            },
                            onTap: () => _openDetail(drama),
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
                  borderRadius: BorderRadius.circular(6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  backgroundColor: const Color(0xFF1E293B),
                  focusedBackgroundColor: const Color(0xFFFF2D55),
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
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.history_toggle_off_rounded, color: Colors.white24, size: 56),
                        const SizedBox(height: 12),
                        const Text('Belum ada riwayat tontonan', style: TextStyle(color: Colors.white38, fontSize: 14)),
                        const SizedBox(height: 16),
                        TvFocusable(
                          focusNode: _firstHistoryFocusNode,
                          onPressed: () {
                            _onTabChanged(0);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted && _firstHomeFocusNode.canRequestFocus) {
                                _firstHomeFocusNode.requestFocus();
                              }
                            });
                          },
                          onKeyEvent: (node, event) {
                            if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp) {
                              _tabFocusNodes[2].requestFocus();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          borderRadius: BorderRadius.circular(8),
                          backgroundColor: const Color(0xFF1E293B),
                          focusedBackgroundColor: const Color(0xFFFF2D55),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.explore_outlined, color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Jelajahi Beranda',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ],
                          ),
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
                    itemCount: _historyItems.length,
                    itemBuilder: (context, index) {
                      final item = _historyItems[index];
                      final drama = item.toDramaItem();
                      return TvDramaCard(
                        drama: drama,
                        focusNode: index == 0 ? _firstHistoryFocusNode : null,
                        onKeyEvent: index < 6
                            ? (node, event) {
                                if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                  _tabFocusNodes[2].requestFocus();
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              }
                            : null,
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
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.favorite_border_rounded, color: Colors.white24, size: 56),
                        const SizedBox(height: 12),
                        const Text('Belum ada drama favorit tersimpan', style: TextStyle(color: Colors.white38, fontSize: 14)),
                        const SizedBox(height: 16),
                        TvFocusable(
                          focusNode: _firstBookmarkFocusNode,
                          onPressed: () {
                            _onTabChanged(0);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted && _firstHomeFocusNode.canRequestFocus) {
                                _firstHomeFocusNode.requestFocus();
                              }
                            });
                          },
                          onKeyEvent: (node, event) {
                            if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp) {
                              _tabFocusNodes[3].requestFocus();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          borderRadius: BorderRadius.circular(8),
                          backgroundColor: const Color(0xFF1E293B),
                          focusedBackgroundColor: const Color(0xFFFF2D55),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.explore_outlined, color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Jelajahi Beranda',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ],
                          ),
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
                    itemCount: _bookmarkItems.length,
                    itemBuilder: (context, index) {
                      final item = _bookmarkItems[index];
                      final drama = item.toDramaItem();
                      return TvDramaCard(
                        drama: drama,
                        focusNode: index == 0 ? _firstBookmarkFocusNode : null,
                        onKeyEvent: index < 6
                            ? (node, event) {
                                if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                  _tabFocusNodes[3].requestFocus();
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              }
                            : null,
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
    final clearBtnFocus = FocusNode();
    final submitBtnFocus = FocusNode();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          focusNode.requestFocus();
        });

        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _searchInputFocusNode.canRequestFocus) {
                  _searchInputFocusNode.requestFocus();
                }
              });
            }
          },
          child: StatefulBuilder(
            builder: (builderCtx, setDialogState) {
              final currentText = dialogController.text;
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
                            decoration: InputDecoration(
                              hintText: 'Masukkan judul drama...',
                              hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                              border: InputBorder.none,
                              suffixIcon: currentText.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, color: Colors.white70, size: 20),
                                      onPressed: () {
                                        dialogController.clear();
                                        setDialogState(() {});
                                      },
                                    )
                                  : null,
                            ),
                            textInputAction: TextInputAction.search,
                            onChanged: (_) => setDialogState(() {}),
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
                        'Gunakan remote TV: ketik kata kunci, lalu geser ke tombol Cari Sekarang.',
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
                          clearBtnFocus.requestFocus();
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
                    focusNode: clearBtnFocus,
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent) {
                        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                          focusNode.requestFocus();
                          return KeyEventResult.handled;
                        } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                          cancelBtnFocus.requestFocus();
                          return KeyEventResult.handled;
                        } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                          submitBtnFocus.requestFocus();
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    onPressed: () {
                      dialogController.clear();
                      setDialogState(() {});
                      focusNode.requestFocus();
                    },
                    borderRadius: BorderRadius.circular(8),
                    backgroundColor: const Color(0xFF1E293B),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.clear_rounded, size: 16, color: Colors.white70),
                        SizedBox(width: 4),
                        Text('Hapus Teks', style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                  TvFocusable(
                    focusNode: submitBtnFocus,
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent) {
                        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                          focusNode.requestFocus();
                          return KeyEventResult.handled;
                        } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                          clearBtnFocus.requestFocus();
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
          ),
        );
      },
    ).then((_) {
      if (mounted && _searchInputFocusNode.canRequestFocus) {
        _searchInputFocusNode.requestFocus();
      }
    });
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
                  onPressed: _openTvSearchDialog,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        _tabFocusNodes[4].requestFocus();
                        return KeyEventResult.handled;
                      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                        _searchClearFocusNode.requestFocus();
                        return KeyEventResult.handled;
                      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        if (_firstQuickKeywordFocusNode.canRequestFocus) {
                          _firstQuickKeywordFocusNode.requestFocus();
                          return KeyEventResult.handled;
                        } else if (_firstSearchResultFocusNode.canRequestFocus) {
                          _firstSearchResultFocusNode.requestFocus();
                          return KeyEventResult.handled;
                        }
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
                    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      if (_firstQuickKeywordFocusNode.canRequestFocus) {
                        _firstQuickKeywordFocusNode.requestFocus();
                        return KeyEventResult.handled;
                      } else if (_firstSearchResultFocusNode.canRequestFocus) {
                        _firstSearchResultFocusNode.requestFocus();
                        return KeyEventResult.handled;
                      }
                    }
                  }
                  return KeyEventResult.ignored;
                },
                onPressed: () {
                  if (queryText.isNotEmpty) {
                    setState(() {
                      _searchController.clear();
                      _searchResults = [];
                      _searchError = '';
                    });
                  }
                  _searchInputFocusNode.requestFocus();
                },
                borderRadius: BorderRadius.circular(10),
                backgroundColor: const Color(0xFF1E293B),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.clear_rounded,
                      color: queryText.isNotEmpty ? Colors.white70 : Colors.white38,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Hapus',
                      style: TextStyle(
                        color: queryText.isNotEmpty ? Colors.white70 : Colors.white38,
                        fontSize: 13,
                        fontWeight: queryText.isNotEmpty ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              TvFocusable(
                focusNode: _searchSubmitBtnFocusNode,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      _tabFocusNodes[4].requestFocus();
                      return KeyEventResult.handled;
                    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                      _searchClearFocusNode.requestFocus();
                      return KeyEventResult.handled;
                    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      if (_firstQuickKeywordFocusNode.canRequestFocus) {
                        _firstQuickKeywordFocusNode.requestFocus();
                        return KeyEventResult.handled;
                      } else if (_firstSearchResultFocusNode.canRequestFocus) {
                        _firstSearchResultFocusNode.requestFocus();
                        return KeyEventResult.handled;
                      }
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
                ...quickKeywords.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final kw = entry.value;
                  final isCurrent = queryText.toLowerCase() == kw.toLowerCase();
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TvFocusable(
                      focusNode: idx == 0 ? _firstQuickKeywordFocusNode : null,
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent) {
                          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                            _searchInputFocusNode.requestFocus();
                            return KeyEventResult.handled;
                          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                            if (_firstSearchResultFocusNode.canRequestFocus) {
                              _firstSearchResultFocusNode.requestFocus();
                              return KeyEventResult.handled;
                            }
                          }
                        }
                        return KeyEventResult.ignored;
                      },
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
                                focusNode: index == 0 ? _firstSearchResultFocusNode : null,
                                onKeyEvent: index < 6
                                    ? (node, event) {
                                        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                          if (_firstQuickKeywordFocusNode.canRequestFocus) {
                                            _firstQuickKeywordFocusNode.requestFocus();
                                          } else {
                                            _searchInputFocusNode.requestFocus();
                                          }
                                          return KeyEventResult.handled;
                                        }
                                        return KeyEventResult.ignored;
                                      }
                                    : null,
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
  Future<void> _applyAndSaveHost(String url, [BuildContext? dialogCtx, BuildContext? parentDialogCtx]) async {
    final target = url.trim();
    if (target.isEmpty) return;
    await AppSettings.setBaseUrl(target);
    if (dialogCtx != null && dialogCtx.mounted) {
      Navigator.of(dialogCtx).pop(target);
    }
    if (parentDialogCtx != null && parentDialogCtx.mounted) {
      Navigator.of(parentDialogCtx).pop(target);
    }
    if (mounted) {
      setState(() {});
      _loadHomeCatalog(reset: true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Host upstream berhasil disimpan: $target'),
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<String?> _showManualUrlInputDialog(BuildContext parentCtx, String initialUrl) {
    final controller = TextEditingController(text: initialUrl);
    final cancelFocus = FocusNode();
    final submitFocus = FocusNode();

    return showDialog<String>(
      context: parentCtx,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit_note_rounded, color: Color(0xFF38BDF8), size: 26),
            SizedBox(width: 10),
            Text('Ketik URL Host Manual', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ketik URL endpoint server (contoh: https://narto-drama.vercel.app):',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    submitFocus.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 1,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'monospace'),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (val) async {
                    await _applyAndSaveHost(val, dialogCtx, parentCtx);
                  },
                  decoration: InputDecoration(
                    hintText: 'https://...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFFF2D55), width: 2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TvFocusable(
            focusNode: cancelFocus,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowRight) {
                submitFocus.requestFocus();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            onPressed: () => Navigator.of(dialogCtx).pop(),
            borderRadius: BorderRadius.circular(8),
            backgroundColor: const Color(0xFF334155),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: const Text('Batal', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          TvFocusable(
            focusNode: submitFocus,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                cancelFocus.requestFocus();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            onPressed: () async {
              await _applyAndSaveHost(controller.text, dialogCtx, parentCtx);
            },
            borderRadius: BorderRadius.circular(8),
            backgroundColor: const Color(0xFFFF2D55),
            focusedBackgroundColor: const Color(0xFFFF5377),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: const Text('Simpan & Terapkan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showHostConfigDialog() {
    String currentTargetUrl = AppSettings.baseUrl;
    bool isTesting = false;
    String testResult = '';
    bool? testSuccess;

    final preset1Focus = FocusNode();
    final preset2Focus = FocusNode();
    final editUrlBtnFocus = FocusNode();
    final testBtnFocus = FocusNode();
    final cancelBtnFocus = FocusNode();
    final saveBtnFocus = FocusNode();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          preset1Focus.requestFocus();
        });
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final isResmi = currentTargetUrl == 'https://narto-drama.com';
            final isVercel = currentTargetUrl == 'https://narto-drama.vercel.app';

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
                width: 580,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Pilih Preset Host Cepat:', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TvFocusable(
                          focusNode: preset1Focus,
                          onKeyEvent: (node, event) {
                            if (event is KeyDownEvent) {
                              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                editUrlBtnFocus.requestFocus();
                                return KeyEventResult.handled;
                              } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                                preset2Focus.requestFocus();
                                return KeyEventResult.handled;
                              }
                            }
                            return KeyEventResult.ignored;
                          },
                          onPressed: () {
                            setDialogState(() {
                              currentTargetUrl = 'https://narto-drama.com';
                              testResult = '';
                              testSuccess = null;
                            });
                          },
                          borderRadius: BorderRadius.circular(6),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          backgroundColor: isResmi ? const Color(0xFF0284C7) : const Color(0xFF334155),
                          focusedBackgroundColor: const Color(0xFF0369A1),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isResmi) const Icon(Icons.check_circle_rounded, color: Colors.white, size: 14),
                              if (isResmi) const SizedBox(width: 6),
                              const Text('Resmi (narto-drama.com)', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        TvFocusable(
                          focusNode: preset2Focus,
                          onKeyEvent: (node, event) {
                            if (event is KeyDownEvent) {
                              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                editUrlBtnFocus.requestFocus();
                                return KeyEventResult.handled;
                              } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                                preset1Focus.requestFocus();
                                return KeyEventResult.handled;
                              }
                            }
                            return KeyEventResult.ignored;
                          },
                          onPressed: () {
                            setDialogState(() {
                              currentTargetUrl = 'https://narto-drama.vercel.app';
                              testResult = '';
                              testSuccess = null;
                            });
                          },
                          borderRadius: BorderRadius.circular(6),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          backgroundColor: isVercel ? const Color(0xFF0284C7) : const Color(0xFF334155),
                          focusedBackgroundColor: const Color(0xFF0369A1),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isVercel) const Icon(Icons.check_circle_rounded, color: Colors.white, size: 14),
                              if (isVercel) const SizedBox(width: 6),
                              const Text('Mirror Edge Vercel', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('URL Endpoint Aktif / Custom:', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TvFocusable(
                      focusNode: editUrlBtnFocus,
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
                        final inputUrl = await _showManualUrlInputDialog(ctx, currentTargetUrl);
                        if (inputUrl != null && inputUrl.isNotEmpty) {
                          setDialogState(() {
                            currentTargetUrl = inputUrl;
                            testResult = '';
                            testSuccess = null;
                          });
                          saveBtnFocus.requestFocus();
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      backgroundColor: const Color(0xFF0F172A),
                      focusedBackgroundColor: const Color(0xFF1E293B),
                      focusBorderColor: const Color(0xFFFF2D55),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.link_rounded, color: Color(0xFF38BDF8), size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              currentTargetUrl,
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF334155),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.edit_rounded, color: Colors.white70, size: 12),
                                SizedBox(width: 4),
                                Text('Ketik URL', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
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
                                editUrlBtnFocus.requestFocus();
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
                                  final res = await AppSettings.testConnection(currentTargetUrl);
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
                    await _applyAndSaveHost(currentTargetUrl, ctx);
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
