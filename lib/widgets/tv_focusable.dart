import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reusable TV-first focusable wrapper optimized for Android TV remote D-Pad navigation.
class TvFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final FocusNode? focusNode;
  final bool autofocus;
  final double scale;
  final BorderRadius? borderRadius;
  final Color focusBorderColor;
  final double borderWidth;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final Color? focusedBackgroundColor;
  final String? tooltip;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;

  const TvFocusable({
    super.key,
    required this.child,
    this.onPressed,
    this.onLongPress,
    this.focusNode,
    this.autofocus = false,
    this.scale = 1.05,
    this.borderRadius,
    this.focusBorderColor = const Color(0xFFFF2D55), // Crimson neon
    this.borderWidth = 3.0,
    this.padding,
    this.backgroundColor,
    this.focusedBackgroundColor,
    this.tooltip,
    this.onKeyEvent,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  late FocusNode _node;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _node = widget.focusNode ?? FocusNode();
    _node.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (mounted && _isFocused != _node.hasFocus) {
      setState(() {
        _isFocused = _node.hasFocus;
      });
      if (_node.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          try {
            final ro = context.findRenderObject();
            if (ro != null && ro.attached && ro is RenderBox && ro.hasSize) {
              Scrollable.ensureVisible(
                context,
                alignment: 0.25,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
              );
            }
          } catch (_) {}
        });
      }
    }
  }

  @override
  void didUpdateWidget(TvFocusable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      _node.removeListener(_handleFocusChange);
      if (oldWidget.focusNode == null) {
        _node.dispose();
      }
      _node = widget.focusNode ?? FocusNode();
      _isFocused = _node.hasFocus;
      _node.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    _node.removeListener(_handleFocusChange);
    if (widget.focusNode == null) {
      _node.dispose();
    }
    super.dispose();
  }

  void _triggerPress() {
    if (widget.onPressed != null) {
      widget.onPressed!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(10);
    final bgColor = _isFocused
        ? (widget.focusedBackgroundColor ?? widget.backgroundColor)
        : widget.backgroundColor;

    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        if (widget.onKeyEvent != null) {
          final res = widget.onKeyEvent!(node, event);
          if (res != KeyEventResult.ignored) {
            return res;
          }
        }
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter ||
              event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA ||
              event.logicalKey == LogicalKeyboardKey.gameButtonSelect) {
            _triggerPress();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _triggerPress,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _isFocused ? widget.scale : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: widget.padding,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: radius,
              border: Border.all(
                color: _isFocused ? widget.focusBorderColor : Colors.transparent,
                width: widget.borderWidth,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: widget.focusBorderColor.withValues(alpha: 0.45),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
