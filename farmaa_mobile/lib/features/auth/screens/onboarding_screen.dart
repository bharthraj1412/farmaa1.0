import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../generated/l10n/app_localizations.dart';

class _OnboardingPage {
  final String emoji;
  final String Function(AppLocalizations) title;
  final String Function(AppLocalizations) subtitle;
  final Color bgColor;

  const _OnboardingPage({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.bgColor,
  });
}

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with TickerProviderStateMixin {
  final _pageController = PageController();
  int _currentPage = 0;
  late AnimationController _emojiController;
  late Animation<double> _emojiScale;

  final _pages = [
    _OnboardingPage(
      emoji:    '🌾',
      title:    (l) => l.onboardingTitle1,
      subtitle: (l) => l.onboardingSub1,
      bgColor:  const Color(0xFF1B5E20),
    ),
    _OnboardingPage(
      emoji:    '📊',
      title:    (l) => l.onboardingTitle2,
      subtitle: (l) => l.onboardingSub2,
      bgColor:  const Color(0xFF4E342E),
    ),
    _OnboardingPage(
      emoji:    '🤝',
      title:    (l) => l.onboardingTitle3,
      subtitle: (l) => l.onboardingSub3,
      bgColor:  const Color(0xFF1565C0),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _emojiController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _emojiScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _emojiController, curve: Curves.elasticOut),
    );
    _emojiController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _emojiController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    _emojiController.reset();
    _emojiController.forward();
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutQuart,
      );
    } else {
      context.go(AppRoutes.login);
    }
  }

  void _toggleLanguage() {
    final current = ref.read(localeProvider);
    ref.read(localeProvider.notifier).setLocale(
      current.languageCode == 'en' ? const Locale('ta') : const Locale('en'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l       = AppLocalizations.of(context);
    final locale  = ref.watch(localeProvider);
    final isTamil = locale.languageCode == 'ta';
    final page    = _pages[_currentPage];

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [page.bgColor, page.bgColor.withValues(alpha: 0.7)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Top bar: Language toggle + Skip ────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    // Language toggle button
                    GestureDetector(
                      onTap: _toggleLanguage,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isTamil ? '🇮🇳' : '🇬🇧',
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isTamil ? 'தமிழ்' : 'English',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.swap_horiz,
                                color: Colors.white, size: 14),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Skip button
                    TextButton(
                      onPressed: () => context.go(AppRoutes.login),
                      child: Text(
                        l.skip,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Language selection hint (first page only) ───────
              if (_currentPage == 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.language,
                            color: Colors.white70, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          isTamil
                              ? 'மொழியை மேலே மாற்றலாம்'
                              : 'Tap the button above to switch language',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 8),

              // ── Page content ────────────────────────────────────
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _pages.length,
                  itemBuilder: (context, index) => _buildPage(
                    _pages[index],
                    index == _currentPage,
                    l,
                  ),
                ),
              ),

              // ── Page indicators ─────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _pages.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width:  i == _currentPage ? 28 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _currentPage
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // ── Next / Get Started button ───────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: _currentPage == _pages.length - 1
                    ? Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => context.go(AppRoutes.login),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: page.bgColor,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: AppTheme.radiusRound),
                              ),
                              child: Text(
                                l.getStarted,
                                style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                      )
                    : ElevatedButton(
                        onPressed: _nextPage,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: page.bgColor,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: AppTheme.radiusRound),
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        child: Text(
                          l.next,
                          style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPage(
    _OnboardingPage page,
    bool isActive,
    AppLocalizations l,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated emoji in a frosted circle
          ScaleTransition(
            scale: isActive ? _emojiScale : const AlwaysStoppedAnimation(1.0),
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                color:  Colors.white.withValues(alpha: 0.15),
                shape:  BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(page.emoji,
                    style: const TextStyle(fontSize: 72)),
              ),
            ),
          ),
          const SizedBox(height: 40),
          Text(
            page.title(l),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            page.subtitle(l),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15, color: Colors.white70, height: 1.6),
          ),
        ],
      ),
    );
  }
}
