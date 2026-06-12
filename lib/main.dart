import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'pages/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  runApp(const PdfTranslatorApp());
}

class PdfTranslatorApp extends StatelessWidget {
  const PdfTranslatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF2563EB);
    const secondary = Color(0xFF7C3AED);

    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: primary,
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFDBEAFE),
          onPrimaryContainer: const Color(0xFF172554),
          secondary: secondary,
          onSecondary: Colors.white,
          secondaryContainer: const Color(0xFFEDE9FE),
          onSecondaryContainer: const Color(0xFF2E1065),
          surface: const Color(0xFFFCFCFF),
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: const Color(0xFFF8FAFC),
          surfaceContainer: const Color(0xFFF3F6FC),
          surfaceContainerHighest: const Color(0xFFEFF3FA),
        );

    return MaterialApp(
      title: 'AI Reader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: colorScheme.surface,
        appBarTheme: AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 1,
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          surfaceTintColor: colorScheme.primary,
          iconTheme: IconThemeData(color: colorScheme.onPrimary),
          actionsIconTheme: IconThemeData(color: colorScheme.onPrimary),
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        cardTheme: CardThemeData(
          color: colorScheme.surfaceContainerLowest,
          surfaceTintColor: colorScheme.surfaceTint,
          shadowColor: colorScheme.shadow.withValues(alpha: 0.14),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: colorScheme.primary,
            side: BorderSide(color: colorScheme.outlineVariant),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: colorScheme.surfaceContainerHighest,
          selectedColor: colorScheme.primaryContainer,
          secondarySelectedColor: colorScheme.secondaryContainer,
          iconTheme: IconThemeData(color: colorScheme.primary),
          labelStyle: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.onPrimary;
            }
            return colorScheme.outline;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.primary;
            }
            return colorScheme.surfaceContainerHighest;
          }),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: colorScheme.surfaceContainerLowest,
          surfaceTintColor: colorScheme.surfaceTint,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}
