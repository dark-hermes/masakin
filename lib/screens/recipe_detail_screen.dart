import 'package:flutter/material.dart';

import '../services/database_helper.dart';
import '../utils/app_theme.dart';
import '../widgets/detected_ingredients_widget.dart';

class RecipeDetailScreen extends StatefulWidget {
  const RecipeDetailScreen({
    super.key,
    required this.detectedIngredients,
    required this.detections,
    required this.recipe,
  });

  factory RecipeDetailScreen.fromSavedRecipe(SavedRecipe savedRecipe) {
    return RecipeDetailScreen(
      detectedIngredients: const [],
      detections: const [],
      recipe: _recipeFromSavedRecipe(savedRecipe),
    );
  }

  final List<String> detectedIngredients;
  final List<Map<String, dynamic>> detections;
  final Map<String, dynamic> recipe;

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();

  static Map<String, dynamic> _recipeFromSavedRecipe(SavedRecipe savedRecipe) {
    final lines = savedRecipe.contentMarkdown
        .split('\n')
        .map((line) => line.trim())
        .toList(growable: false);

    final title = _firstHeading(lines) ?? savedRecipe.title;
    return {
      'title': title,
      'description': _description(lines),
      'time': _bulletValue(lines, 'Waktu', fallback: '- menit'),
      'calories': _bulletValue(lines, 'Kalori', fallback: savedRecipe.calories),
      'protein': _bulletValue(lines, 'Protein', fallback: '-'),
      'carbs': _bulletValue(lines, 'Karbo', fallback: '-'),
      'fat': _bulletValue(lines, 'Lemak', fallback: '-'),
      'ingredients': _sectionItems(lines, 'Bahan'),
      'steps': _sectionItems(lines, 'Langkah', numbered: true),
    };
  }

  static String? _firstHeading(List<String> lines) {
    for (final line in lines) {
      if (line.startsWith('# ')) return line.substring(2).trim();
    }
    return null;
  }

  static String _description(List<String> lines) {
    for (final line in lines) {
      if (line.isEmpty || line.startsWith('#') || line.startsWith('- ')) {
        continue;
      }
      return line;
    }
    return 'Resep tersimpan dari MasakIn.';
  }

  static String _bulletValue(
    List<String> lines,
    String label, {
    required String fallback,
  }) {
    final prefix = '- $label:';
    for (final line in lines) {
      if (line.toLowerCase().startsWith(prefix.toLowerCase())) {
        final value = line.substring(prefix.length).trim();
        return value.isEmpty ? fallback : value;
      }
    }
    return fallback;
  }

  static List<String> _sectionItems(
    List<String> lines,
    String heading, {
    bool numbered = false,
  }) {
    final items = <String>[];
    var inSection = false;
    final headingText = '## $heading';

    for (final line in lines) {
      if (line.toLowerCase() == headingText.toLowerCase()) {
        inSection = true;
        continue;
      }
      if (inSection && line.startsWith('## ')) break;
      if (!inSection || line.isEmpty) continue;

      var value = line;
      if (numbered) {
        value = value.replaceFirst(RegExp(r'^\d+\.\s*'), '').trim();
      } else if (value.startsWith('- ')) {
        value = value.substring(2).trim();
      }
      if (value.isNotEmpty) items.add(value);
    }

    return items;
  }
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  bool _isSaved = false;
  bool _isCheckingSaved = true;
  bool _isSaving = false;

  String get _title => _text('title', fallback: 'Detail Resep');
  String get _description => _text(
    'description',
    fallback: 'Resep dibuat berdasarkan bahan yang terdeteksi.',
  );
  String get _time => _text('time', fallback: '- menit');
  String get _calories => _text('calories', fallback: '- kkal');
  String get _protein => _text('protein', fallback: '-');
  String get _carbs => _text('carbs', fallback: '-');
  String get _fat => _text('fat', fallback: '-');
  List<String> get _ingredients => _stringList('ingredients');
  List<String> get _steps => _stringList('steps');

  @override
  void initState() {
    super.initState();
    _loadSavedState();
  }

  Future<void> _loadSavedState() async {
    final isSaved = await DatabaseHelper.instance.isRecipeSaved(_title);
    if (!mounted) return;
    setState(() {
      _isSaved = isSaved;
      _isCheckingSaved = false;
    });
  }

  Future<void> _toggleSave() async {
    if (_isSaving || _isCheckingSaved) return;

    setState(() => _isSaving = true);
    try {
      if (_isSaved) {
        await DatabaseHelper.instance.deleteSavedRecipeByTitle(_title);
      } else {
        await DatabaseHelper.instance.insertSavedRecipe(
          SavedRecipe(
            title: _title,
            contentMarkdown: _recipeAsMarkdown(),
            calories: _calories,
            savedAt: DateTime.now(),
          ),
        );
      }

      if (!mounted) return;
      setState(() => _isSaved = !_isSaved);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isSaved
                ? 'Resep berhasil disimpan.'
                : 'Resep dihapus dari tersimpan.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _text(String key, {required String fallback}) {
    final value = widget.recipe[key];
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  List<String> _stringList(String key) {
    final value = widget.recipe[key];
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }

  String _recipeAsMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# $_title')
      ..writeln()
      ..writeln(_description)
      ..writeln()
      ..writeln('- Waktu: $_time')
      ..writeln('- Kalori: $_calories')
      ..writeln('- Protein: $_protein')
      ..writeln('- Karbo: $_carbs')
      ..writeln('- Lemak: $_fat')
      ..writeln()
      ..writeln('## Bahan');

    for (final ingredient in _ingredients) {
      buffer.writeln('- $ingredient');
    }

    buffer
      ..writeln()
      ..writeln('## Langkah');
    for (var index = 0; index < _steps.length; index++) {
      buffer.writeln('${index + 1}. ${_steps[index]}');
    }

    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _SaveRecipeButton(
        isSaved: _isSaved,
        isBusy: _isCheckingSaved || _isSaving,
        onPressed: _toggleSave,
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _ResultHero(
              title: _title,
              description: _description,
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              24,
              28,
              24,
              MediaQuery.paddingOf(context).bottom + 180,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _NutritionSummary(
                  calories: _calories,
                  protein: _protein,
                  carbs: _carbs,
                  fat: _fat,
                ),
                const SizedBox(height: 28),
                if (widget.detections.isNotEmpty) ...[
                  _DetectedIngredientsSection(detections: widget.detections),
                  const SizedBox(height: 28),
                ],
                _RecipeDetailCard(
                  description: _description,
                  time: _time,
                  ingredients: _ingredients,
                  steps: _steps,
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveRecipeButton extends StatelessWidget {
  const _SaveRecipeButton({
    required this.isSaved,
    required this.isBusy,
    required this.onPressed,
  });

  final bool isSaved;
  final bool isBusy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final background = isSaved ? const Color(0xFF6B7280) : AppColors.primary;
    final label = isBusy
        ? 'Memuat'
        : isSaved
        ? 'Tersimpan'
        : 'Simpan Resep';
    final icon = isSaved ? Icons.bookmark_rounded : Icons.bookmark_border;

    return FloatingActionButton.extended(
      onPressed: isBusy ? null : onPressed,
      backgroundColor: background,
      foregroundColor: Colors.white,
      elevation: 10,
      icon: isBusy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Colors.white,
              ),
            )
          : Icon(icon),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
    );
  }
}

class _ResultHero extends StatelessWidget {
  const _ResultHero({
    required this.title,
    required this.description,
    required this.onBack,
  });

  final String title;
  final String description;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 292),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          24,
          MediaQuery.paddingOf(context).top + 24,
          24,
          28,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF8904), Color(0xFF7F1D1D)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: 28,
              top: 72,
              child: Icon(
                Icons.flatware_rounded,
                color: Colors.white.withValues(alpha: 0.26),
                size: 112,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeroBackButton(onTap: onBack),
                const SizedBox(height: 52),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
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
                        size: 16,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Resep Sehat',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  description,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
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
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        ),
        child: const Icon(Icons.arrow_back, color: Colors.white, size: 26),
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
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Color(0xFF35D66F),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Analisis Gizi',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _NutritionMetricsGrid(
            metrics: [
              _NutritionMetric('Kalori', calories, ''),
              _NutritionMetric('Protein', protein, ''),
              _NutritionMetric('Karbo', carbs, ''),
              _NutritionMetric('Lemak', fat, ''),
            ],
          ),
        ],
      ),
    );
  }
}

class _NutritionMetricsGrid extends StatelessWidget {
  const _NutritionMetricsGrid({required this.metrics});

  final List<_NutritionMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 360 ? 4 : 2;
        const spacing = 10.0;
        final tileWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: tileWidth,
                child: _MetricTile(metric: metric),
              ),
          ],
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric});

  final _NutritionMetric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 112,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            metric.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 34,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                metric.value,
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          if (metric.unit.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              metric.unit,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NutritionMetric {
  const _NutritionMetric(this.label, this.value, this.unit);

  final String label;
  final String value;
  final String unit;
}

class _DetectedIngredientsSection extends StatelessWidget {
  const _DetectedIngredientsSection({required this.detections});

  final List<Map<String, dynamic>> detections;

  @override
  Widget build(BuildContext context) {
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
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        DetectedIngredientsWidget(ingredients: detections),
      ],
    );
  }
}

class _RecipeDetailCard extends StatelessWidget {
  const _RecipeDetailCard({
    required this.description,
    required this.time,
    required this.ingredients,
    required this.steps,
  });

  final String description;
  final String time;
  final List<String> ingredients;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Text(
                  'Detail Resep',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _TimeBadge(time: time),
            ],
          ),
          const SizedBox(height: 16),
          Text(description, style: AppTextStyles.body),
          const SizedBox(height: 24),
          const _SectionHeading(
            icon: Icons.shopping_basket_rounded,
            title: 'Bahan',
          ),
          const SizedBox(height: 12),
          _BulletList(emptyText: 'Bahan tidak tersedia.', items: ingredients),
          const SizedBox(height: 24),
          const _SectionHeading(icon: Icons.list_alt_rounded, title: 'Langkah'),
          const SizedBox(height: 12),
          _StepList(steps: steps),
        ],
      ),
    );
  }
}

class _TimeBadge extends StatelessWidget {
  const _TimeBadge({required this.time});

  final String time;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 116),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule_rounded, color: AppColors.accent, size: 16),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              time,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.items, required this.emptyText});

  final List<String> items;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return Text(emptyText, style: AppTextStyles.body);

    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: CircleAvatar(
                    radius: 3,
                    backgroundColor: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(item, style: AppTextStyles.body)),
              ],
            ),
          ),
      ],
    );
  }
}

class _StepList extends StatelessWidget {
  const _StepList({required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) {
      return const Text(
        'Langkah memasak tidak tersedia.',
        style: AppTextStyles.body,
      );
    }

    return Column(
      children: List.generate(steps.length, (index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(steps[index], style: AppTextStyles.body)),
            ],
          ),
        );
      }),
    );
  }
}
