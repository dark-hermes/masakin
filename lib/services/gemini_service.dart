import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  GeminiService({GenerativeModel? model}) : _model = model;

  static const defaultModel = 'gemini-2.5-flash';

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
        temperature: 0.4,
        maxOutputTokens: 2048,
      ),
      systemInstruction: Content.system(
        'You are an expert chef. Return practical recipe recommendations in Indonesian.',
      ),
    );
  }

  Future<String> getRecipes(List<String> detectedIngredients) async {
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
Provide exactly up to 3 recipe recommendations.
Rule 1: Assume the user already has basic spices and condiments (salt, sugar, pepper, water, cooking oil, garlic, onion) even if they are not in the detected list.
Rule 2: For each recipe, provide the Recipe Name, Cooking Time, and Nutritional Value (Calories, Protein, Carbs, Fat).
Rule 3: Output in a structured Markdown format.

Use Indonesian recipe content. Keep every recommendation actionable and concise.
''';

    final response = await _client.generateContent([Content.text(prompt)]);
    final text = response.text?.trim();
    if (text == null || text.isEmpty) {
      throw StateError('Gemini returned an empty recipe response.');
    }

    return text;
  }
}
