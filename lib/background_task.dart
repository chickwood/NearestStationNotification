import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class BackgroundTask extends StatelessWidget {
  static const _channel = MethodChannel(
    'name.w57.nearest_station_notification/background_task',
  );

  final bool moveTaskToBackground;
  final Widget child;

  const BackgroundTask({
    super.key,
    required this.moveTaskToBackground,
    required this.child,
  });

  static bool get _isNativeAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _moveTaskToBack() async {
    await _channel.invokeMethod<void>('moveTaskToBack');
  }

  @override
  Widget build(BuildContext context) {
    if (!_isNativeAndroid) return child;

    return PopScope(
      canPop: !moveTaskToBackground,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && moveTaskToBackground) {
          unawaited(_moveTaskToBack());
        }
      },
      child: child,
    );
  }
}
