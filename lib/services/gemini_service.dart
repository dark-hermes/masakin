import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  GeminiService({GenerativeModel? model}) : _model = model;

  static const defaultModel = 'gemini-2.5-flash';
  static final Schema _recipeSchema = Schema.object(
    properties: {
      'title': Schema.string(description: 'Short recipe name'),
      'description': Schema.string(description: 'One sentence description'),
      'time': Schema.string(description: 'Cooking time, for example 20 menit'),
      'calories': Schema.string(description: 'Calories, for example 250 kkal'),
      'protein': Schema.string(description: 'Protein, for example 15g'),
      'carbs': Schema.string(description: 'Carbohydrates, for example 10g'),
      'fat': Schema.string(description: 'Fat, for example 5g'),
      'ingredients': Schema.array(items: Schema.string()),
      'steps': Schema.array(items: Schema.string()),
    },
    requiredProperties: [
      'title',
      'description',
      'time',
      'calories',
      'protein',
      'carbs',
      'fat',
      'ingredients',
      'steps',
    ],
  );
  static final Schema _recipeResponseSchema = Schema.array(
    items: _recipeSchema,
  );

  GenerativeModel? _model;

  GenerativeModel get _client {
    final existing = _model;
    if (existing != null) return existing;

    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw StateError(
        'GEMINI_API_KEY is missing. Add it to .env before requesting recipes.',
      );
    }

    return _model = GenerativeModel(
      model: dotenv.env['GEMINI_MODEL']?.trim().isNotEmpty == true
          ? dotenv.env['GEMINI_MODEL']!.trim()
          : defaultModel,
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: _recipeResponseSchema,
        temperature: 0.4,
        maxOutputTokens: 2048,
      ),
      systemInstruction: Content.system(
        'You are an expert chef. Return practical recipe recommendations in Indonesian.',
      ),
    );
  }

  Future<List<dynamic>> getRecipes(List<String> detectedIngredients) async {
    final ingredients = detectedIngredients
        .map((ingredient) => ingredient.trim())
        .where((ingredient) => ingredient.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (ingredients.isEmpty) {
      throw ArgumentError('At least one detected ingredient is required.');
    }

    final prompt =
        '''
You are an expert chef. The user has these primary ingredients: ${ingredients.join(', ')}.
Provide a MAXIMUM of 3 recipe recommendations. You can provide 1, 2, or 3 recipes, but NEVER more than 3.
Rule 1: Assume the user already has basic spices and condiments (salt, sugar, pepper, water, cooking oil, garlic, onion) even if they are not in the detected list.
Rule 2: Return only a valid JSON array. Do not include Markdown, code fences, explanations, or text outside the JSON.
Rule 3: Use Indonesian recipe content. Keep every recommendation actionable and concise.
Rule 4: Every array item must follow this exact schema:
[
  {
    "title": "Short Recipe Name",
    "description": "One sentence description",
    "time": "20 menit",
    "calories": "250 kkal",
    "protein": "15g",
    "carbs": "10g",
    "fat": "5g",
    "ingredients": ["item 1", "item 2"],
    "steps": ["step 1", "step 2"]
  }
]

Return the JSON array now.
''';

    try {
      final response = await _client.generateContent([Content.text(prompt)]);
      final text = response.text?.trim();
      if (text == null || text.isEmpty) {
        return _fallbackRecipes(ingredients);
      }

      final decoded = jsonDecode(_cleanJsonText(text));
      final recipes = _extractRecipeList(decoded)
          .map(_normalizeRecipe)
          .whereType<Map<String, dynamic>>()
          .take(3)
          .toList(growable: false);

      return recipes.isEmpty ? _fallbackRecipes(ingredients) : recipes;
    } on FormatException {
      return _fallbackRecipes(ingredients);
    } on TypeError {
      return _fallbackRecipes(ingredients);
    }
  }

  String _cleanJsonText(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('```')) return trimmed;

    return trimmed
        .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();
  }

  List<dynamic> _extractRecipeList(Object? decoded) {
    if (decoded is List) return decoded;

    if (decoded is Map) {
      if (_looksLikeRecipe(decoded)) return [decoded];

      for (final key in const [
        'recipes',
        'resep',
        'recommendations',
        'rekomendasi',
        'recipeRecommendations',
        'recipe_recommendations',
        'rekomendasiResep',
        'rekomendasi_resep',
        'data',
        'items',
        'result',
        'results',
      ]) {
        final value = decoded[key];
        if (value is List) return value;
        if (value is Map) {
          final nested = _extractRecipeList(value);
          if (nested.isNotEmpty) return nested;
        }
      }

      for (final value in decoded.values) {
        final nested = _extractRecipeList(value);
        if (nested.isNotEmpty) return nested;
      }
    }

    return const [];
  }

  bool _looksLikeRecipe(Object? value) {
    if (value is! Map) return false;

    return _firstText(value, const [
          'title',
          'name',
          'recipeName',
          'recipe_name',
          'nama',
          'namaResep',
          'nama_resep',
          'judul',
        ]) !=
        null;
  }

  Map<String, dynamic>? _normalizeRecipe(Object? value) {
    if (value is! Map) return null;

    final title = _firstText(value, const [
      'title',
      'name',
      'recipeName',
      'recipe_name',
      'nama',
      'namaResep',
      'nama_resep',
      'judul',
    ]);
    if (title == null) return null;

    return {
      'title': title,
      'description':
          _firstText(value, const ['description', 'deskripsi', 'desc']) ??
          'Resep praktis berdasarkan bahan yang terdeteksi.',
      'time':
          _firstText(value, const [
            'time',
            'cookingTime',
            'cooking_time',
            'waktu',
            'waktuMasak',
            'waktu_masak',
          ]) ??
          '20 menit',
      'calories':
          _firstText(value, const ['calories', 'calorie', 'kalori']) ??
          '250 kkal',
      'protein': _firstText(value, const ['protein']) ?? '15g',
      'carbs':
          _firstText(value, const [
            'carbs',
            'carbohydrates',
            'karbo',
            'karbohidrat',
          ]) ??
          '20g',
      'fat': _firstText(value, const ['fat', 'lemak']) ?? '8g',
      'ingredients': _firstList(value, const [
        'ingredients',
        'ingredient',
        'bahan',
        'bahan_bahan',
        'bahanBahan',
      ]),
      'steps': _firstList(value, const [
        'steps',
        'instructions',
        'cara',
        'caraMasak',
        'cara_masak',
        'langkah',
        'langkahLangkah',
        'langkah_langkah',
      ]),
    };
  }

  String? _firstText(Map<dynamic, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;
      if (value is List) {
        final text = value
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .join(', ');
        if (text.isNotEmpty) return text;
        continue;
      }

      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  List<String> _firstList(Map<dynamic, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is List) {
        final items = value
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
        if (items.isNotEmpty) return items;
      }

      if (value is String) {
        final items = value
            .split(RegExp(r'[\n,;]'))
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
        if (items.isNotEmpty) return items;
      }
    }
    return const [];
  }

  List<Map<String, dynamic>> _fallbackRecipes(List<String> ingredients) {
    final primary = _titleCase(ingredients.first);
    final extra = ingredients.skip(1).map(_titleCase).take(2).toList();
    final ingredientLine = [primary, ...extra];

    return [
      {
        'title': '$primary Tumis Sederhana',
        'description':
            'Masakan cepat dari $primary dengan bumbu dasar yang ringan.',
        'time': '15 menit',
        'calories': '220 kkal',
        'protein': '12g',
        'carbs': '18g',
        'fat': '9g',
        'ingredients': [
          ...ingredientLine,
          'Bawang putih',
          'Bawang merah',
          'Garam',
          'Merica',
          'Minyak goreng',
        ],
        'steps': [
          'Iris bahan utama dan siapkan bumbu dasar.',
          'Tumis bawang hingga harum dengan sedikit minyak.',
          'Masukkan bahan utama, bumbui, lalu masak hingga matang.',
        ],
      },
      {
        'title': '$primary Bumbu Gurih',
        'description':
            'Olahan $primary yang sederhana, gurih, dan cocok untuk makan harian.',
        'time': '20 menit',
        'calories': '260 kkal',
        'protein': '15g',
        'carbs': '22g',
        'fat': '10g',
        'ingredients': [
          ...ingredientLine,
          'Bawang putih',
          'Garam',
          'Gula',
          'Air',
          'Minyak goreng',
        ],
        'steps': [
          'Siapkan bahan dan potong sesuai ukuran sekali makan.',
          'Masak bumbu dasar hingga harum.',
          'Tambahkan bahan utama dan sedikit air, lalu masak sampai bumbu meresap.',
        ],
      },
      {
        'title': '$primary Praktis Rumahan',
        'description': 'Resep rumahan yang mudah dibuat dari bahan terdeteksi.',
        'time': '25 menit',
        'calories': '300 kkal',
        'protein': '18g',
        'carbs': '24g',
        'fat': '12g',
        'ingredients': [
          ...ingredientLine,
          'Bawang merah',
          'Bawang putih',
          'Garam',
          'Merica',
          'Air',
        ],
        'steps': [
          'Bersihkan bahan utama dan siapkan bumbu.',
          'Masak bahan utama bersama bumbu sampai matang.',
          'Koreksi rasa dan sajikan selagi hangat.',
        ],
      },
    ].take(3).toList(growable: false);
  }

  String _titleCase(String value) {
    return value
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map((word) {
          final lower = word.toLowerCase();
          return '${lower[0].toUpperCase()}${lower.substring(1)}';
        })
        .join(' ');
  }
}
