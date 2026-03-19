import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/onboarding_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/profile_completion_screen.dart';
import '../../features/shared/screens/main_shell.dart';
import '../../features/my_crops/screens/my_crops_screen.dart';
import '../../features/my_crops/screens/crop_list_screen.dart';
import '../../features/my_crops/screens/add_edit_crop_screen.dart';
import '../../features/market/screens/market_prices_screen.dart';
import '../../features/ai_chat/screens/farmer_ai_screen.dart';
import '../../features/shared/screens/orders_screen.dart';
import '../../features/market/screens/market_feed_screen.dart';
import '../../features/cart_checkout/screens/cart_screen.dart';
import '../../features/cart_checkout/screens/checkout_screen.dart';
import '../../features/market/screens/crop_detail_screen.dart';
import '../../features/shared/screens/profile_screen.dart';
import '../../features/shared/screens/settings_screen.dart';
import '../../features/ai_chat/screens/ai_chat_screen.dart';
import '../../features/admin/screens/admin_dashboard.dart';
import '../../features/cart_checkout/screens/order_confirmation_screen.dart';
import '../../features/shared/screens/notifications_screen.dart';
import '../../core/models/crop_model.dart';

/// Application routes
class AppRoutes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const completeProfile = '/complete-profile';
  // ── Unified Tabs ──
  static const home = '/home';
  static const myCrops = '/my-crops';
  static const cart = '/cart';
  static const orders = '/orders';
  static const profile = '/profile';

  // ── Legacy references mapped to unified ──
  static const farmerHome = myCrops;
  static const buyerHome = home;
  static const farmerProfile = profile;
  static const buyerProfile = profile;
  static const farmerOrders = orders;
  static const buyerOrders = orders;
  static const buyerCart = cart;

  // ── Sub-routes ──
  static const farmerCrops = '/farmer/crops';
  static const farmerAddCrop = '/farmer/crops/add';
  static const farmerCropEdit = '/farmer/crops/:id/edit';
  static const farmerPrices = '/farmer/prices';
  static const farmerAI = '/farmer/ai';
  static const buyerCropDetail = '/buyer/crop/:id';
  static const buyerCheckout = '/buyer/checkout';
  static const aiChat = '/ai-chat';
  static const settings = '/settings';
  static const admin = '/admin';
  static const notifications = '/notifications';
  static const orderConfirmation = '/buyer/order-confirmed';
}

/// A provider that creates and maintains a single GoRouter instance.
final routerProvider = Provider<GoRouter>((ref) {
  final listenable = _RouterListenable(ref);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: listenable,
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Oops! Page not found.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(state.uri.path),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => context.go(AppRoutes.splash),
              child: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    ),
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final splashFinished = ref.read(splashFinishedProvider);
      final location = state.matchedLocation;

      debugPrint(
          '[Router] Redirect check: location=$location, isLoading=${authState.isLoading}, splashFinished=$splashFinished');

      // Ensure splash animation finishes before we move away from root
      if (!splashFinished && location == AppRoutes.splash) return null;

      // Handle loading state
      if (authState.isLoading && !splashFinished) return null;

      final user = authState.user;

      // ── Unauthenticated ──
      if (user == null) {
        if (splashFinished && location == AppRoutes.splash) {
          return AppRoutes.onboarding;
        }

        final publicRoutes = [
          AppRoutes.onboarding,
          AppRoutes.login,
        ];
        if (publicRoutes.contains(location)) return null;
        return AppRoutes.login;
      }

      // ── Authenticated but profile NOT completed ──
      if (!user.profileCompleted) {
        // Allow staying on complete-profile page
        if (location == AppRoutes.completeProfile) return null;
        // Redirect everywhere else to profile completion
        return AppRoutes.completeProfile;
      }

      // ── Authenticated + profile completed → redirect away from auth screens ──
      if ([
        AppRoutes.splash,
        AppRoutes.onboarding,
        AppRoutes.login,
        AppRoutes.completeProfile,
      ].contains(location)) {
        return AppRoutes.home;
      }

      return null;
    },
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, __) => const SplashScreen()),
      GoRoute(
          path: AppRoutes.onboarding,
          builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: AppRoutes.login, builder: (_, __) => const LoginScreen()),
      GoRoute(
          path: AppRoutes.completeProfile,
          builder: (_, __) => const ProfileCompletionScreen()),

      // ── Main Unified Shell ──────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          // Unified 5 Tabs
          GoRoute(path: AppRoutes.home, builder: (_, __) => const MarketFeedScreen()),
          GoRoute(path: AppRoutes.myCrops, builder: (_, __) => const MyCropsScreen()),
          GoRoute(path: AppRoutes.cart, builder: (_, __) => const CartScreen()),
          GoRoute(path: AppRoutes.orders, builder: (_, __) => const OrdersScreen()),
          GoRoute(path: AppRoutes.profile, builder: (_, __) => const ProfileScreen()),

          // Sub-routes
          GoRoute(
              path: AppRoutes.farmerCrops,
              builder: (_, __) => const CropListScreen()),
          GoRoute(
            path: AppRoutes.farmerAddCrop,
            pageBuilder: (context, state) => CustomTransitionPage(
              child: const AddEditCropScreen(),
              transitionsBuilder: (_, animation, __, child) => SlideTransition(
                position: animation.drive(
                  Tween(begin: const Offset(0, 1), end: Offset.zero)
                      .chain(CurveTween(curve: Curves.easeOutCubic)),
                ),
                child: child,
              ),
            ),
          ),
          GoRoute(
            path: AppRoutes.farmerCropEdit,
            builder: (context, state) => AddEditCropScreen(
              cropId: state.pathParameters['id'],
            ),
          ),
          GoRoute(
              path: AppRoutes.farmerPrices,
              builder: (_, __) => const MarketPricesScreen()),
          GoRoute(
              path: AppRoutes.farmerAI,
              builder: (_, __) => const FarmerAIScreen()),
          GoRoute(
            path: AppRoutes.buyerCropDetail,
            builder: (context, state) => CropDetailScreen(
              cropId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: AppRoutes.buyerCheckout,
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;
              if (extra == null) return const CartScreen();
              return CheckoutScreen(
                crop: extra['crop'] as CropModel,
                quantity: extra['quantity'] as double,
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.aiChat,
        builder: (_, __) => const AIChatScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, __) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.admin,
        builder: (_, __) => const AdminDashboard(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (_, __) => const NotificationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.orderConfirmation,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return OrderConfirmationScreen(
            orderId: extra['orderId']?.toString() ?? 'ORD-DEMO',
            cropName: extra['cropName']?.toString() ?? '',
            quantity: (extra['quantity'] as num?)?.toDouble() ?? 0,
            totalAmount: (extra['totalAmount'] as num?)?.toDouble() ?? 0,
          );
        },
      ),
    ],
  );
});

/// A Listenable that triggers GoRouter refreshes when auth state changes or splash finishes.
class _RouterListenable extends ChangeNotifier {
  _RouterListenable(Ref ref) {
    _subscription = ref.listen(
      authProvider,
      (_, __) => notifyListeners(),
    );
    _splashSubscription = ref.listen(
      splashFinishedProvider,
      (_, __) => notifyListeners(),
    );
  }
  late final ProviderSubscription _subscription;
  late final ProviderSubscription _splashSubscription;

  @override
  void dispose() {
    _subscription.close();
    _splashSubscription.close();
    super.dispose();
  }
}
