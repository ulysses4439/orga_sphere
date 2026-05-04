import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme(
          brightness: Brightness.light,
          primary: AppColors.navy,
          onPrimary: AppColors.textWhite,
          primaryContainer: AppColors.navyPale,
          onPrimaryContainer: AppColors.navy,
          secondary: AppColors.teal,
          onSecondary: AppColors.textWhite,
          secondaryContainer: AppColors.tealPale,
          onSecondaryContainer: AppColors.textBlack,
          surface: AppColors.appWhite,
          onSurface: AppColors.textBlack,
          error: Color(0xFFB00020),
          onError: AppColors.textWhite,
          errorContainer: Color(0xFFFFDAD6),
          onErrorContainer: Color(0xFF410002),
          outline: AppColors.lightGrey,
          outlineVariant: AppColors.navySoft,
          surfaceContainerHighest: AppColors.offWhite,
        ),
        scaffoldBackgroundColor: AppColors.offWhite,

        // App-Bar: Navy mit weißem Text
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.navy,
          foregroundColor: AppColors.textWhite,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: AppColors.textWhite,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),

        // Tab-Bar: weißer aktiver Tab, Teal-Indikator
        tabBarTheme: const TabBarThemeData(
          labelColor: AppColors.textWhite,
          unselectedLabelColor: AppColors.navySoft,
          indicatorColor: AppColors.teal,
          dividerColor: Colors.transparent,
        ),

        // FAB: Teal
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.teal,
          foregroundColor: AppColors.textWhite,
        ),

        // FilledButton (Speichern-Buttons): Teal
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.all(AppColors.teal),
            foregroundColor: WidgetStateProperty.all(AppColors.textWhite),
          ),
        ),

        // ElevatedButton: Teal
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.teal,
            foregroundColor: AppColors.textWhite,
          ),
        ),

        // TextButton (z.B. Dialoge): Teal
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: AppColors.teal),
        ),

        // Karten: weißer Hintergrund, dezenter Rahmen
        cardTheme: CardThemeData(
          color: AppColors.appWhite,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AppColors.lightGrey),
          ),
        ),

        // Divider
        dividerTheme: const DividerThemeData(color: AppColors.lightGrey),

        // Eingabefelder
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.lightGrey),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.lightGrey),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.navy, width: 2),
          ),
          filled: true,
          fillColor: AppColors.appWhite,
        ),

        // Chips (Status-Labels): keine Outline, Farbe kommt vom Widget
        chipTheme: const ChipThemeData(side: BorderSide.none),
      );
}
