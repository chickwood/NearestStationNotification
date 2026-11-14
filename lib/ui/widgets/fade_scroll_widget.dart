import 'package:material_ui/material_ui.dart';

class FadeScrollWidget extends StatefulWidget {
  const FadeScrollWidget({
    super.key,
    required this.controller,
    required this.child,
    this.fadeExtent = 24,
  });

  final ScrollController controller;
  final Widget child;
  final double fadeExtent;

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
                final stop = (widget.fadeExtent / bounds.height).clamp(
                  0.0,
                  0.5,
                );

                return LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    background.withValues(alpha: _canUp ? 0 : 1),
                    background,
                    background,
                    background.withValues(alpha: _canDown ? 0 : 1),
                  ],
                  stops: [0, stop, 1 - stop, 1],
                ).createShader(bounds);
              },
              child: widget.child,
            ),
    );
  }
}
