import 'package:flutter/material.dart';

/// Shared motion language for the studio (v1.2 polish pass): content
/// fades/slides in once when it appears, staggered in lists, instead
/// of popping. Purely presentational — no state, no timers leaking
/// into tests beyond the animation itself.
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offsetY = 14,
  });

  final Widget child;
  final Duration delay;
  final double offsetY;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380) + delay,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        // The delay is folded into the duration with the curve's
        // tail: early values clamp to invisible until the item's
        // turn comes (progress past the delay share).
        final total = 380.0 + delay.inMilliseconds;
        final local =
            ((t * total) - delay.inMilliseconds) / 380.0;
        final v = local.clamp(0.0, 1.0);
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, offsetY * (1 - v)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
