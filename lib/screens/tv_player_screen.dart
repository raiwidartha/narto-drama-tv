import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/drama.dart';
import '../services/narto_api_service.dart';
import '../services/history_bookmark_service.dart';
import '../services/app_settings.dart';
import '../widgets/tv_focusable.dart';

class TvPlayerScreen extends StatefulWidget {
  final DramaDetail drama;
  final int initialEpisodeIndex;

  const TvPlayerScreen({
    super.key,
    required this.drama,
    this.initialEpisodeIndex = 0,
  });

  @override
  State<TvPlayerScreen> createState() => _TvPlayerScreenState();
}

class _TvPlayerScreenState extends State<TvPlayerScreen> {
  VideoPlayerController? _controller;
  Widget? _cachedVideoWidget;
  late int _currentIndex;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  // TV Controls visibility
  bool _showControls = false;
  bool _showEpisodeDrawer = false;
  Timer? _hideControlsTimer;

  // Subtitles
  bool _subtitlesEnabled = true;
  List<SubtitleCue> _subtitles = [];
  final ValueNotifier<String> _activeSubtitleNotifier = ValueNotifier<String>('');
  int _activeCueIndex = -1;

  // Temporary seek indicator
  String _seekIndicatorText = '';
  Timer? _seekIndicatorTimer;

  // TV focus node for root key interception
  final FocusNode _rootFocusNode = FocusNode();
  final FocusNode _playPauseFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialEpisodeIndex;
    _initController();
    _savePlaybackHistory();
  }

  void _savePlaybackHistory() {
    if (widget.drama.episodes.isNotEmpty && _currentIndex < widget.drama.episodes.length) {
      final ep = widget.drama.episodes[_currentIndex];
      HistoryBookmarkService.saveHistory(
        dramaKey: widget.drama.historyKey,
        dramaId: widget.drama.id,
        movieId: widget.drama.effectiveMovieId,
        title: widget.drama.title,
        posterUrl: widget.drama.posterUrl,
        watchUrl: ep.watchUrl,
        provider: widget.drama.providerName ?? 'narto',
        episodeIndex: _currentIndex,
        totalEpisodes: widget.drama.episodes.length,
      );
    }
  }

  Future<void> _initController() async {
    if (widget.drama.episodes.isEmpty || _currentIndex >= widget.drama.episodes.length) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Episode tidak tersedia';
      });
      return;
    }

    _loadSubtitlesForCurrentEpisode();

    final ep = widget.drama.episodes[_currentIndex];
    var streamUrl = ep.effectiveStreamUrl;

    if (streamUrl.isEmpty) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Link streaming kosong untuk episode ini';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    final oldController = _controller;
    _controller = null;
    _cachedVideoWidget = null;
    await oldController?.dispose();

    final videoHeaders = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
      'Referer': 'https://narto-drama.com/',
      'Cookie': AppSettings.customCookie ?? NartoApiService.defaultCookie,
    };

    VideoPlayerController? activeController;

    Future<VideoPlayerController?> tryInitUrl(String rawUrl) async {
      final clean = rawUrl.replaceAll(r'\/', '/').trim();
      if (!clean.startsWith('http')) return null;

      try {
        final c = VideoPlayerController.networkUrl(
          Uri.parse(clean),
          httpHeaders: videoHeaders,
        );
        await c.initialize();
        return c;
      } catch (_) {}

      try {
        final c = VideoPlayerController.networkUrl(Uri.parse(clean));
        await c.initialize();
        return c;
      } catch (_) {}

      return null;
    }

    try {
      // 1. Try effective stream url
      activeController = await tryInitUrl(streamUrl);

      // 2. Try playUrl fallback
      if (activeController == null && ep.playUrl.isNotEmpty && ep.playUrl != streamUrl) {
        activeController = await tryInitUrl(ep.playUrl);
      }

      // 3. Try directPlayUrl fallback
      if (activeController == null && ep.directPlayUrl.isNotEmpty && ep.directPlayUrl != streamUrl) {
        activeController = await tryInitUrl(ep.directPlayUrl);
      }

      // 4. Try refreshing token from edge server
      if (activeController == null) {
        final dramaSlug = widget.drama.slug ?? ep.slug;
        final epNum = ep.number > 0 ? ep.number : (_currentIndex + 1);
        if (dramaSlug.isNotEmpty) {
          final refreshedUrl = await NartoApiService.refreshStreamUrl(dramaSlug, epNum);
          if (refreshedUrl != null && refreshedUrl.isNotEmpty) {
            activeController = await tryInitUrl(refreshedUrl);
          }
        }
      }

      if (activeController == null) {
        throw Exception('Semua sumber video tidak dapat diputar');
      }

      final controller = activeController;
      controller.play();
      WakelockPlus.enable();

      controller.addListener(() {
        if (!mounted) return;
        if (controller.value.isInitialized) {
          final pos = controller.value.position;

          // Subtitle sync
          if (_subtitlesEnabled && _subtitles.isNotEmpty) {
            String matchText = '';
            if (_activeCueIndex >= 0 && _activeCueIndex < _subtitles.length) {
              final cur = _subtitles[_activeCueIndex];
              if (pos >= cur.start && pos <= cur.end) {
                matchText = cur.text;
              }
            }
            if (matchText.isEmpty) {
              final idx = _findCueIndex(pos);
              if (idx >= 0) {
                _activeCueIndex = idx;
                matchText = _subtitles[idx].text;
              } else {
                _activeCueIndex = -1;
              }
            }
            if (_activeSubtitleNotifier.value != matchText) {
              _activeSubtitleNotifier.value = matchText;
            }
          } else if (_activeSubtitleNotifier.value.isNotEmpty) {
            _activeSubtitleNotifier.value = '';
            _activeCueIndex = -1;
          }

          // Auto next episode
          if (pos >= controller.value.duration && controller.value.duration > Duration.zero) {
            _playNextEpisode();
          }
        }
      });

      if (mounted) {
        _cachedVideoWidget = RepaintBoundary(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        );
        setState(() {
          _controller = controller;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = 'Gagal memuat video ($e)';
        });
      }
    }
  }

  int _findCueIndex(Duration pos) {
    if (_subtitles.isEmpty) return -1;
    int low = 0;
    int high = _subtitles.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final cue = _subtitles[mid];
      if (pos < cue.start) {
        high = mid - 1;
      } else if (pos > cue.end) {
        low = mid + 1;
      } else {
        return mid;
      }
    }
    return -1;
  }

  Future<void> _loadSubtitlesForCurrentEpisode() async {
    if (widget.drama.episodes.isEmpty || _currentIndex >= widget.drama.episodes.length) return;
    final ep = widget.drama.episodes[_currentIndex];

    String subUrl = ep.effectiveSubtitleUrl;
    if (subUrl.isEmpty && ep.multiSubtitles.isNotEmpty) {
      final chosen = ep.multiSubtitles.firstWhere(
        (t) => t.languageCode.toLowerCase().startsWith('id'),
        orElse: () => ep.multiSubtitles.firstWhere(
          (t) => t.isDefault,
          orElse: () => ep.multiSubtitles.first,
        ),
      );
      subUrl = chosen.subtitleUrl;
    }

    _activeSubtitleNotifier.value = '';
    _activeCueIndex = -1;
    _subtitles = [];

    if (subUrl.isNotEmpty) {
      final cues = await NartoApiService.fetchSubtitles(subUrl);
      if (mounted) {
        setState(() {
          _subtitles = cues;
        });
      }
    }
  }

  void _playNextEpisode() {
    if (_currentIndex < widget.drama.episodes.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _savePlaybackHistory();
      _initController();
    }
  }

  void _playPreviousEpisode() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
      _savePlaybackHistory();
      _initController();
    }
  }

  void _jumpToEpisode(int index) {
    if (index >= 0 && index < widget.drama.episodes.length && index != _currentIndex) {
      setState(() {
        _currentIndex = index;
        _showEpisodeDrawer = false;
      });
      _savePlaybackHistory();
      _initController();
    }
  }

  void _togglePlayPause() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      c.pause();
      _showHudTemporarily(persistent: true);
    } else {
      c.play();
      _showHudTemporarily(persistent: false);
    }
  }

  void _seekBy(int seconds) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final cur = c.value.position;
    final dur = c.value.duration;
    var target = cur + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (target > dur) target = dur;
    c.seekTo(target);

    // Show visual seek badge
    _seekIndicatorTimer?.cancel();
    setState(() {
      _seekIndicatorText = seconds > 0 ? '+$seconds detik' : '$seconds detik';
    });
    _seekIndicatorTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() {
          _seekIndicatorText = '';
        });
      }
    });
  }

  void _showHudTemporarily({bool persistent = false}) {
    _hideControlsTimer?.cancel();
    setState(() {
      _showControls = true;
    });
    if (!persistent) {
      _hideControlsTimer = Timer(const Duration(seconds: 5), () {
        if (mounted && (_controller?.value.isPlaying ?? false)) {
          setState(() {
            _showControls = false;
          });
        }
      });
    }
  }

  KeyEventResult _handleTvKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    // Handle Play/Pause
    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause) {
      _togglePlayPause();
      return KeyEventResult.handled;
    }

    // Handle Seek FastForward / Rewind
    if (key == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(10);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaRewind) {
      _seekBy(-10);
      return KeyEventResult.handled;
    }

    // Handle Next / Prev Track
    if (key == LogicalKeyboardKey.mediaTrackNext) {
      _playNextEpisode();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaTrackPrevious) {
      _playPreviousEpisode();
      return KeyEventResult.handled;
    }

    // If Episode Drawer is open, let its focus tree handle arrows
    if (_showEpisodeDrawer) {
      if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _showEpisodeDrawer = false;
        });
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // If HUD Controls are showing, let buttons receive focus, or dismiss on back
    if (_showControls) {
      if (key == LogicalKeyboardKey.escape) {
        setState(() {
          _showControls = false;
        });
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        // Toggle down to Episode Drawer
        setState(() {
          _showControls = false;
          _showEpisodeDrawer = true;
        });
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // When playing cleanly without HUD:
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA) {
      _togglePlayPause();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-10);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      _seekBy(10);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      _showHudTemporarily(persistent: true);
      _playPauseFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _showEpisodeDrawer = true;
      });
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _seekIndicatorTimer?.cancel();
    _activeSubtitleNotifier.dispose();
    _controller?.dispose();
    _controller = null;
    _cachedVideoWidget = null;
    _rootFocusNode.dispose();
    _playPauseFocusNode.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final currentEp = (widget.drama.episodes.isNotEmpty && _currentIndex < widget.drama.episodes.length)
        ? widget.drama.episodes[_currentIndex]
        : null;

    return Focus(
      focusNode: _rootFocusNode,
      autofocus: true,
      onKeyEvent: _handleTvKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Center Video Player (Isolated cached widget)
            Center(
              child: _cachedVideoWidget != null
                  ? _cachedVideoWidget!
                  : const SizedBox.shrink(),
            ),

            // Loading indicator
            if (_isLoading)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFFFF2D55)),
                      SizedBox(height: 16),
                      Text(
                        'Memuat Episode...',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),

            // Error display
            if (_hasError)
              Container(
                color: Colors.black87,
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFFF2D55), size: 56),
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      TvFocusable(
                        autofocus: true,
                        onPressed: _initController,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        backgroundColor: const Color(0xFFFF2D55),
                        child: const Text('Coba Lagi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),

            // Subtitle Display (TV 10-foot optimized)
            if (_subtitlesEnabled)
              ValueListenableBuilder<String>(
                valueListenable: _activeSubtitleNotifier,
                builder: (context, subtitleText, child) {
                  if (subtitleText.isEmpty) return const SizedBox.shrink();
                  return Align(
                    alignment: Alignment(0, (AppSettings.subtitleVerticalOffset * 2) - 1.0),
                    child: RepaintBoundary(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 80),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppSettings.subtitleBgEnabled
                              ? Color(AppSettings.subtitleBgColor).withValues(alpha: AppSettings.subtitleBgOpacity)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          subtitleText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: AppSettings.subtitleFontSize,
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
                  );
                },
              ),

            // Seek Indicator Overlay Badge
            if (_seekIndicatorText.isNotEmpty)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFF2D55), width: 2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _seekIndicatorText.startsWith('+') ? Icons.fast_forward : Icons.fast_rewind,
                        color: const Color(0xFFFF2D55),
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _seekIndicatorText,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),

            // TV HUD Overlay (Controls)
            if (_showControls && _controller != null && _controller!.value.isInitialized)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.65),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Top Bar (Title & Episode Info)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(40, 24, 40, 0),
                        child: Row(
                          children: [
                            TvFocusable(
                              onPressed: () => Navigator.of(context).pop(),
                              padding: const EdgeInsets.all(8),
                              backgroundColor: Colors.white12,
                              child: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.drama.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Episode ${_currentIndex + 1} / ${widget.drama.episodes.length} ${currentEp != null && currentEp.title.isNotEmpty ? "• ${currentEp.title}" : ""}',
                                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Center HUD Buttons (Prev, Play/Pause, Next)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Prev Episode
                          TvFocusable(
                            onPressed: _currentIndex > 0 ? _playPreviousEpisode : null,
                            padding: const EdgeInsets.all(12),
                            backgroundColor: Colors.white12,
                            child: Icon(
                              Icons.skip_previous_rounded,
                              color: _currentIndex > 0 ? Colors.white : Colors.white24,
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 24),

                          // Rewind 10s
                          TvFocusable(
                            onPressed: () => _seekBy(-10),
                            padding: const EdgeInsets.all(12),
                            backgroundColor: Colors.white12,
                            child: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 32),
                          ),
                          const SizedBox(width: 24),

                          // Play / Pause
                          ValueListenableBuilder<VideoPlayerValue>(
                            valueListenable: _controller!,
                            builder: (context, val, child) {
                              final isPlaying = val.isPlaying;
                              return TvFocusable(
                                focusNode: _playPauseFocusNode,
                                autofocus: true,
                                onPressed: _togglePlayPause,
                                padding: const EdgeInsets.all(16),
                                backgroundColor: const Color(0xFFFF2D55),
                                child: Icon(
                                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 40,
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 24),

                          // Forward 10s
                          TvFocusable(
                            onPressed: () => _seekBy(10),
                            padding: const EdgeInsets.all(12),
                            backgroundColor: Colors.white12,
                            child: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 32),
                          ),
                          const SizedBox(width: 24),

                          // Next Episode
                          TvFocusable(
                            onPressed: _currentIndex < widget.drama.episodes.length - 1 ? _playNextEpisode : null,
                            padding: const EdgeInsets.all(12),
                            backgroundColor: Colors.white12,
                            child: Icon(
                              Icons.skip_next_rounded,
                              color: _currentIndex < widget.drama.episodes.length - 1 ? Colors.white : Colors.white24,
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 24),

                          // Subtitle Toggle
                          TvFocusable(
                            onPressed: () {
                              setState(() {
                                _subtitlesEnabled = !_subtitlesEnabled;
                              });
                            },
                            padding: const EdgeInsets.all(12),
                            backgroundColor: _subtitlesEnabled ? const Color(0xFF38BDF8).withValues(alpha: 0.25) : Colors.white12,
                            child: Icon(
                              _subtitlesEnabled ? Icons.subtitles_rounded : Icons.subtitles_off_rounded,
                              color: _subtitlesEnabled ? const Color(0xFF38BDF8) : Colors.white38,
                              size: 32,
                            ),
                          ),
                        ],
                      ),

                      // Bottom Progress & Hint Bar
                      Padding(
                        padding: const EdgeInsets.fromLTRB(40, 0, 40, 24),
                        child: Column(
                          children: [
                            ValueListenableBuilder<VideoPlayerValue>(
                              valueListenable: _controller!,
                              builder: (context, val, child) {
                                final pos = val.position;
                                final dur = val.duration;
                                final progress = dur.inMilliseconds > 0
                                    ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                                    : 0.0;
                                return Column(
                                  children: [
                                    LinearProgressIndicator(
                                      value: progress,
                                      backgroundColor: Colors.white24,
                                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF2D55)),
                                      minHeight: 6,
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(_formatDuration(pos), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                        const Text('Tekan [Bawah] untuk Daftar Episode', style: TextStyle(color: Colors.white38, fontSize: 12)),
                                        Text(_formatDuration(dur), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                      ],
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Quick Episode Drawer (Horizontal Row at bottom)
            if (_showEpisodeDrawer)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 180,
                child: Container(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.95),
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Pilih Episode (${widget.drama.episodes.length} total)',
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          const Text(
                            'Tekan [Atas] atau [Kembali] untuk menutup',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: widget.drama.episodes.length,
                          itemBuilder: (context, index) {
                            final isCur = index == _currentIndex;
                            return Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: TvFocusable(
                                autofocus: isCur,
                                onPressed: () => _jumpToEpisode(index),
                                borderRadius: BorderRadius.circular(8),
                                backgroundColor: isCur ? const Color(0xFFFF2D55) : const Color(0xFF1E293B),
                                focusedBackgroundColor: isCur ? const Color(0xFFFF2D55) : const Color(0xFF334155),
                                child: Container(
                                  width: 90,
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Text(
                                    'Ep ${index + 1}',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: isCur ? FontWeight.w900 : FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
