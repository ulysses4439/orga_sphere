import 'package:flutter/material.dart';

/// Global navigator key – used to show dialogs from timer callbacks and
/// services that have no BuildContext of their own.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Angezeigte App-Version (ohne Build-Suffix).
///
/// WICHTIG: Bei jeder Versionserhöhung an ALLEN drei Stellen anpassen:
///   1. `version:` in pubspec.yaml
///   2. diese Konstante (Anzeige in der App, Handy-Startseite)
///   3. Fenstertitel in windows/runner/main.cpp (grauer Titelbalken)
const String kAppVersion = '1.0.10';
