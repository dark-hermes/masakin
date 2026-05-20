import 'package:flutter/material.dart';

import '../services/database_helper.dart';
import '../utils/app_theme.dart';
import 'recipe_detail_screen.dart';

class SavedRecipesScreen extends StatefulWidget {
  const SavedRecipesScreen({super.key});

  @override
  State<SavedRecipesScreen> createState() => _SavedRecipesScreenState();
}

class _SavedRecipesScreenState extends State<SavedRecipesScreen> {
  late Future<List<SavedRecipe>> _savedRecipesFuture;

  @override
  void initState() {
    super.initState();
    _savedRecipesFuture = DatabaseHelper.instance.fetchSavedRecipes();
  }

  void _refreshRecipes() {
    setState(() {
      _savedRecipesFuture = DatabaseHelper.instance.fetchSavedRecipes();
    });
  }

  Future<void> _deleteRecipe(SavedRecipe recipe) async {
    final id = recipe.id;
    if (id == null) return;

    await DatabaseHelper.instance.deleteSavedRecipe(id);
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Resep tersimpan dihapus.')));
    _refreshRecipes();
  }

  Future<void> _openRecipe(SavedRecipe recipe) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecipeDetailScreen.fromSavedRecipe(recipe),
      ),
    );
    if (mounted) _refreshRecipes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _refreshRecipes(),
          color: AppColors.primary,
          child: FutureBuilder<List<SavedRecipe>>(
            future: _savedRecipesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                );
              }

              if (snapshot.hasError) {
                return _SavedRecipesMessage(
                  icon: Icons.error_outline_rounded,
                  title: 'Gagal memuat resep',
                  message: snapshot.error.toString(),
                );
              }

              final recipes = snapshot.data ?? const [];
              if (recipes.isEmpty) {
                return const _SavedRecipesMessage(
                  icon: Icons.bookmark_border_rounded,
                  title: 'Belum ada resep tersimpan',
                  message: 'Resep yang kamu simpan akan muncul di sini.',
                );
              }

              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 110),
                itemCount: recipes.length + 1,
                separatorBuilder: (_, index) => index == 0
                    ? const SizedBox(height: 18)
                    : const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (index == 0) return const _SavedRecipesHeader();

                  final recipe = recipes[index - 1];
                  return _SavedRecipeTile(
                    recipe: recipe,
                    onTap: () => _openRecipe(recipe),
                    onDelete: () => _deleteRecipe(recipe),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SavedRecipesHeader extends StatelessWidget {
  const _SavedRecipesHeader();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Resep Tersimpan',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Kumpulan resep yang sudah kamu simpan.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _SavedRecipeTile extends StatelessWidget {
  const _SavedRecipeTile({
    required this.recipe,
    required this.onTap,
    required this.onDelete,
  });

  final SavedRecipe recipe;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFFEFFDF4),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.restaurant_menu_rounded,
            color: AppColors.primary,
          ),
        ),
        title: Text(
          recipe.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${recipe.calories} • ${_formatSavedDate(recipe.savedAt)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        trailing: IconButton(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline_rounded),
          color: AppColors.textSecondary,
          tooltip: 'Hapus resep',
        ),
      ),
    );
  }

  static String _formatSavedDate(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    return '$day/$month/$year';
  }
}

class _SavedRecipesMessage extends StatelessWidget {
  const _SavedRecipesMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 120, 24, 110),
      children: [
        Icon(icon, color: AppColors.primary, size: 46),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}
