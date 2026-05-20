import 'dart:io';

import 'package:flutter/material.dart';

import '../utils/app_theme.dart';
import '../widgets/detected_ingredients_widget.dart';
import '../widgets/detection_mask_overlay.dart';
import '../widgets/recipe_horizontal_list_widget.dart';
import 'recipe_detail_screen.dart';

class RecipeResultScreen extends StatefulWidget {
  const RecipeResultScreen({
    super.key,
    required this.detectedIngredients,
    required this.detections,
    required this.recipes,
    this.previewImageFile,
    this.previewImageSize,
  });

  final List<String> detectedIngredients;
  final List<Map<String, dynamic>> detections;
  final List<dynamic> recipes;
  final File? previewImageFile;
  final Size? previewImageSize;

  @override
  State<RecipeResultScreen> createState() => _RecipeResultScreenState();
}

class _RecipeResultScreenState extends State<RecipeResultScreen> {
  late List<String> _ingredients;
  late List<Map<String, dynamic>> _detections;
  late List<dynamic> _recipes;

  @override
  void initState() {
    super.initState();
    _ingredients = _dedupe(widget.detectedIngredients);
    _detections = List<Map<String, dynamic>>.from(widget.detections);
    _recipes = widget.recipes.take(3).toList(growable: false);
  }

  void _openRecipeDetail(Map<String, dynamic> recipe) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecipeDetailScreen(
          detectedIngredients: _ingredients,
          detections: _detections,
          recipe: recipe,
        ),
      ),
    );
  }

  List<String> _dedupe(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      final key = trimmed.toLowerCase();
      if (seen.add(key)) result.add(trimmed);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: _RecommendationBackground(
              imageFile: widget.previewImageFile,
              imageSize: widget.previewImageSize,
              detections: _detections,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: [
                  _HeroBackButton(onTap: () => Navigator.of(context).pop()),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'MasakIn',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            shadows: [
                              Shadow(color: Colors.black38, blurRadius: 8),
                            ],
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Rekomendasi dari bahan terdeteksi',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            shadows: [
                              Shadow(color: Colors.black45, blurRadius: 8),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.72,
            minChildSize: 0.45,
            maxChildSize: 0.92,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 48,
                          height: 5,
                          decoration: BoxDecoration(
                            color: AppColors.indicatorInactive,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      _DetectedIngredientsSection(
                        ingredients: _ingredients,
                        detections: _detections,
                      ),
                      const SizedBox(height: 30),
                      const Text(
                        'Rekomendasi Masakan',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 16),
                      RecipeHorizontalListWidget(
                        recipes: _recipes,
                        onRecipeTap: (recipe) => _openRecipeDetail(recipe),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RecommendationBackground extends StatelessWidget {
  const _RecommendationBackground({
    required this.imageFile,
    required this.imageSize,
    required this.detections,
  });

  final File? imageFile;
  final Size? imageSize;
  final List<Map<String, dynamic>> detections;

  @override
  Widget build(BuildContext context) {
    final file = imageFile;
    final size = imageSize;

    if (file == null || size == null) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF8904), Color(0xFF7F1D1D)],
          ),
        ),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(file, fit: BoxFit.cover),
          _ResultDetectionBoxOverlay(detections: detections, imageSize: size),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.42),
                  Colors.black.withValues(alpha: 0.08),
                  Colors.black.withValues(alpha: 0.30),
                ],
                stops: const [0, 0.42, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultDetectionBoxOverlay extends StatelessWidget {
  const _ResultDetectionBoxOverlay({
    required this.detections,
    required this.imageSize,
  });

  final List<Map<String, dynamic>> detections;
  final Size imageSize;

  @override
  Widget build(BuildContext context) {
    return DetectionMaskOverlay(
      detections: detections,
      imageSize: imageSize,
      fit: BoxFit.cover,
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
