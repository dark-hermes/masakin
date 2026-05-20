import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_theme.dart';
import 'main_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const routeName = '/onboarding';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _onboardingSeenKey = 'onboarding_seen';
  late final PageController _pageController;
  int _currentPage = 0;

  static const _pages = [
    _OnboardingData(
      title: 'Scan Bahan\nMasakan',
      description:
          'Deteksi berbagai bahan makanan\nsecara otomatis menggunakan AI',
      buttonLabel: 'Lanjutkan',
      illustration: _OnboardingIllustrationType.ingredients,
    ),
    _OnboardingData(
      title: 'Rekomendasi\nMasakan Pintar',
      description:
          'Dapatkan rekomendasi resep\nberdasarkan bahan yang kamu miliki',
      buttonLabel: 'Lanjutkan',
      illustration: _OnboardingIllustrationType.recipe,
    ),
    _OnboardingData(
      title: 'Analisis Gizi\nOtomatis',
      description: 'Lihat kalori dan kandungan gizi hasil\nanalisis AI',
      buttonLabel: 'Mulai Sekarang',
      illustration: _OnboardingIllustrationType.nutrition,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _completeOnboardingAndOpenMain() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingSeenKey, true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const MainScreen()),
    );
  }

  void _skipToMain() {
    _completeOnboardingAndOpenMain();
  }

  void _handlePrimaryAction() {
    if (_currentPage == _pages.length - 1) {
      _skipToMain();
      return;
    }

    _goToPage(_currentPage + 1);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final horizontalPadding = (size.width * 0.0815).clamp(24.0, 32.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _OnboardingHeader(
              currentPage: _currentPage,
              onBack: _currentPage > 0
                  ? () => _goToPage(_currentPage - 1)
                  : null,
              onSkip: _currentPage < _pages.length - 1 ? _skipToMain : null,
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemBuilder: (context, index) {
                  return _OnboardingPage(
                    data: _pages[index],
                    pageIndex: index,
                    horizontalPadding: horizontalPadding,
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                0,
                horizontalPadding,
                48,
              ),
              child: Column(
                children: [
                  _DotIndicator(
                    itemCount: _pages.length,
                    currentIndex: _currentPage,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 8,
                        shadowColor: AppColors.primary.withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _handlePrimaryAction,
                      child: Text(
                        _pages[_currentPage].buttonLabel,
                        style: AppTextStyles.button,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingHeader extends StatelessWidget {
  const _OnboardingHeader({
    required this.currentPage,
    required this.onBack,
    required this.onSkip,
  });

  final int currentPage;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (onBack == null)
              const SizedBox(width: 112)
            else
              TextButton.icon(
                onPressed: onBack,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF364153),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(112, 40),
                  alignment: Alignment.centerLeft,
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                icon: const Icon(Icons.arrow_back, size: 20),
                label: const Text('Kembali'),
              ),
            if (onSkip == null)
              const SizedBox(width: 84)
            else
              TextButton(
                onPressed: onSkip,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF99A1AF),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(84, 40),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                child: const Text('Lewati'),
              ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.data,
    required this.pageIndex,
    required this.horizontalPadding,
  });

  final _OnboardingData data;
  final int pageIndex;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompactHeight = constraints.maxHeight < 520;
        final illustrationHeightFactor = switch (data.illustration) {
          _OnboardingIllustrationType.nutrition =>
            isCompactHeight ? 0.68 : 0.74,
          _ => isCompactHeight ? 0.46 : 0.52,
        };
        final maxIllustrationWidth = switch (data.illustration) {
          _OnboardingIllustrationType.ingredients => 328.0,
          _OnboardingIllustrationType.recipe => 288.0,
          _OnboardingIllustrationType.nutrition => 288.0,
        };
        final illustrationSize = math
            .min(
              constraints.maxWidth - horizontalPadding * 2,
              maxIllustrationWidth,
            )
            .toDouble();
        final titleTopGap = isCompactHeight
            ? 16.0
            : switch (data.illustration) {
                _OnboardingIllustrationType.nutrition => 24.0,
                _ => 40.0,
              };
        final descriptionGap = isCompactHeight ? 10.0 : 16.0;

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                children: [
                  SizedBox(
                    height: constraints.maxHeight * illustrationHeightFactor,
                    child: Align(
                      alignment:
                          data.illustration ==
                              _OnboardingIllustrationType.nutrition
                          ? Alignment.topCenter
                          : Alignment.center,
                      child: _OnboardingIllustration(
                        type: data.illustration,
                        size: illustrationSize,
                      ),
                    ),
                  ),
                  SizedBox(height: titleTopGap),
                  Text(
                    data.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: descriptionGap),
                  Text(
                    data.description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      height: 1.625,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OnboardingIllustration extends StatelessWidget {
  const _OnboardingIllustration({required this.type, required this.size});

  final _OnboardingIllustrationType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    return switch (type) {
      _OnboardingIllustrationType.ingredients => _IngredientsIllustration(
        size: size,
      ),
      _OnboardingIllustrationType.recipe => _RecipeIllustration(width: size),
      _OnboardingIllustrationType.nutrition => _NutritionIllustration(
        width: size,
      ),
    };
  }
}

class _IngredientsIllustration extends StatelessWidget {
  const _IngredientsIllustration({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final cardWidth = size * 0.78;
    final cardHeight = cardWidth * 1.25;

    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: cardWidth,
            height: cardHeight,
            padding: EdgeInsets.all(cardWidth * 0.047),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF3F4F6), Color(0xFFE5E7EB)],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 34,
                  offset: const Offset(0, 25),
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFF9FAFB), Colors.white],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: constraints.maxHeight * 0.5,
                        child: Container(
                          height: 2,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                AppColors.primary,
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      _DetectedFood(
                        left: constraints.maxWidth * 0.11,
                        top: constraints.maxHeight * 0.12,
                        size: constraints.maxWidth * 0.27,
                        color: const Color(0xFFFF6467),
                        label: 'Tomat',
                        shape: BoxShape.circle,
                      ),
                      _DetectedFood(
                        left: constraints.maxWidth * 0.655,
                        top: constraints.maxHeight * 0.285,
                        size: constraints.maxWidth * 0.205,
                        color: const Color(0xFFFFB86A),
                        label: 'Wortel',
                        shape: BoxShape.circle,
                      ),
                      _DetectedFood(
                        left: constraints.maxWidth * 0.18,
                        top: constraints.maxHeight * 0.65,
                        size: constraints.maxWidth * 0.24,
                        color: const Color(0xFFDAB2FF),
                        label: 'Terong',
                        shape: BoxShape.rectangle,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          Positioned(
            right: size * 0.105,
            top: size * 0.12,
            child: const _SparkleBadge(size: 32),
          ),
        ],
      ),
    );
  }
}

class _DetectedFood extends StatelessWidget {
  const _DetectedFood({
    required this.left,
    required this.top,
    required this.size,
    required this.color,
    required this.label,
    required this.shape,
  });

  final double left;
  final double top;
  final double size;
  final Color color;
  final String label;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      child: SizedBox(
        width: size + 8,
        height: size + 30,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color,
                shape: shape,
                borderRadius: shape == BoxShape.rectangle
                    ? BorderRadius.circular(10)
                    : null,
              ),
            ),
            Positioned(
              top: -4,
              child: Container(
                width: size + 8,
                height: size + 8,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.primary, width: 2),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            Positioned(
              top: size + 4,
              child: Container(
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecipeIllustration extends StatelessWidget {
  const _RecipeIllustration({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final cardHeight = width * 0.857;

    return SizedBox(
      width: width,
      height: width * 0.86,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: width * 0.04,
            top: width * 0.035,
            child: Transform.rotate(
              angle: 0.052,
              child: _BackCard(
                width: width * 0.89,
                color: const Color(0xFFE5E7EB).withValues(alpha: 0.5),
              ),
            ),
          ),
          Positioned(
            left: width * 0.015,
            top: width * 0.01,
            child: Transform.rotate(
              angle: -0.035,
              child: _BackCard(
                width: width * 0.945,
                color: const Color(0xFFD1D5DC).withValues(alpha: 0.7),
              ),
            ),
          ),
          Container(
            width: width,
            height: cardHeight,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 44,
                  offset: const Offset(0, 25),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 108,
                  child: Stack(
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFFF8904), Color(0xFFFB2C36)],
                          ),
                        ),
                      ),
                      Center(
                        child: Container(
                          width: width * 0.333,
                          height: width * 0.333,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.3),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.flatware_rounded,
                            color: Colors.white,
                            size: width * 0.22,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          height: 24,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome_rounded,
                                color: Colors.white,
                                size: 12,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'AI Match',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 100,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tumis Sayur Spesial',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Row(
                          children: [
                            _RecipeChip(
                              label: '3 bahan cocok',
                              backgroundColor: Color(0xFFDCFCE7),
                              foregroundColor: Color(0xFF008236),
                            ),
                            SizedBox(width: 8),
                            _RecipeChip(
                              label: '20 menit',
                              backgroundColor: Color(0xFFFFEDD4),
                              foregroundColor: Color(0xFFCA3500),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Row(
                          children: List.generate(
                            5,
                            (_) => const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.star_rounded,
                                color: AppColors.accent,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BackCard extends StatelessWidget {
  const _BackCard({required this.width, required this.color});

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: width * 0.706,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
      ),
    );
  }
}

class _RecipeChip extends StatelessWidget {
  const _RecipeChip({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foregroundColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }
}

class _NutritionIllustration extends StatelessWidget {
  const _NutritionIllustration({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      constraints: BoxConstraints(minHeight: width * 1.333),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 34,
            offset: const Offset(0, 25),
          ),
        ],
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Analisis Gizi',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              _SparkleBadge(size: 40),
            ],
          ),
          const SizedBox(height: 22),
          const _CalorieRing(),
          const SizedBox(height: 24),
          const _NutritionBar(
            label: 'Protein',
            value: 0.65,
            valueLabel: '65%',
            color: AppColors.primary,
          ),
          const SizedBox(height: 10),
          const _NutritionBar(
            label: 'Karbohidrat',
            value: 0.80,
            valueLabel: '80%',
            color: AppColors.accent,
          ),
          const SizedBox(height: 10),
          const _NutritionBar(
            label: 'Lemak',
            value: 0.45,
            valueLabel: '45%',
            color: Color(0xFFFFB900),
          ),
        ],
      ),
    );
  }
}

class _CalorieRing extends StatelessWidget {
  const _CalorieRing();

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 128,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: const Size.square(128), painter: _RingPainter()),
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '450',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'kkal',
                style: TextStyle(
                  color: Color(0xFF6A7282),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final strokeWidth = 8.0;
    final backgroundPaint = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final greenPaint = Paint()
      ..color = const Color(0xFF4DAF50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final orangePaint = Paint()
      ..color = const Color(0xFFC8871D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      rect.deflate(strokeWidth / 2),
      0,
      math.pi * 2,
      false,
      backgroundPaint,
    );
    canvas.drawArc(
      rect.deflate(strokeWidth / 2),
      -math.pi * 0.52,
      math.pi * 0.42,
      false,
      orangePaint,
    );
    canvas.drawArc(
      rect.deflate(strokeWidth / 2),
      math.pi * 0.34,
      math.pi * 0.42,
      false,
      greenPaint,
    );
    canvas.drawArc(
      rect.deflate(strokeWidth / 2),
      math.pi * 0.88,
      math.pi * 0.36,
      false,
      greenPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _NutritionBar extends StatelessWidget {
  const _NutritionBar({
    required this.label,
    required this.value,
    required this.valueLabel,
    required this.color,
  });

  final String label;
  final double value;
  final String valueLabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            Text(
              valueLabel,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 8,
            backgroundColor: const Color(0xFFE5E7EB),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _SparkleBadge extends StatelessWidget {
  const _SparkleBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(
        Icons.auto_awesome_rounded,
        color: Colors.white,
        size: size * 0.56,
      ),
    );
  }
}

class _DotIndicator extends StatelessWidget {
  const _DotIndicator({required this.itemCount, required this.currentIndex});

  final int itemCount;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(itemCount, (index) {
        final isActive = index == currentIndex;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: isActive ? 32 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: isActive ? AppColors.accent : AppColors.indicatorInactive,
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}

class _OnboardingData {
  const _OnboardingData({
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.illustration,
  });

  final String title;
  final String description;
  final String buttonLabel;
  final _OnboardingIllustrationType illustration;
}

enum _OnboardingIllustrationType { ingredients, recipe, nutrition }
