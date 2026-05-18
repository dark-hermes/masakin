import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/gemini_service.dart';
import '../services/tflite_service.dart';
import '../utils/app_theme.dart';
import '../widgets/detected_ingredients_widget.dart';
import '../widgets/recipe_horizontal_list_widget.dart';
import 'recipe_result_screen.dart';

class CameraDetectionScreen extends StatefulWidget {
  const CameraDetectionScreen({super.key});

  static const routeName = '/camera-detection';

  @override
  State<CameraDetectionScreen> createState() => _CameraDetectionScreenState();
}

class _CameraDetectionScreenState extends State<CameraDetectionScreen>
    with WidgetsBindingObserver {
  final TfliteService _tfliteService = TfliteService();
  final GeminiService _geminiService = GeminiService();
  final ImagePicker _imagePicker = ImagePicker();

  List<CameraDescription> _cameras = const [];
  CameraController? _cameraController;
  int _cameraIndex = 0;

  bool _isInitializingCamera = true;
  bool _isProcessing = false;
  String? _errorMessage;
  String? _recipeMarkdown;
  List<Map<String, dynamic>> _detectedIngredients = const [];
  List<Map<String, dynamic>> _recipeCards = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _tfliteService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _isInitializingCamera = true;
      _errorMessage = null;
    });

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw StateError('Kamera tidak tersedia di perangkat ini.');
      }

      final oldController = _cameraController;
      _cameraController = null;
      await oldController?.dispose();

      final safeCameraIndex = _cameraIndex
          .clamp(0, _cameras.length - 1)
          .toInt();
      final controller = CameraController(
        _cameras[safeCameraIndex],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _isInitializingCamera = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isInitializingCamera = false;
        _errorMessage = 'Gagal membuka kamera: $error';
      });
    }
  }

  Future<void> _captureImage() async {
    final controller = _cameraController;
    if (_isProcessing ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }

    try {
      final picture = await controller.takePicture();
      await _processImage(File(picture.path));
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Gagal mengambil gambar: $error');
    }
  }

  Future<void> _pickImage() async {
    if (_isProcessing) return;

    final pickedFile = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );
    if (pickedFile == null) return;

    await _processImage(File(pickedFile.path));
  }

  Future<void> _switchCamera() async {
    if (_isProcessing || _cameras.length < 2) return;

    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _initializeCamera();
  }

  Future<void> _processImage(File imageFile) async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _recipeMarkdown = null;
      _recipeCards = const [];
    });

    try {
      final detections = await _tfliteService.processImage(imageFile);
      final ingredients = _deduplicateIngredients(detections);
      final ingredientNames = ingredients
          .map((ingredient) => ingredient['name']?.toString() ?? '')
          .where((name) => name.trim().isNotEmpty)
          .toList(growable: false);

      if (ingredientNames.isEmpty) {
        if (!mounted) return;
        setState(() {
          _detectedIngredients = const [];
          _errorMessage =
              'Tidak ada bahan makanan yang melewati confidence threshold.';
        });
        return;
      }

      final markdown = await _geminiService.getRecipes(ingredientNames);
      final cards = _parseRecipeCards(markdown);

      if (!mounted) return;
      setState(() {
        _detectedIngredients = ingredients;
        _recipeMarkdown = markdown;
        _recipeCards = cards;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Pemrosesan gagal: $error');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  List<Map<String, dynamic>> _deduplicateIngredients(
    List<Map<String, dynamic>> detections,
  ) {
    final byName = <String, Map<String, dynamic>>{};

    for (final detection in detections) {
      final name = detection['name']?.toString().trim();
      if (name == null || name.isEmpty) continue;

      final current = byName[name];
      final confidence = _asDouble(detection['confidence']);
      final currentConfidence = _asDouble(current?['confidence']);

      if (current == null || confidence > currentConfidence) {
        byName[name] = detection;
      }
    }

    final result = byName.values.toList(growable: false)
      ..sort((a, b) {
        return _asDouble(b['confidence']).compareTo(_asDouble(a['confidence']));
      });

    return result;
  }

  List<Map<String, dynamic>> _parseRecipeCards(String markdown) {
    final blocks = _splitRecipeBlocks(markdown);
    return blocks
        .take(3)
        .map((block) {
          final title = _extractTitle(block);
          return {
            'title': title,
            'description': _extractDescription(block, title),
            'time': _extractTime(block),
            'calories': _extractNutrition(block, const ['kalori', 'calories']),
            'protein': _extractNutrition(block, const ['protein']),
            'carbs': _extractNutrition(block, const [
              'karbo',
              'carbs',
              'karbohidrat',
            ]),
            'fat': _extractNutrition(block, const ['lemak', 'fat']),
          };
        })
        .toList(growable: false);
  }

  List<String> _splitRecipeBlocks(String markdown) {
    final lines = markdown.split('\n');
    final blocks = <String>[];
    final current = <String>[];

    bool isRecipeStart(String line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return false;
      if (RegExp(r'^#{1,3}\s+').hasMatch(trimmed)) return true;
      return RegExp(r'^\d+(?:[.)]|\s|-)+').hasMatch(trimmed) &&
          !trimmed.toLowerCase().contains('rule');
    }

    for (final line in lines) {
      if (isRecipeStart(line) && current.isNotEmpty) {
        blocks.add(current.join('\n').trim());
        current.clear();
      }
      current.add(line);
    }

    if (current.isNotEmpty) blocks.add(current.join('\n').trim());
    final cleaned = blocks.where((block) => block.isNotEmpty).toList();
    return cleaned.isEmpty ? [markdown] : cleaned;
  }

  String _extractTitle(String block) {
    final lines = block
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);

    for (final line in lines) {
      final normalized = line
          .replaceFirst(RegExp(r'^#{1,6}\s*'), '')
          .replaceFirst(RegExp(r'^\d+(?:[.)]|\s|-)+'), '')
          .replaceAll('*', '')
          .replaceFirst(RegExp(r'^nama resep\s*:\s*', caseSensitive: false), '')
          .trim();
      if (normalized.isNotEmpty &&
          !normalized.toLowerCase().startsWith('waktu') &&
          !normalized.toLowerCase().startsWith('nilai gizi')) {
        return normalized;
      }
    }

    return 'Rekomendasi Masakan';
  }

  String _extractDescription(String block, String title) {
    final lines = block
        .split('\n')
        .map((line) => line.trim().replaceAll('*', ''))
        .where((line) => line.isNotEmpty)
        .where((line) => !line.contains(title))
        .where((line) => !line.contains(':'))
        .where((line) => !line.startsWith('-'))
        .toList(growable: false);

    return lines.isEmpty
        ? 'Resep dibuat berdasarkan bahan yang terdeteksi.'
        : lines.first;
  }

  String _extractTime(String block) {
    final match = RegExp(
      r'(?:waktu(?:\s+masak)?|cooking\s+time)\s*[:\-]?\s*([0-9]+)\s*(?:menit|min|minutes?)?',
      caseSensitive: false,
    ).firstMatch(block);
    if (match == null) return '- menit';
    return '${match.group(1)} menit';
  }

  String _extractNutrition(String block, List<String> labels) {
    for (final label in labels) {
      final match = RegExp(
        '$label\\s*[:\\-]?\\s*([0-9]+(?:[\\.,][0-9]+)?)\\s*(kkal|kcal|cal|gram|gr|g)?',
        caseSensitive: false,
      ).firstMatch(block);
      if (match != null) {
        final value = match.group(1)?.replaceAll(',', '.') ?? '-';
        final unit = match.group(2)?.toLowerCase();
        if (label == 'kalori' || label == 'calories') {
          return '$value kkal';
        }
        return '$value ${unit == null || unit == 'g' || unit == 'gr' ? 'g' : unit}';
      }
    }

    return '-';
  }

  double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  void _openResultScreen() {
    final markdown = _recipeMarkdown;
    if (markdown == null || markdown.trim().isEmpty) return;

    final ingredients = _detectedIngredients
        .map((ingredient) => ingredient['name']?.toString() ?? '')
        .where((name) => name.trim().isNotEmpty)
        .toList(growable: false);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecipeResultScreen(
          detectedIngredients: ingredients,
          detections: _detectedIngredients,
          recipeMarkdown: markdown,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _buildCameraLayer()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: _buildHeaderControls(),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.5,
            minChildSize: 0.2,
            maxChildSize: 0.9,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                      const SizedBox(height: 22),
                      _buildDetectedIngredientsSection(),
                      const SizedBox(height: 28),
                      _buildRecipeSection(),
                    ],
                  ),
                ),
              );
            },
          ),
          if (_isProcessing) _buildProcessingOverlay(),
        ],
      ),
    );
  }

  Widget _buildCameraLayer() {
    final controller = _cameraController;
    if (_isInitializingCamera) {
      return const ColoredBox(
        color: Color(0xFF1F2937),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (controller == null || !controller.value.isInitialized) {
      return Container(
        color: const Color(0xFF1F2937),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Text(
          _errorMessage ?? 'Camera feed belum tersedia.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return CameraPreview(controller);
  }

  Widget _buildHeaderControls() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MasakIn',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  shadows: [Shadow(color: Colors.black38, blurRadius: 8)],
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Scan Bahan, Temukan Masakan',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  shadows: [Shadow(color: Colors.black45, blurRadius: 8)],
                ),
              ),
            ],
          ),
        ),
        _RoundActionButton(
          icon: Icons.photo_library_outlined,
          onPressed: _pickImage,
          tooltip: 'Pilih dari galeri',
        ),
        const SizedBox(width: 10),
        _RoundActionButton(
          icon: Icons.camera_alt_rounded,
          onPressed: _captureImage,
          tooltip: 'Ambil gambar',
          highlighted: true,
        ),
        const SizedBox(width: 10),
        _RoundActionButton(
          icon: Icons.cameraswitch_rounded,
          onPressed: _switchCamera,
          tooltip: 'Balik kamera',
        ),
      ],
    );
  }

  Widget _buildDetectedIngredientsSection() {
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
        DetectedIngredientsWidget(ingredients: _detectedIngredients),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            style: const TextStyle(
              color: AppColors.accent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRecipeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Rekomendasi Masakan',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        RecipeHorizontalListWidget(
          recipes: _recipeCards,
          onRecipeTap: (_) => _openResultScreen(),
        ),
        if (_recipeMarkdown != null) ...[
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _openResultScreen,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Lihat Detail Resep',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildProcessingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.48),
        child: const Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.all(Radius.circular(18)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: 16),
                  Text(
                    'Memproses bahan makanan...',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundActionButton extends StatelessWidget {
  const _RoundActionButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.highlighted = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: highlighted
            ? AppColors.primary
            : Colors.white.withValues(alpha: 0.18),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}
