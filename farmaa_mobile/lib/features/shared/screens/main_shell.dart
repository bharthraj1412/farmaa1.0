import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../generated/l10n/app_localizations.dart';

class MainShell extends ConsumerWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final user = ref.watch(currentUserProvider);
    final isFarmer = user?.isFarmer == true || user?.isAdmin == true;
    final isBuyer = user?.isBuyer == true || user?.isAdmin == true;

    // Build dynamic destinations based on role
    final destinations = <_NavItem>[
      _NavItem(
        route: AppRoutes.home,
        icon: Icons.storefront_outlined,
        selectedIcon: Icons.storefront,
        label: l.browse,
        pathPrefix: '/home',
      ),
      if (isFarmer)
        _NavItem(
          route: AppRoutes.myCrops,
          icon: Icons.grass_outlined,
          selectedIcon: Icons.grass,
          label: l.myCrops,
          pathPrefix: '/my-crops',
          altPrefixes: ['/farmer/'],
        ),
      if (isBuyer)
        _NavItem(
          route: AppRoutes.cart,
          icon: Icons.shopping_cart_outlined,
          selectedIcon: Icons.shopping_cart,
          label: l.cart,
          pathPrefix: '/cart',
        ),
      _NavItem(
        route: AppRoutes.orders,
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long,
        label: l.orders,
        pathPrefix: '/orders',
      ),
      _NavItem(
        route: AppRoutes.profile,
        icon: Icons.person_outline,
        selectedIcon: Icons.person,
        label: l.profile,
        pathPrefix: '/profile',
      ),
    ];

    final location = GoRouterState.of(context).uri.path;
    int currentIndex = 0;
    for (int i = 0; i < destinations.length; i++) {
      if (location.startsWith(destinations[i].pathPrefix)) {
        currentIndex = i;
        break;
      }
      if (destinations[i].altPrefixes != null) {
        for (final prefix in destinations[i].altPrefixes!) {
          if (location.startsWith(prefix)) {
            currentIndex = i;
            break;
          }
        }
      }
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) => context.go(destinations[index].route),
        backgroundColor: Colors.white,
        indicatorColor: AppTheme.primaryGreen.withValues(alpha: 0.15),
        destinations: destinations
            .map((d) => NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon, color: AppTheme.primaryGreen),
                  label: d.label,
                ))
            .toList(),
      ),
    );
  }
}

class _NavItem {
  final String route;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String pathPrefix;
  final List<String>? altPrefixes;

  const _NavItem({
    required this.route,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.pathPrefix,
    this.altPrefixes,
  });
}
