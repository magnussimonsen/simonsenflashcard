import 'package:flutter/material.dart';

/// Global theme-mode notifier.
/// Toggle dark mode from anywhere by setting [appThemeMode.value].
final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.system);
