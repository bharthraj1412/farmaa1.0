import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages the app locale (language) with persistence.
class LocaleNotifier extends Notifier<Locale> {
  static const _key = 'farmaa_locale';
  static const _storage = FlutterSecureStorage();

  @override
  Locale build() {
    _loadLocale();
    return const Locale('en'); // default
  }

  Future<void> _loadLocale() async {
    try {
      final code = await _storage.read(key: _key);
      if (code != null) {
        state = Locale(code);
      }
    } catch (_) {}
  }

  Future<void> setLocale(Locale locale) async {
    state = locale;
    try {
      await _storage.write(key: _key, value: locale.languageCode);
    } catch (_) {}
  }

  bool get isTamil => state.languageCode == 'ta';
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(
  LocaleNotifier.new,
);
