import 'package:flutter/material.dart';

/// Global navigator key – used to show dialogs from timer callbacks and
/// services that have no BuildContext of their own.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
