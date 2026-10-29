import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/drama.dart';
import '../services/narto_api_service.dart';
import '../services/history_bookmark_service.dart';
import '../widgets/tv_focusable.dart';
import 'tv_player_screen.dart';

class TvDetailScreen extends StatefulWidget {
  final DramaItem drama;

  const TvDetailScreen({super.key, required this.drama});

  @override
  State<TvDetailScreen> createState() => _TvDetailScreenState();
}

class _TvDetailScreenState extends State<TvDetailScreen> {
  DramaDetail? _detail;
  bool _isLoading = true;
  String _errorMessage = '';
  int? _lastWatchedEpIndex;
  bool _isBookmarked = false;

  @override
  void initState() {
    super.initState();
    _loadDetail();
    _loadHistoryAndBookmark();
  }

  Future<void> _loadHistoryAndBookmark() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = widget.drama.historyKey;
      int? last = prefs.getInt('last_ep_$key');
      if (last == null && widget.drama.id.isNotEmpty && widget.drama.id != '0') {
        last = prefs.getInt('last_ep_${widget.drama.id}');
      }
      final bookmarked = await HistoryBookmarkService.isBookmarked(key);
      if (mounted) {
        setState(() {
          _lastWatchedEpIndex = last;
          _isBookmarked = bookmarked;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadDetail() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final detail = await NartoApiService.fetchDramaDetail(widget.drama.watchUrl);

      if (mounted) {
        if (detail == null) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Gagal memuat detail drama dari server';
          });
        } else {
          final mergedDetail = detail.copyWith(
            description: (detail.description != null && detail.description!.trim().isNotEmpty)
                ? detail.description
                : widget.drama.description,
          );
          setState(() {
            _detail = mergedDetail;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Gagal memuat detail drama ($e)';
        });
      }
    }
  }

  void _openPlayer(int episodeIndex) async {
    if (_detail == null || _detail!.episodes.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TvPlayerScreen(
          drama: _detail!,
          initialEpisodeIndex: episodeIndex,
        ),
      ),
    );

    // Refresh history when returning from player
    _loadHistoryAndBookmark();
  }

  String get _effectiveProvider {
    final detailProv = _detail?.providerName?.trim();
    if (detailProv != null &&
        detailProv.isNotEmpty &&
        detailProv.toLowerCase() != 'narto' &&
        detailProv.toLowerCase() != 'local') {
      return detailProv;
    }
    final dramaProv = widget.drama.providerKey?.trim();
    if (dramaProv != null &&
        dramaProv.isNotEmpty &&
        dramaProv.toLowerCase() != 'narto' &&
        dramaProv.toLowerCase() != 'local') {
      return dramaProv;
    }
    final detected = DramaItem.detectProvider(
      watchUrl: widget.drama.watchUrl,
      tags: widget.drama.tags,
    );
    if (detected.isNotEmpty && detected.toLowerCase() != 'narto') {
      return detected;
    }
    return 'NARTO DRAMA';
  }

  void _toggleBookmark() async {
    final detail = _detail;
    final title = detail?.title ?? widget.drama.title;
    final poster = (detail?.posterUrl.isNotEmpty ?? false) ? detail!.posterUrl : widget.drama.posterUrl;
    final totalEp = detail?.episodes.length ?? int.tryParse(widget.drama.episodeCount ?? '0') ?? 0;
    final effectiveProv = _effectiveProvider;

    await HistoryBookmarkService.toggleBookmark(
      dramaKey: widget.drama.historyKey,
      dramaId: widget.drama.id,
      title: title,
      posterUrl: poster,
      watchUrl: widget.drama.watchUrl,
      provider: effectiveProv != 'NARTO DRAMA' ? effectiveProv : (widget.drama.providerKey ?? 'narto'),
      totalEpisodes: totalEp,
    );

    _loadHistoryAndBookmark();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Slate 900
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFFFF2D55)),
                  SizedBox(height: 16),
                  Text('Memuat Detail Drama...', style: TextStyle(color: Colors.white70, fontSize: 16)),
                ],
              ),
            )
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFFF2D55), size: 48),
                      const SizedBox(height: 12),
                      Text(_errorMessage, style: const TextStyle(color: Colors.white, fontSize: 16)),
                      const SizedBox(height: 16),
                      TvFocusable(
                        autofocus: true,
                        onPressed: _loadDetail,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        backgroundColor: const Color(0xFFFF2D55),
                        child: const Text('Coba Lagi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                )
              : _buildWidescreenDetail(),
    );
  }

  void _showFullSynopsisModal(String title, String synopsis) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.description_outlined, color: Color(0xFFFF2D55), size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 580,
            child: SingleChildScrollView(
              child: Text(
                synopsis.trim().isNotEmpty ? synopsis : 'Tidak ada sinopsis tersedia untuk drama ini.',
                style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 14, height: 1.6),
              ),
            ),
          ),
          actions: [
            TvFocusable(
              autofocus: true,
              onPressed: () => Navigator.of(ctx).pop(),
              borderRadius: BorderRadius.circular(8),
              backgroundColor: const Color(0xFFFF2D55),
              focusedBackgroundColor: const Color(0xFFFF5377),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: const Text('Tutup', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWidescreenDetail() {
    final detail = _detail;
    final title = detail?.title ?? widget.drama.title;
    final poster = (detail?.posterUrl.isNotEmpty ?? false) ? detail!.posterUrl : widget.drama.posterUrl;
    final synopsis = (detail?.description != null && detail!.description!.trim().isNotEmpty)
        ? detail.description!
        : (widget.drama.description != null && widget.drama.description!.trim().isNotEmpty)
            ? widget.drama.description!
            : 'Tidak ada sinopsis tersedia untuk drama ini.';
    final episodes = detail?.episodes ?? [];
    final targetEpIndex = _lastWatchedEpIndex ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Column: Poster & Actions (210px) - clean, portrait, uncropped
          SizedBox(
            width: 210,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Back Button + Header Row
                Row(
                  children: [
                    TvFocusable(
                      onPressed: () => Navigator.of(context).pop(),
                      padding: const EdgeInsets.all(7),
                      backgroundColor: const Color(0xFF1E293B),
                      child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _effectiveProvider.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Poster Image (Portrait, exactly same ratio as preview/card, uncropped)
                Container(
                  width: 210,
                  height: 290,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12, width: 0.8),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 4)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: CachedNetworkImage(
                      imageUrl: poster,
                      memCacheWidth: 420,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: const Color(0xFF1E293B),
                        child: const Center(child: Icon(Icons.movie_outlined, color: Colors.white24, size: 36)),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: const Color(0xFF1E293B),
                        child: const Center(child: Icon(Icons.broken_image, color: Colors.white24, size: 36)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Primary Action Button (Tonton Sekarang)
                TvFocusable(
                  autofocus: true,
                  onPressed: () => _openPlayer(targetEpIndex),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  backgroundColor: const Color(0xFFFF2D55),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                      const SizedBox(width: 6),
                      Text(
                        _lastWatchedEpIndex != null
                            ? 'Lanjut Ep ${_lastWatchedEpIndex! + 1}'
                            : 'Tonton Sekarang',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Secondary Action: Bookmark (Simpan ke Favorit)
                TvFocusable(
                  onPressed: _toggleBookmark,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  backgroundColor: const Color(0xFF1E293B),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isBookmarked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: _isBookmarked ? const Color(0xFFFF2D55) : Colors.white70,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isBookmarked ? 'Tersimpan Favorit' : 'Simpan ke Favorit',
                        style: TextStyle(
                          color: _isBookmarked ? const Color(0xFFFF2D55) : Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 28),

          // Right Column: Title, Synopsis & Episode Grid
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),

                // Badge tags
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF2D55).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFFF2D55), width: 0.8),
                      ),
                      child: Text(
                        '${episodes.length} EPISODE',
                        style: const TextStyle(color: Color(0xFFFF2D55), fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (_lastWatchedEpIndex != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF10B981), width: 0.8),
                        ),
                        child: Text(
                          'LANJUT EP ${_lastWatchedEpIndex! + 1}',
                          style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),

                // Prominent Synopsis Card (TV Remote Focusable & Clickable)
                TvFocusable(
                  onPressed: () => _showFullSynopsisModal(title, synopsis),
                  borderRadius: BorderRadius.circular(10),
                  backgroundColor: const Color(0xFF1E293B).withValues(alpha: 0.8),
                  focusedBackgroundColor: const Color(0xFF334155),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.description_outlined, color: Color(0xFFFF2D55), size: 16),
                          const SizedBox(width: 8),
                          const Text(
                            'Sinopsis Cerita',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          Text(
                            'Tekan OK untuk baca lengkap',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        synopsis,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Header Daftar Episode
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Daftar Episode',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Pilih episode untuk langsung memutar',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Grid of episodes - compact so synopsis has plenty of room
                Expanded(
                  child: episodes.isEmpty
                      ? const Center(
                          child: Text(
                            'Tidak ada episode ditemukan',
                            style: TextStyle(color: Colors.white38),
                          ),
                        )
                      : GridView.builder(
                          physics: const BouncingScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            childAspectRatio: 2.1,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: episodes.length,
                          itemBuilder: (context, index) {
                            final isWatched = _lastWatchedEpIndex != null && index <= _lastWatchedEpIndex!;
                            final isCurrent = index == _lastWatchedEpIndex;

                            return TvFocusable(
                              onPressed: () => _openPlayer(index),
                              borderRadius: BorderRadius.circular(6),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                              backgroundColor: isCurrent
                                  ? const Color(0xFFFF2D55)
                                  : (isWatched
                                      ? const Color(0xFF1E293B).withValues(alpha: 0.85)
                                      : const Color(0xFF1E293B)),
                              focusedBackgroundColor: isCurrent
                                  ? const Color(0xFFFF2D55)
                                  : const Color(0xFF334155),
                              child: Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isWatched && !isCurrent)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 3),
                                        child: Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 11),
                                      ),
                                    Text(
                                      'EP ${index + 1}',
                                      style: TextStyle(
                                        color: isCurrent || isWatched ? Colors.white : Colors.white70,
                                        fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
