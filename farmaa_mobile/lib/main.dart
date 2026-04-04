import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'generated/l10n/app_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/services/notification_service.dart';
import 'core/services/realtime_service.dart';
import 'core/api/api_client.dart';
import 'core/providers/locale_provider.dart';
import 'core/config/environment_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Environment configuration
  await EnvironmentConfig.init();

  // 2. Load persisted backend URL
  await ApiClient().loadPersistedBaseUrl();

  // 3. Initialize core services
  try {
    await Supabase.initialize(
      url:     EnvironmentConfig.supabaseUrl,
      anonKey: EnvironmentConfig.supabaseAnonKey,
    );
    await Firebase.initializeApp();
    await NotificationService.instance.init();
    // Start Supabase Realtime subscriptions for live price updates
    await RealtimeService.instance.init();
    debugPrint('[Farmaa] All services initialized successfully ✓');
  } catch (e) {
    debugPrint('[Farmaa] Service initialization failure (non-fatal): $e');
  }

  GoogleFonts.config.allowRuntimeFetching = true;

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:        Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('[Farmaa][FlutterError] ${details.exception}');
  };

  EnvironmentConfig.printDebugInfo();

  runApp(const ProviderScope(child: FarmaaApp()));
}

/// Called lazily after first frame to avoid blocking startup.
Future<void> initializeAppServices() async {
  // All services are initialized synchronously in main() above.
  // This function is kept for backward compatibility.
}

class FarmaaApp extends ConsumerWidget {
  const FarmaaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp.router(
      title:                  'Farmaa',
      debugShowCheckedModeBanner: false,
      theme:                  AppTheme.lightTheme,
      routerConfig:           router,
      locale:                 locale,
      supportedLocales: const [
        Locale('en'),
        Locale('ta'),
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        ErrorWidget.builder = (FlutterErrorDetails details) => Scaffold(
          backgroundColor: AppTheme.surfaceCream,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('⚠️', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 16),
                  const Text(
                    'Something went wrong',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    details.exception.toString(),
                    style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
