import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const MyApp());
}

// متغير لحفظ اللغة الحالية (العربية افتراضياً)
final ValueNotifier<Locale> appLocale = ValueNotifier(const Locale('ar'));

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: appLocale,
      builder: (context, locale, child) {
        return MaterialApp(
          title: 'الناصح',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: const Color(0xFF1E88E5),
            scaffoldBackgroundColor: const Color(0xFF121212),
            fontFamily: 'Cairo',
          ),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('ar'),
            Locale('fr'),
            Locale('en'),
          ],
          locale: locale, // اللغة الحالية
          home: const HomeScreen(),
        );
      },
    );
  }
}
