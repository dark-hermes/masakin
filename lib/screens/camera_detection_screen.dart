import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/gemini_service.dart';
import '../services/tflite_service.dart';
import '../utils/app_theme.dart';
import '../widgets/detection_mask_overlay.dart';
import 'recipe_result_screen.dart';

enum _DetectionPhase { camera, processing, preview }

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
  final TextEditingController _manualIngredientController =
      TextEditingController();

  List<CameraDescription> _cameras = const [];
  CameraController? _cameraController;
  int _cameraIndex = 0;

  _DetectionPhase _phase = _DetectionPhase.camera;
  bool _isInitializingCamera = true;
  String? _errorMessage;
  File? _previewImageFile;
  Size? _previewImageSize;
  List<Map<String, dynamic>> _detections = const [];
  List<Map<String, dynamic>> _detectedIngredients = const [];

  bool get _isProcessing => _phase == _DetectionPhase.processing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _manualIngredientController.dispose();
    _cameraController?.dispose();
    _tfliteService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;

    if (state == AppLifecycleState.inactive) {
      controller?.dispose();
      return;
    }

    if (state == AppLifecycleState.resumed &&
        _phase == _DetectionPhase.camera) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    if (_phase != _DetectionPhase.camera) return;

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
      if (!mounted || _phase != _DetectionPhase.camera) {
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
    if (_isProcessing ||
        _cameras.length < 2 ||
        _phase != _DetectionPhase.camera) {
      return;
    }

    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _initializeCamera();
  }

  Future<void> _processImage(File imageFile) async {
    Size? imageSize;

    setState(() {
      _phase = _DetectionPhase.processing;
      _errorMessage = null;
      _previewImageFile = imageFile;
      _previewImageSize = null;
      _detections = const [];
      _detectedIngredients = const [];
      _manualIngredientController.clear();
    });

    try {
      imageSize = await _decodeImageSize(imageFile);
      final detections = await _tfliteService.processImage(imageFile);
      final ingredients = _deduplicateIngredients(detections);

      if (!mounted) return;
      setState(() {
        _phase = _DetectionPhase.preview;
        _previewImageSize = imageSize;
        _detections = detections;
        _detectedIngredients = ingredients;
        if (ingredients.isEmpty) {
          _errorMessage =
              'Tidak ada bahan makanan yang melewati confidence threshold.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = imageSize == null
            ? _DetectionPhase.camera
            : _DetectionPhase.preview;
        _previewImageFile = imageSize == null ? null : imageFile;
        _previewImageSize = imageSize;
        _detections = const [];
        _detectedIngredients = const [];
        _errorMessage = 'Pemrosesan gagal: $error';
      });
    }
  }

  Future<Size> _decodeImageSize(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final decodedImage = await decodeImageFromList(bytes);
    final size = Size(
      decodedImage.width.toDouble(),
      decodedImage.height.toDouble(),
    );
    decodedImage.dispose();
    return size;
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

  double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _showRecipes() async {
    if (_isProcessing || _detectedIngredients.isEmpty) return;

    final ingredientNames = _detectedIngredients
        .map((ingredient) => ingredient['name']?.toString() ?? '')
        .where((name) => name.trim().isNotEmpty)
        .toList(growable: false);

    if (ingredientNames.isEmpty) {
      setState(() => _errorMessage = 'Bahan terdeteksi tidak valid.');
      return;
    }

    setState(() {
      _phase = _DetectionPhase.processing;
      _errorMessage = null;
    });

    try {
      final recipes = (await _geminiService.getRecipes(
        ingredientNames,
      )).take(3).toList(growable: false);
      final validRecipes = recipes
          .map(_asRecipeMap)
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);

      if (!mounted) return;
      if (validRecipes.isEmpty) {
        setState(() {
          _phase = _DetectionPhase.preview;
          _errorMessage =
              'Gemini tidak mengembalikan rekomendasi resep yang valid.';
        });
        return;
      }

      setState(() {
        _phase = _DetectionPhase.preview;
      });

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RecipeResultScreen(
            detectedIngredients: ingredientNames,
            detections: _detectedIngredients,
            recipes: validRecipes,
            previewImageFile: _previewImageFile,
            previewImageSize: _previewImageSize,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _DetectionPhase.preview;
        _errorMessage = 'Gagal mengambil rekomendasi resep: $error';
      });
    }
  }

  Map<String, dynamic>? _asRecipeMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  void _resetDetection() {
    setState(() {
      _phase = _DetectionPhase.camera;
      _errorMessage = null;
      _previewImageFile = null;
      _previewImageSize = null;
      _detections = const [];
      _detectedIngredients = const [];
    });

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      _initializeCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: _buildPhaseLayer()),
          if (_phase == _DetectionPhase.camera) ...[
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: _buildHeaderControls(),
              ),
            ),
            _buildCameraCaptureControls(),
          ],
          if (_isProcessing) _buildProcessingOverlay(),
        ],
      ),
    );
  }

  Widget _buildPhaseLayer() {
    return switch (_phase) {
      _DetectionPhase.camera => _buildCameraLayer(),
      _DetectionPhase.processing => _buildProcessingLayer(),
      _DetectionPhase.preview => _buildDetectionPreview(),
    };
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

    return _FullScreenCameraPreview(controller: controller);
  }

  Widget _buildProcessingLayer() {
    final imageFile = _previewImageFile;
    if (imageFile == null) return _buildCameraLayer();

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Image.file(
          imageFile,
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
        ),
      ),
    );
  }

  Widget _buildDetectionPreview() {
    final imageFile = _previewImageFile;
    final imageSize = _previewImageSize;

    if (imageFile == null || imageSize == null) {
      return _buildCameraLayer();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Colors.black,
          child: Image.file(
            imageFile,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
          ),
        ),
        _DetectionBoxOverlay(detections: _detections, imageSize: imageSize),
        _PreviewTopBar(onRetake: _resetDetection),
        _PreviewBottomPanel(
          detections: _detectedIngredients,
          errorMessage: _errorMessage,
          manualIngredientController: _manualIngredientController,
          onAddIngredient: _addManualIngredient,
          onShowRecipes: _detectedIngredients.isEmpty ? null : _showRecipes,
        ),
      ],
    );
  }

  void _addManualIngredient() {
    final name = _manualIngredientController.text.trim();
    if (name.isEmpty || _isProcessing) return;

    final alreadyExists = _detectedIngredients.any(
      (ingredient) =>
          ingredient['name']?.toString().trim().toLowerCase() ==
          name.toLowerCase(),
    );

    _manualIngredientController.clear();
    if (alreadyExists) return;

    setState(() {
      _errorMessage = null;
      _detectedIngredients = [
        ..._detectedIngredients,
        {'name': name, 'confidence': null, 'manual': true},
      ];
    });
  }

  Widget _buildHeaderControls() {
    return const _CameraHeaderTitle();
  }

  Widget _buildCameraCaptureControls() {
    return Positioned(
      left: 24,
      right: 24,
      bottom: math.max(28, MediaQuery.paddingOf(context).bottom + 18),
      child: _CameraControlCluster(
        onPickImage: _pickImage,
        onCaptureImage: _captureImage,
        onSwitchCamera: _switchCamera,
      ),
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

class _DetectionBoxOverlay extends StatelessWidget {
  const _DetectionBoxOverlay({
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
      fit: BoxFit.contain,
    );
  }
}

class _PreviewTopBar extends StatelessWidget {
  const _PreviewTopBar({required this.onRetake});

  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12,
      right: 12,
      top: 0,
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Tooltip(
                message: 'Ganti foto',
                child: Material(
                  color: Colors.black.withValues(alpha: 0.50),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onRetake,
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.50),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'Preview Deteksi',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewBottomPanel extends StatelessWidget {
  const _PreviewBottomPanel({
    required this.detections,
    required this.errorMessage,
    required this.manualIngredientController,
    required this.onAddIngredient,
    required this.onShowRecipes,
  });

  final List<Map<String, dynamic>> detections;
  final String? errorMessage;
  final TextEditingController manualIngredientController;
  final VoidCallback onAddIngredient;
  final VoidCallback? onShowRecipes;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Positioned(
      left: 16,
      right: 16,
      bottom: math.max(16, bottomPadding + 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      detections.isEmpty
                          ? 'Tidak ada bahan terdeteksi'
                          : '${detections.length} bahan terdeteksi',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              if (detections.isNotEmpty) ...[
                const SizedBox(height: 12),
                _DetectedPreviewChips(detections: detections),
              ],
              const SizedBox(height: 12),
              _ManualIngredientInput(
                controller: manualIngredientController,
                onSubmit: onAddIngredient,
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  errorMessage!,
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: onShowRecipes,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.textSecondary.withValues(
                      alpha: 0.28,
                    ),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white70,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.restaurant_menu_rounded, size: 20),
                  label: const Text(
                    'Lihat Resep',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
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

class _ManualIngredientInput extends StatelessWidget {
  const _ManualIngredientInput({
    required this.controller,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
            decoration: InputDecoration(
              hintText: 'Tambah bahan manual',
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 13,
                vertical: 12,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: onSubmit,
          icon: const Icon(Icons.add_circle_rounded),
          color: AppColors.primary,
          iconSize: 32,
          tooltip: 'Tambah bahan',
        ),
      ],
    );
  }
}

class _DetectedPreviewChips extends StatelessWidget {
  const _DetectedPreviewChips({required this.detections});

  final List<Map<String, dynamic>> detections;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final detection in detections.take(6))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFEFFDF4),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _chipText(detection),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  String _chipText(Map<String, dynamic> detection) {
    final name = detection['name']?.toString().trim();
    final confidence = detection['confidence'] ?? detection['score'];
    final score = _scoreText(confidence);
    if (name == null || name.isEmpty) return score;
    if (score.isEmpty) return name;
    return '$name $score';
  }

  String _scoreText(Object? value) {
    if (value is num) {
      final percentage = value <= 1 ? (value * 100).round() : value.round();
      return '$percentage%';
    }

    final parsed = double.tryParse(value?.toString() ?? '');
    if (parsed == null) return '';
    final percentage = parsed <= 1 ? (parsed * 100).round() : parsed.round();
    return '$percentage%';
  }
}

class _CameraHeaderTitle extends StatelessWidget {
  const _CameraHeaderTitle();

  @override
  Widget build(BuildContext context) {
    return const Column(
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
    );
  }
}

class _FullScreenCameraPreview extends StatelessWidget {
  const _FullScreenCameraPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (width <= 0 || height <= 0) return const SizedBox.shrink();

        final cameraAspectRatio = controller.value.aspectRatio;
        final previewAspectRatio = cameraAspectRatio <= 0
            ? width / height
            : height >= width
            ? 1 / cameraAspectRatio
            : cameraAspectRatio;

        return ClipRect(
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              alignment: Alignment.center,
              child: SizedBox(
                width: width,
                height: width / previewAspectRatio,
                child: CameraPreview(controller),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CameraControlCluster extends StatelessWidget {
  const _CameraControlCluster({
    required this.onPickImage,
    required this.onCaptureImage,
    required this.onSwitchCamera,
  });

  final VoidCallback onPickImage;
  final VoidCallback onCaptureImage;
  final VoidCallback onSwitchCamera;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _RoundActionButton(
              icon: Icons.photo_library_outlined,
              onPressed: onPickImage,
              tooltip: 'Pilih dari galeri',
            ),
          ),
          _RoundActionButton(
            icon: Icons.camera_alt_rounded,
            onPressed: onCaptureImage,
            tooltip: 'Ambil gambar',
            highlighted: true,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: _RoundActionButton(
              icon: Icons.cameraswitch_rounded,
              onPressed: onSwitchCamera,
              tooltip: 'Balik kamera',
            ),
          ),
        ],
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
    final size = highlighted ? 64.0 : 48.0;
    final iconSize = highlighted ? 30.0 : 23.0;

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
            width: size,
            height: size,
            child: Icon(icon, color: Colors.white, size: iconSize),
          ),
        ),
      ),
    );
  }
}
