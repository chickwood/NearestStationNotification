import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_styled_toast/flutter_styled_toast.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'common.dart';
import 'l10n.dart';
import 'ui/home_page.dart';

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

class NearestStationNotificationApp extends StatelessWidget {
  const NearestStationNotificationApp({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return StyledToast(
      child: MaterialApp(
        title: l10n.appTitle,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF4080FF), // Colors.indigo
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF4080FF),
            foregroundColor: Colors.white,
            actionsPadding: EdgeInsets.only(right: 8),
            titleSpacing: 0,
            titleTextStyle: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        // darkTheme: ThemeData(
        //   brightness: Brightness.dark,
        //   primarySwatch: Colors.blue,
        //   scaffoldBackgroundColor: Colors.grey.shade900,
        // ),
        // themeMode: ThemeMode.system,
        localizationsDelegates: const [
          L10n.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10n.supportedLocales,
        localeListResolutionCallback: (locales, _) => L10n.resolve(locales),
        home: const HomePage(),
      ),
    );
  }
}
