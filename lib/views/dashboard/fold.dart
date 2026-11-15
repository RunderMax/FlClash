import 'dart:ui' show lerpDouble;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import 'style.dart';

/// How tall a card stands while the cards are arranged: about an ordinary
/// card, so a tall one leaves a gap the others can pass.
const dashboardFoldedHeight = 180.0;

const _foldDuration = Duration(milliseconds: 360);
const _fadeExtent = 44.0;

/// Folds a card taller than [dashboardFoldedHeight] down to it, fading the cut
/// edge, and opens it again; a shorter card is left as it is.
class DashboardFold extends StatefulWidget {
  const DashboardFold({
    super.key,
    required this.folded,
    this.animateIn = false,
    required this.child,
  });

  final bool folded;

  /// Starts in the other state and moves to [folded] as it mounts, which is
  /// how a card folds as editing starts and opens as it ends.
  final bool animateIn;
  final Widget child;

  @override
  State<DashboardFold> createState() => _DashboardFoldState();
}

class _DashboardFoldState extends State<DashboardFold>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    value: _openness(widget.animateIn ? !widget.folded : widget.folded),
  );
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeOutCubic.flipped,
  );
  var _started = false;

  static double _openness(bool folded) => folded ? 0 : 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = context.motionDuration(_foldDuration);
    if (!_started) {
      _started = true;
      _controller.animateTo(_openness(widget.folded));
    }
  }

  @override
  void didUpdateWidget(DashboardFold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.folded != oldWidget.folded) {
      _controller.animateTo(_openness(widget.folded));
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (_, child) => _Fold(openness: _curve.value, child: child),
      child: widget.child,
    );
  }
}

class _Fold extends SingleChildRenderObjectWidget {
  const _Fold({required this.openness, super.child});

  final double openness;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFold(openness);

  @override
  void updateRenderObject(BuildContext context, _RenderFold renderObject) {
    renderObject.openness = openness;
  }
}

class _RenderFold extends RenderProxyBox {
  _RenderFold(this._openness);

  double _openness;
  final _clip = LayerHandle<ClipPathLayer>();
  final _mask = LayerHandle<ShaderMaskLayer>();
  bool _clipped = false;

  set openness(double value) {
    if (value == _openness) return;
    _openness = value;
    markNeedsLayout();
  }

  @override
  bool get alwaysNeedsCompositing => _clipped;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(
      BoxConstraints(
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
      ),
      parentUsesSize: true,
    );
    final natural = child.size.height;
    final shown = natural <= dashboardFoldedHeight
        ? natural
        : lerpDouble(dashboardFoldedHeight, natural, _openness)!;
    size = constraints.constrain(Size(child.size.width, shown));
    final clipped = size.height < natural - 0.5;
    if (clipped != _clipped) {
      _clipped = clipped;
      markNeedsCompositingBitsUpdate();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (!_clipped) {
      _clip.layer = null;
      _mask.layer = null;
      context.paintChild(child, offset);
      return;
    }
    final bounds = Offset.zero & size;
    final fadeStart = ((size.height - _fadeExtent) / size.height).clamp(0, 1);
    _clip.layer = context.pushClipPath(
      needsCompositing,
      offset,
      bounds,
      AppShape.all(DashboardCorner.mobileCard).getOuterPath(bounds),
      (context, offset) {
        final mask = (_mask.layer ??= ShaderMaskLayer())
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              Color(0xFFFFFFFF),
              Color(0xFFFFFFFF),
              Color(0x00FFFFFF),
            ],
            stops: [0, fadeStart.toDouble(), 1],
          ).createShader(bounds)
          ..maskRect = offset & size
          ..blendMode = BlendMode.dstIn;
        context.pushLayer(mask, (context, offset) {
          context.paintChild(child, offset);
        }, offset);
      },
      oldLayer: _clip.layer,
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    return super.hitTest(result, position: position);
  }

  @override
  void dispose() {
    _clip.layer = null;
    _mask.layer = null;
    super.dispose();
  }
}
