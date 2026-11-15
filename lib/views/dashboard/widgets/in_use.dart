import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';

/// A frame and a badge both say a row carries traffic, so a glance finds it
/// without reading.
class InUseFrame extends StatelessWidget {
  const InUseFrame({
    super.key,
    required this.inUse,
    required this.radius,
    required this.child,
  });

  final bool inUse;
  final double radius;
  final Widget child;

  static const _border = 1.5;

  @override
  Widget build(BuildContext context) {
    final primary = context.colorScheme.primary;
    final shape = AppShape.all(radius);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: inUse ? 1 : 0),
      duration: context.motionDuration(commonDuration),
      curve: Curves.easeOutCubic,
      builder: (context, emphasis, child) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: shape.copyWith(
            side: BorderSide(
              color: primary.withValues(alpha: emphasis),
              width: _border,
            ),
          ),
        ),
        child: child,
      ),
      child: child,
    );
  }
}

class InUseBadge extends StatelessWidget {
  const InUseBadge({super.key, required this.inUse});

  final bool inUse;

  static const _size = 26.0;

  @override
  Widget build(BuildContext context) {
    final duration = context.motionDuration(commonDuration);
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOutCubic,
      alignment: AlignmentDirectional.centerStart,
      child: AnimatedSwitcher(
        duration: duration,
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: inUse
            ? const Padding(
                key: ValueKey(true),
                padding: EdgeInsetsDirectional.only(end: 10),
                child: SelectionBadge(size: _size),
              )
            : const SizedBox.shrink(key: ValueKey(false)),
      ),
    );
  }
}
