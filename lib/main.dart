import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'common.dart';
import 'home_page.dart';
import 'l10n.dart';
import 'notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Common.appName =
      (await PackageInfo.fromPlatform()).packageName.split('.').last;

  // // LICENSE（MIT License 本体）
  // LicenseRegistry.addLicense(() async* {
  //   final text = await rootBundle.loadString('LICENSE');
  //   yield LicenseEntryWithLineBreaks([Common.appName], text);
  // });

  // ADDITIONAL_NOTICE（station_data_xyz.bin 免責）
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('ADDITIONAL_NOTICE');
    yield LicenseEntryWithLineBreaks([Common.appName], text);
  });

  runApp(const NearestStationNotificationApp());
}

class NearestStationNotificationApp extends StatefulWidget {
  const NearestStationNotificationApp({super.key});

  @override
  State<NearestStationNotificationApp> createState() =>
      _NearestStationNotificationAppState();
}

class _NearestStationNotificationAppState
    extends State<NearestStationNotificationApp> with WidgetsBindingObserver {
  NotificationService? _service;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initialize();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _service?.stopLocating();

    super.dispose();
  }

  /// AppLifecycle 监听
  /// paused  → UI 静默，Geolocator 前台服务继续更新通知栏
  /// resumed → 恢复 UI 推送
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    _service?.changeAppLifecycleState(state);
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    super.didChangeLocales(locales);

    final l10n = AppLocalizations(switch (locales) {
      [final first, ...] => first,
      _ => const Locale('en'),
    });

    _service?.changeLocale(l10n);
  }

  @override
  Widget build(BuildContext context) {
    if (_service == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    return MaterialApp(
      title: l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4080FF), // Colors.indigo
        ),
        useMaterial3: true,
      ),
      // darkTheme: ThemeData(
      //   brightness: Brightness.dark,
      //   primarySwatch: Colors.blue,
      //   scaffoldBackgroundColor: Colors.grey.shade900,
      // ),
      // themeMode: ThemeMode.system,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: HomePage(service: _service!),
    );
  }

  Future<void> _initialize() async {
    final l10n = AppLocalizations(
      switch (WidgetsBinding.instance.platformDispatcher.locales) {
        [final first, ...] => first,
        _ => const Locale('en'),
      },
    );
    final service = NotificationService(l10n);

    await service.initService();

    setState(() {
      _service = service;
    });
  }
}
