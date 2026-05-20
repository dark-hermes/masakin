import 'package:flutter/material.dart';

class DetectedIngredientsWidget extends StatelessWidget {
  const DetectedIngredientsWidget({super.key, required this.ingredients});

  final List<Map<String, dynamic>> ingredients;

  static const List<Color> _dotColors = [
    Color(0xFFFF6900),
    Color(0xFF00C950),
    Color(0xFFFFB703),
    Color(0xFFFF4D4F),
    Color(0xFF8B5CF6),
    Color(0xFF06B6D4),
  ];

  @override
  Widget build(BuildContext context) {
    if (ingredients.isEmpty) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Belum ada bahan terdeteksi',
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Coba arahkan kamera lebih dekat ke bahan makanan, pastikan pencahayaan cukup, atau masukkan bahan secara manual.',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(ingredients.length, (index) {
        final ingredient = ingredients[index];
        final name = (ingredient['name'] ?? '-').toString();
        final score = _scoreText(
          ingredient['score'] ?? ingredient['confidence'],
        );

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFB9F8CF)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _dotColors[index % _dotColors.length],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$name $score',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  String _scoreText(Object? rawScore) {
    if (rawScore == null) return '';
    if (rawScore is num) {
      final value = rawScore <= 1 ? (rawScore * 100).round() : rawScore.round();
      return '$value%';
    }
    final parsed = num.tryParse(rawScore.toString());
    if (parsed == null) return '';
    final value = parsed <= 1 ? (parsed * 100).round() : parsed.round();
    return '$value%';
  }
}
