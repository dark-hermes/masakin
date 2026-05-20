import 'package:flutter/material.dart';

import '../services/database_helper.dart';
import '../utils/app_theme.dart';
import 'camera_detection_screen.dart';
import 'recipe_detail_screen.dart';
import 'saved_recipes_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  static const routeName = '/main';

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  int _savedRefreshTick = 0;

  void _selectTab(int index) {
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
  }

  Future<void> _openCamera() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CameraDetectionScreen()));

    if (!mounted) return;
    setState(() => _savedRefreshTick++);
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(
        key: ValueKey(_savedRefreshTick),
        onScan: _openCamera,
        onOpenSaved: () => _selectTab(1),
      ),
      SavedRecipesScreen(key: ValueKey(_savedRefreshTick)),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: screens),
      bottomNavigationBar: _MainShellNavigation(
        selectedIndex: _selectedIndex,
        onSelectTab: _selectTab,
        onTapCenter: _openCamera,
      ),
    );
  }
}

class _MainShellNavigation extends StatelessWidget {
  const _MainShellNavigation({
    required this.selectedIndex,
    required this.onSelectTab,
    required this.onTapCenter,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onTapCenter;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: SizedBox(
          height: 106,
          child: Stack(
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                top: 16,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.09),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _ShellNavItem(
                          icon: Icons.home_rounded,
                          label: 'Beranda',
                          isSelected: selectedIndex == 0,
                          onTap: () => onSelectTab(0),
                        ),
                      ),
                      const SizedBox(width: 84),
                      Expanded(
                        child: _ShellNavItem(
                          icon: Icons.bookmark_rounded,
                          label: 'Tersimpan',
                          isSelected: selectedIndex == 1,
                          onTap: () => onSelectTab(1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.34),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: IconButton(
                  onPressed: onTapCenter,
                  tooltip: 'Scan bahan',
                  icon: const Icon(
                    Icons.camera_alt_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellNavItem extends StatelessWidget {
  const _ShellNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeColor = AppColors.primary;
    final inactiveColor = const Color(0xFF4B5563);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              scale: isSelected ? 1.1 : 1,
              child: Icon(
                icon,
                color: isSelected ? activeColor : inactiveColor,
                size: 31,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              style: TextStyle(
                color: isSelected ? activeColor : const Color(0xFF1F2937),
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onScan,
    required this.onOpenSaved,
  });

  final VoidCallback onScan;
  final VoidCallback onOpenSaved;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<SavedRecipe>> _recentRecipesFuture;

  @override
  void initState() {
    super.initState();
    _recentRecipesFuture = DatabaseHelper.instance.fetchSavedRecipes();
  }

  Future<void> _openRecipe(SavedRecipe recipe) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecipeDetailScreen.fromSavedRecipe(recipe),
      ),
    );
    if (!mounted) return;
    setState(() {
      _recentRecipesFuture = DatabaseHelper.instance.fetchSavedRecipes();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 110),
          children: [
            _HomeHero(onScan: widget.onScan),
            const SizedBox(height: 22),
            const _HowItWorksSection(),
            const SizedBox(height: 26),
            _RecentSavedSection(
              future: _recentRecipesFuture,
              onOpenSaved: widget.onOpenSaved,
              onRecipeTap: _openRecipe,
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF8904), Color(0xFF7F1D1D)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 0,
            bottom: 18,
            child: Icon(
              Icons.flatware_rounded,
              color: Colors.white.withValues(alpha: 0.22),
              size: 96,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MasakIn',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Scan bahan, cek hasil deteksi, lalu temukan resep yang cocok.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: onScan,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: const Text(
                    'Scan Bahan',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HowItWorksSection extends StatelessWidget {
  const _HowItWorksSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cara Kerja',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 20),
        const _TimelineFlow(),
      ],
    );
  }
}

class _TimelineFlow extends StatelessWidget {
  const _TimelineFlow();

  static const steps = [
    (
      number: '1',
      icon: Icons.photo_camera_rounded,
      title: 'Foto',
      subtitle: 'Ambil atau pilih gambar bahan.',
    ),
    (
      number: '2',
      icon: Icons.center_focus_strong_rounded,
      title: 'Preview',
      subtitle: 'Cek bahan atau tambah manual.',
    ),
    (
      number: '3',
      icon: Icons.restaurant_menu_rounded,
      title: 'Resep',
      subtitle: 'Dapatkan Resep yang Cocok',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 180,
          child: Stack(
            children: [
              // Garis penghubung horizontal
              Positioned(
                top: 36,
                left: 0,
                right: 0,
                child: Row(
                  children: [
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Divider(
                          height: 2,
                          thickness: 2.5,
                          color: Color(0xFFE5E7EB),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Timeline dots dan steps
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                  steps.length,
                  (index) => Expanded(
                    child: _TimelineStep(
                      number: steps[index].number,
                      icon: steps[index].icon,
                      title: steps[index].title,
                      subtitle: steps[index].subtitle,
                      isLast: index == steps.length - 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isLast,
  });

  final String number;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          // Dot dengan ikon
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.primary, size: 28),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Judul step
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          // Deskripsi step
          Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentSavedSection extends StatelessWidget {
  const _RecentSavedSection({
    required this.future,
    required this.onOpenSaved,
    required this.onRecipeTap,
  });

  final Future<List<SavedRecipe>> future;
  final VoidCallback onOpenSaved;
  final ValueChanged<SavedRecipe> onRecipeTap;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SavedRecipe>>(
      future: future,
      builder: (context, snapshot) {
        final recipes = (snapshot.data ?? const [])
            .take(3)
            .toList(growable: false);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Terakhir Disimpan',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onOpenSaved,
                  child: const Text('Lihat Semua'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            else if (recipes.isEmpty)
              const _EmptySavedPreview()
            else
              Column(
                children: [
                  for (final recipe in recipes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _RecentRecipeTile(
                        recipe: recipe,
                        onTap: () => onRecipeTap(recipe),
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _RecentRecipeTile extends StatelessWidget {
  const _RecentRecipeTile({required this.recipe, required this.onTap});

  final SavedRecipe recipe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.restaurant_menu_rounded,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      recipe.calories,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptySavedPreview extends StatelessWidget {
  const _EmptySavedPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: const Text(
        'Belum ada resep tersimpan. Resep yang kamu simpan akan muncul di sini.',
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.45,
        ),
      ),
    );
  }
}
