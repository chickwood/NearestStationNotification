import 'package:material_ui/material_ui.dart';

class FadeScrollWidget extends StatefulWidget {
  const FadeScrollWidget({
    super.key,
    required this.controller,
    required this.child,
    this.fadeExtent = 28,
    this.edgeOpacity = 0.25,
  });

  final ScrollController controller;
  final Widget child;
  final double fadeExtent;
  final double edgeOpacity;

  @override
  State<FadeScrollWidget> createState() => _FadeScrollWidgetState();
}

class _FadeScrollWidgetState extends State<FadeScrollWidget> {
  static const double _edgeThreshold = 4;

  bool _canUp = false;
  bool _canDown = false;
  bool _updateScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
    _scheduleUpdate();
  }

  @override
  void didUpdateWidget(covariant FadeScrollWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_update);
      widget.controller.addListener(_update);
      _scheduleUpdate();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  void _scheduleUpdate() {
    if (_updateScheduled) return;
    _updateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      _update();
    });
  }

  void _update() {
    if (!mounted) return;

    var canUp = false;
    var canDown = false;
    if (widget.controller.hasClients) {
      final position = widget.controller.position;
      canUp = position.pixels > position.minScrollExtent + _edgeThreshold;
      canDown = position.pixels < position.maxScrollExtent - _edgeThreshold;
    }

    if (canUp == _canUp && canDown == _canDown) return;

    setState(() {
      _canUp = canUp;
      _canDown = canDown;
    });
  }

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;

    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        if (notification.depth == 0) _scheduleUpdate();
        return false;
      },
      child: !_canUp && !_canDown
          ? widget.child
          : ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) {
                final fade = (widget.fadeExtent / bounds.height).clamp(
                  0.0,
                  0.5,
                );
                final half = fade / 2;
                final top = _canUp ? widget.edgeOpacity : 1.0;
                final bottom = _canDown ? widget.edgeOpacity : 1.0;

                double lift(double edge) => edge + (1 - edge) * 0.65;

                return LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    background.withValues(alpha: top),
                    background.withValues(alpha: lift(top)),
                    background,
                    background,
                    background.withValues(alpha: lift(bottom)),
                    background.withValues(alpha: bottom),
                  ],
                  stops: [0, half, fade, 1 - fade, 1 - half, 1],
                ).createShader(bounds);
              },
              child: widget.child,
            ),
    );
  }
}
