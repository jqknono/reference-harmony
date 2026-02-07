import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'providers/app_state.dart';
import 'providers/theme_provider.dart';
import 'models/reference_models.dart';
import 'l10n/app_localizations.dart';
import 'pages/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ReferenceHarmonyApp());
}

class ReferenceHarmonyApp extends StatelessWidget {
  const ReferenceHarmonyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AppState()),
      ],
      child: Consumer2<ThemeProvider, AppState>(
        builder: (context, themeProvider, appState, child) {
          return MaterialApp(
            title: 'Reference Harmony',
            debugShowCheckedModeBanner: false,
            theme: themeProvider.lightTheme,
            darkTheme: themeProvider.darkTheme,
            themeMode: themeProvider.themeMode,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('zh', 'CN'),
              Locale('en', 'US'),
            ],
            locale: appState.currentLang == ReferenceLang.en
                ? const Locale('en', 'US')
                : const Locale('zh', 'CN'),
            home: const HomePage(),
          );
        },
      ),
    );
  }
}
