import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../services/database_helper.dart';
import '../utils/app_theme.dart';
import '../widgets/detected_ingredients_widget.dart';

class RecipeResultScreen extends StatefulWidget {
  const RecipeResultScreen({
    super.key,
    required this.detectedIngredients,
    required this.detections,
    required this.recipeMarkdown,
  });

  final List<String> detectedIngredients;
  final List<Map<String, dynamic>> detections;
  final String recipeMarkdown;

  @override
  State<RecipeResultScreen> createState() => _RecipeResultScreenState();
}

class _RecipeResultScreenState extends State<RecipeResultScreen> {
  bool _isSaving = false;

  String get _title => _extractTitle(widget.recipeMarkdown);
  String get _subtitle => _extractSubtitle(widget.recipeMarkdown);
  String get _calories => _extractNutrition(widget.recipeMarkdown, const [
    'kalori',
    'calories',
  ], defaultUnit: 'kkal');
  String get _protein => _extractNutrition(widget.recipeMarkdown, const [
    'protein',
  ], defaultUnit: 'gram');
  String get _carbs => _extractNutrition(widget.recipeMarkdown, const [
    'karbohidrat',
    'karbo',
    'carbs',
  ], defaultUnit: 'gram');
  String get _fat => _extractNutrition(widget.recipeMarkdown, const [
    'lemak',
    'fat',
  ], defaultUnit: 'gram');

  Future<void> _saveRecipe() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);
    try {
      await DatabaseHelper.instance.insertSavedRecipe(
        SavedRecipe(
          title: _title,
          contentMarkdown: widget.recipeMarkdown,
          calories: _calories,
          savedAt: DateTime.now(),
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Resep berhasil disimpan.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal menyimpan resep: $error')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSaving ? null : _saveRecipe,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: _isSaving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.bookmark_add_outlined),
        label: Text(_isSaving ? 'Menyimpan' : 'Save Recipe'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _ResultHero(title: _title, subtitle: _subtitle),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 110),
            sliver: SliverList.list(
              children: [
                _NutritionSummary(
                  calories: _calories,
                  protein: _protein,
                  carbs: _carbs,
                  fat: _fat,
                ),
                const SizedBox(height: 24),
                _DetectedIngredientsSection(
                  ingredients: widget.detectedIngredients,
                  detections: widget.detections,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Rekomendasi Resep',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: MarkdownBody(
                      data: widget.recipeMarkdown,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        h1: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                        h2: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                        h3: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                        p: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 15,
                          height: 1.5,
                        ),
                        listBullet: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        strong: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
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

  String _extractTitle(String markdown) {
    final lines = markdown
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);

    for (final line in lines) {
      final normalized = line
          .replaceFirst(RegExp(r'^#{1,6}\s*'), '')
          .replaceFirst(RegExp(r'^\d+(?:[.)]|\s|-)+'), '')
          .replaceFirst(RegExp(r'^nama resep\s*:\s*', caseSensitive: false), '')
          .replaceAll('*', '')
          .trim();
      if (normalized.isNotEmpty &&
          !normalized.toLowerCase().contains('rekomendasi')) {
        return normalized;
      }
      if (normalized.isNotEmpty) return normalized;
    }

    return 'Rekomendasi Masakan';
  }

  String _extractSubtitle(String markdown) {
    final lines = markdown
        .split('\n')
        .map((line) => line.trim().replaceAll('*', ''))
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.length < 2) return 'Resep dari bahan terdeteksi';

    final candidate = lines
        .skip(1)
        .firstWhere(
          (line) => !line.startsWith('#') && !line.contains(':'),
          orElse: () => 'Resep dari bahan terdeteksi',
        );
    return candidate.trim();
  }

  String _extractNutrition(
    String markdown,
    List<String> labels, {
    required String defaultUnit,
  }) {
    for (final label in labels) {
      final match = RegExp(
        '$label\\s*[:\\-]?\\s*([0-9]+(?:[\\.,][0-9]+)?)\\s*(kkal|kcal|cal|gram|gr|g)?',
        caseSensitive: false,
      ).firstMatch(markdown);
      if (match == null) continue;

      final value = match.group(1)?.replaceAll(',', '.') ?? '-';
      final rawUnit = match.group(2)?.toLowerCase();
      final unit = rawUnit == null || rawUnit == 'g' || rawUnit == 'gr'
          ? defaultUnit
          : rawUnit;
      return '$value $unit';
    }

    return '-';
  }
}

class _ResultHero extends StatelessWidget {
  const _ResultHero({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 256,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF8904), Color(0xFF7F1D1D)],
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Icon(
                Icons.flatware_rounded,
                color: Colors.white.withValues(alpha: 0.28),
                size: 96,
              ),
            ),
            Positioned(
              left: 24,
              top: 16,
              child: _HeroBackButton(onTap: () => Navigator.of(context).pop()),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
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
                          'Resep Sehat',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      height: 1.18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 16,
                      height: 1.35,
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

class _HeroBackButton extends StatelessWidget {
  const _HeroBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        ),
        child: const Icon(Icons.arrow_back, color: Colors.white),
      ),
    );
  }
}

class _NutritionSummary extends StatelessWidget {
  const _NutritionSummary({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  final String calories;
  final String protein;
  final String carbs;
  final String fat;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, Color(0xFF00A63E)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.2),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Color(0x33FFFFFF),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              SizedBox(width: 10),
              Text(
                'Analisis Gizi',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricTile.fromDisplay(label: 'Kalori', display: calories),
              _MetricTile.fromDisplay(label: 'Protein', display: protein),
              _MetricTile.fromDisplay(label: 'Karbo', display: carbs),
              _MetricTile.fromDisplay(label: 'Lemak', display: fat),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.unit,
  });

  factory _MetricTile.fromDisplay({
    required String label,
    required String display,
  }) {
    final cleaned = display.trim();
    if (cleaned == '-' || cleaned.isEmpty) {
      return _MetricTile(label: label, value: '-', unit: '');
    }

    final parts = cleaned.split(RegExp(r'\s+'));
    return _MetricTile(
      label: label,
      value: parts.first,
      unit: parts.length > 1 ? parts.skip(1).join(' ') : '',
    );
  }

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 90,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                unit,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetectedIngredientsSection extends StatelessWidget {
  const _DetectedIngredientsSection({
    required this.ingredients,
    required this.detections,
  });

  final List<String> ingredients;
  final List<Map<String, dynamic>> detections;

  @override
  Widget build(BuildContext context) {
    final items = detections.isNotEmpty
        ? detections
        : ingredients
              .map((ingredient) => {'name': ingredient, 'score': null})
              .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              color: AppColors.primary,
              size: 20,
            ),
            SizedBox(width: 8),
            Text(
              'Bahan Terdeteksi',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        DetectedIngredientsWidget(ingredients: items),
      ],
    );
  }
}
