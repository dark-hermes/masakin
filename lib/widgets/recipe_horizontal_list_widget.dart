import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

class RecipeHorizontalListWidget extends StatelessWidget {
  const RecipeHorizontalListWidget({
    super.key,
    required this.recipes,
    this.onRecipeTap,
  });

  final List<dynamic> recipes;
  final ValueChanged<Map<String, dynamic>>? onRecipeTap;

  @override
  Widget build(BuildContext context) {
    final visibleRecipes = recipes
        .take(3)
        .map(_asRecipeMap)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);

    if (visibleRecipes.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Rekomendasi resep akan muncul setelah bahan terdeteksi.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 320,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: visibleRecipes.length,
        itemBuilder: (context, index) {
          final recipe = visibleRecipes[index];
          return _RecipeCard(
            recipe: recipe,
            onTap: onRecipeTap == null ? null : () => onRecipeTap!(recipe),
          );
        },
      ),
    );
  }

  Map<String, dynamic>? _asRecipeMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.recipe, this.onTap});

  final Map<String, dynamic> recipe;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final title = _text('title', fallback: 'Rekomendasi Masakan');
    final description = _text(
      'description',
      fallback: 'Resep dibuat berdasarkan bahan yang terdeteksi.',
    );
    final time = _text('time', fallback: '- menit');
    final calories = _text('calories', fallback: '- kkal');

    return Container(
      width: 260,
      margin: const EdgeInsets.only(right: 16),
      child: Material(
        color: Colors.white,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 120,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFF8904), Color(0xFFFF3131)],
                  ),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Icon(
                        Icons.flatware_rounded,
                        color: Colors.white.withValues(alpha: 0.55),
                        size: 54,
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          '+ Sehat',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              time,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.local_fire_department_rounded,
                            size: 16,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              calories,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: _MacroTile(
                              label: 'Protein',
                              value: _text('protein', fallback: '-'),
                              color: const Color(0xFFEFFDF4),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _MacroTile(
                              label: 'Karbo',
                              value: _text('carbs', fallback: '-'),
                              color: const Color(0xFFFFF7ED),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _MacroTile(
                              label: 'Lemak',
                              value: _text('fat', fallback: '-'),
                              color: const Color(0xFFFFFBEB),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _text(String key, {required String fallback}) {
    final value = recipe[key];
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }
}

class _MacroTile extends StatelessWidget {
  const _MacroTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            width: double.infinity,
            height: 16,
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
