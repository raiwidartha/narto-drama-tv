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
          setState(() {
            _detail = detail;
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

  void _toggleBookmark() async {
    final detail = _detail;
    final title = detail?.title ?? widget.drama.title;
    final poster = (detail?.posterUrl.isNotEmpty ?? false) ? detail!.posterUrl : widget.drama.posterUrl;
    final totalEp = detail?.episodes.length ?? int.tryParse(widget.drama.episodeCount ?? '0') ?? 0;

    await HistoryBookmarkService.toggleBookmark(
      dramaKey: widget.drama.historyKey,
      dramaId: widget.drama.id,
      title: title,
      posterUrl: poster,
      watchUrl: widget.drama.watchUrl,
      provider: widget.drama.providerKey ?? detail?.providerName ?? 'narto',
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

  Widget _buildWidescreenDetail() {
    final detail = _detail;
    final title = detail?.title ?? widget.drama.title;
    final poster = (detail?.posterUrl.isNotEmpty ?? false) ? detail!.posterUrl : widget.drama.posterUrl;
    final synopsis = detail?.description ?? widget.drama.description ?? 'Tidak ada sinopsis tersedia.';
    final episodes = detail?.episodes ?? [];
    final targetEpIndex = _lastWatchedEpIndex ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 28, 36, 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Column: Poster & Metadata (320px)
          SizedBox(
            width: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back Button + Header Row
                Row(
                  children: [
                    TvFocusable(
                      onPressed: () => Navigator.of(context).pop(),
                      padding: const EdgeInsets.all(8),
                      backgroundColor: const Color(0xFF1E293B),
                      child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.drama.providerKey?.toUpperCase() ?? 'NARTO DRAMA',
                        style: const TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Poster Image
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: CachedNetworkImage(
                      imageUrl: poster,
                      memCacheWidth: 480,
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

                // Title
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    height: 1.25,
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
                        style: const TextStyle(color: Color(0xFFFF2D55), fontSize: 10, fontWeight: FontWeight.w800),
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
                          style: const TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),

                // Primary Action Button (Tonton Sekarang)
                TvFocusable(
                  autofocus: true,
                  onPressed: () => _openPlayer(targetEpIndex),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: const Color(0xFFFF2D55),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        _lastWatchedEpIndex != null
                            ? 'Lanjut Ep ${_lastWatchedEpIndex! + 1}'
                            : 'Tonton Sekarang',
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Secondary Action: Bookmark
                TvFocusable(
                  onPressed: _toggleBookmark,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  backgroundColor: const Color(0xFF1E293B),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isBookmarked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: _isBookmarked ? const Color(0xFFFF2D55) : Colors.white70,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isBookmarked ? 'Tersimpan di Favorit' : 'Simpan ke Favorit',
                        style: TextStyle(
                          color: _isBookmarked ? const Color(0xFFFF2D55) : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Synopsis Text
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        synopsis,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 36),

          // Right Column: Episode Grid (Flexible)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Daftar Episode',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Pilih episode untuk langsung memutar',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Grid of episodes
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
                            crossAxisCount: 6,
                            childAspectRatio: 1.6,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: episodes.length,
                          itemBuilder: (context, index) {
                            final isWatched = _lastWatchedEpIndex != null && index <= _lastWatchedEpIndex!;
                            final isCurrent = index == _lastWatchedEpIndex;

                            return TvFocusable(
                              onPressed: () => _openPlayer(index),
                              borderRadius: BorderRadius.circular(8),
                              backgroundColor: isCurrent
                                  ? const Color(0xFFFF2D55)
                                  : (isWatched
                                      ? const Color(0xFF1E293B).withValues(alpha: 0.8)
                                      : const Color(0xFF1E293B)),
                              focusedBackgroundColor: isCurrent
                                  ? const Color(0xFFFF2D55)
                                  : const Color(0xFF334155),
                              child: Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (isWatched && !isCurrent)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 4),
                                        child: Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 14),
                                      ),
                                    Text(
                                      'Ep ${index + 1}',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w600,
                                        fontSize: 13,
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
