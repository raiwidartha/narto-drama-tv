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
      padding: const EdgeInsets.fromLTRB(36, 24, 36, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Column: Poster & Actions (280px)
          SizedBox(
            width: 280,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
                const SizedBox(height: 14),

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
              ],
            ),
          ),
          const SizedBox(width: 32),

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
                  backgroundColor: const Color(0xFF1E293B).withValues(alpha: 0.7),
                  focusedBackgroundColor: const Color(0xFF334155),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        synopsis,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Header Daftar Episode
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Daftar Episode',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
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
                const SizedBox(height: 10),

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
                                        child: Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 12),
                                      ),
                                    Text(
                                      'EP ${index + 1}',
                                      style: TextStyle(
                                        color: isCurrent || isWatched ? Colors.white : Colors.white70,
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
