import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/drama.dart';
import 'tv_focusable.dart';

class TvDramaCard extends StatelessWidget {
  final DramaItem drama;
  final VoidCallback onTap;
  final bool autofocus;
  final double width;
  final double height;
  final FocusNode? focusNode;

  const TvDramaCard({
    super.key,
    required this.drama,
    required this.onTap,
    this.autofocus = false,
    this.focusNode,
    this.width = 160,
    this.height = 240,
  });

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      onPressed: onTap,
      scale: 1.06,
      borderRadius: BorderRadius.circular(10),
      focusBorderColor: const Color(0xFFFF2D55),
      borderWidth: 3,
      backgroundColor: const Color(0xFF1E293B),
      focusedBackgroundColor: const Color(0xFF334155),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Poster with Badges
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                    child: CachedNetworkImage(
                      imageUrl: drama.posterUrl,
                      memCacheWidth: 320,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: const Color(0xFF0F172A),
                        child: const Center(
                          child: Icon(Icons.movie_outlined, color: Colors.white24, size: 36),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: const Color(0xFF0F172A),
                        child: const Center(
                          child: Icon(Icons.broken_image_outlined, color: Colors.white24, size: 36),
                        ),
                      ),
                    ),
                  ),

                  // Gradient shadow at bottom of image
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 48,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xFF1E293B), Colors.transparent],
                        ),
                      ),
                    ),
                  ),

                  // Provider tag (top left)
                  if (drama.displayProvider.isNotEmpty)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF2D55).withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.white24, width: 0.5),
                          boxShadow: const [
                            BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 1)),
                          ],
                        ),
                        child: Text(
                          drama.displayProvider,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),

                  // Episode count tag (top right)
                  if ((drama.episodeCount ?? '').isNotEmpty)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF2D55).withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${drama.episodeCount} Ep',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Title section
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Text(
                drama.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
