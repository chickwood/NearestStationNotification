import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class BackgroundTaskWidget extends StatelessWidget {
  final bool canPop;
  final Widget child;

  final MethodChannel _channel;

  BackgroundTaskWidget({
    super.key,
    required String channelId,
    required this.canPop,
    required this.child,
  }) : _channel = MethodChannel(channelId);

  static bool get _isNativeAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _moveTaskToBack() async {
    await _channel.invokeMethod<void>('moveTaskToBack');
  }

  @override
  Widget build(BuildContext context) {
    if (!_isNativeAndroid) return child;

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!canPop && !didPop) {
          unawaited(_moveTaskToBack());
        }
      },
      child: child,
    );
  }
}
