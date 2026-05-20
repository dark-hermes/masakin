import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class TfliteService {
  TfliteService({
    this.modelPath = 'assets/model.tflite',
    this.labelsPath = 'assets/labels.txt',
    this.confidenceThreshold = 0.5,
    this.iouThreshold = 0.45,
    this.maxResults = 20,
    this.useBgrOrder = false,
  });

  static const int inputSize = 640;

  final String modelPath;
  final String labelsPath;
  final double confidenceThreshold;
  final double iouThreshold;
  final int maxResults;
  final bool useBgrOrder;

  Interpreter? _interpreter;
  List<String> _labels = const [];
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    final options = InterpreterOptions();
    if (Platform.isAndroid) {
      options.addDelegate(XNNPackDelegate());
    }

    _interpreter = await Interpreter.fromAsset(modelPath, options: options);
    final rawLabels = await rootBundle.loadString(labelsPath);
    _labels = rawLabels
        .split(RegExp(r'\r?\n'))
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .toList(growable: false);

    if (kDebugMode) {
      final inputTensor = _interpreter!.getInputTensor(0);
      final outputTensors = _interpreter!.getOutputTensors();
      print('[TfliteService] Model loaded: $modelPath');
      print('[TfliteService]   Input: shape=${inputTensor.shape}, type=${inputTensor.type}');
      print('[TfliteService]   Outputs: ${outputTensors.map((t) => 'shape=${t.shape}, type=${t.type}').join('; ')}');
      print('[TfliteService]   Labels: $_labels');
      print('[TfliteService]   BGR order: $useBgrOrder');
    }

    _isInitialized = true;
  }

  Future<List<Map<String, dynamic>>> processImage(File imageFile) async {
    await initialize();

    final interpreter = _interpreter;
    if (interpreter == null) {
      throw StateError('TFLite interpreter is not initialized.');
    }

    final bytes = await imageFile.readAsBytes();
    final decodedImage = img.decodeImage(bytes);
    if (decodedImage == null) {
      throw ArgumentError('Cannot decode image: ${imageFile.path}');
    }

    final inputTensor = interpreter.getInputTensor(0);
    final inputShape = inputTensor.shape;
    if (inputShape.length != 4) {
      throw StateError('Unsupported YOLO input shape: $inputShape');
    }

    final sourceImage = img.bakeOrientation(decodedImage);
    final letterboxed = _letterboxImage(sourceImage);

    final input = _buildInputTensor(
      image: letterboxed.image,
      tensor: inputTensor,
      isNchw: inputShape[1] == 3,
    );

    final outputTensors = interpreter.getOutputTensors();
    if (outputTensors.isEmpty) {
      throw StateError('Model has no output tensors.');
    }

    final outputs = <int, Object>{};
    for (var i = 0; i < outputTensors.length; i++) {
      outputs[i] = _createTensorBuffer(outputTensors[i]);
    }

    interpreter.runForMultipleInputs([input], outputs);

    if (kDebugMode) {
      for (var i = 0; i < outputTensors.length; i++) {
        final flat = _flattenTensorValues(outputs[i], outputTensors[i]);
        final sample = flat.take(10).toList();
        final min = flat.isEmpty ? 0.0 : flat.reduce(math.min);
        final max = flat.isEmpty ? 0.0 : flat.reduce(math.max);
        print('[TfliteService]   Output[$i]: shape=${outputTensors[i].shape}, values=${flat.length}, range=[$min, $max], sample=$sample');
      }
    }

    final detectionOutput = _selectDetectionOutput(outputs, outputTensors);
    final detTensor = detectionOutput.tensor;
    final detShape = detTensor.shape;
    final flat = _flattenTensorValues(detectionOutput.output, detTensor);

    // Detect if this is a post-NMS model (Ultralytics TFLite export with
    // built-in NMS). Format: [1, maxDet, 4+1+1+maskCoeffs] where channels
    // contain [xmin, ymin, xmax, ymax, confidence, classIndex, ...masks].
    // Heuristic: channel 5 values are integers (class indices) in [0, numClasses).
    final isPostNms = _isPostNmsFormat(flat, detShape);

    if (kDebugMode) {
      print('[TfliteService]   Post-NMS format detected: $isPostNms');
    }

    List<_DetectionCandidate> candidates;
    int maskCoefficientCount;

    if (isPostNms) {
      final parsed = _parsePostNmsOutput(
        flat: flat,
        shape: detShape,
        transform: letterboxed.transform,
      );
      candidates = parsed.detections;
      maskCoefficientCount = parsed.maskCoefficientCount;
    } else {
      final parsedOutput = _parseYoloOutput(
        output: detectionOutput.output,
        tensor: detTensor,
        transform: letterboxed.transform,
      );
      candidates = parsedOutput.detections;
      maskCoefficientCount = parsedOutput.maskCoefficientCount;
    }

    if (kDebugMode) {
      print('[TfliteService]   Detections found: ${candidates.length} (threshold=$confidenceThreshold)');
      final top5 = candidates.toList()
        ..sort((a, b) => b.confidence.compareTo(a.confidence));
      for (final d in top5.take(5)) {
        print('[TfliteService]     ${d.name}: conf=${d.confidence.toStringAsFixed(4)}, box=(${d.box.left.toStringAsFixed(3)}, ${d.box.top.toStringAsFixed(3)}, ${d.box.right.toStringAsFixed(3)}, ${d.box.bottom.toStringAsFixed(3)})');
      }
    }

    final maskPrototype = maskCoefficientCount <= 0
        ? null
        : _selectMaskPrototype(
            outputs: outputs,
            outputTensors: outputTensors,
            detectionOutputIndex: detectionOutput.index,
            maskCoefficientCount: maskCoefficientCount,
          );

    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));

    // Skip NMS for post-NMS models (already applied inside the model).
    final filtered = isPostNms
        ? candidates.take(maxResults).toList()
        : _nonMaxSuppression(candidates).take(maxResults).toList();

    final selected = filtered
        .map(
          (detection) => detection.toMap(
            imageWidth: letterboxed.transform.imageWidth,
            imageHeight: letterboxed.transform.imageHeight,
            transform: letterboxed.transform,
            maskPrototype: maskPrototype,
          ),
        )
        .toList(growable: false);

    return selected;
  }

  _LetterboxedImage _letterboxImage(img.Image source) {
    final scale = math.min(inputSize / source.width, inputSize / source.height);
    final resizedWidth = math.max(1, (source.width * scale).round());
    final resizedHeight = math.max(1, (source.height * scale).round());
    final padLeft = ((inputSize - resizedWidth) / 2).floor();
    final padTop = ((inputSize - resizedHeight) / 2).floor();

    final canvas = img.Image(width: inputSize, height: inputSize);
    img.fill(canvas, color: img.ColorRgb8(114, 114, 114));

    final resized = img.copyResize(
      source,
      width: resizedWidth,
      height: resizedHeight,
      interpolation: img.Interpolation.linear,
    );
    img.compositeImage(canvas, resized, dstX: padLeft, dstY: padTop);

    return _LetterboxedImage(
      image: canvas,
      transform: _LetterboxTransform(
        imageWidth: source.width,
        imageHeight: source.height,
        inputSize: inputSize,
        scale: scale,
        padLeft: padLeft.toDouble(),
        padTop: padTop.toDouble(),
      ),
    );
  }

  Object _buildInputTensor({
    required img.Image image,
    required Tensor tensor,
    required bool isNchw,
  }) {
    num convertChannel(num channelValue) {
      final normalized = channelValue / 255.0;

      if (tensor.type == TensorType.float32 ||
          tensor.type == TensorType.float16) {
        return normalized;
      }

      if (tensor.type == TensorType.uint8 || tensor.type == TensorType.int8) {
        final params = tensor.params;
        if (params.scale > 0) {
          final quantized = (normalized / params.scale + params.zeroPoint)
              .round();
          if (tensor.type == TensorType.int8) {
            return quantized.clamp(-128, 127);
          }
          return quantized.clamp(0, 255);
        }
      }

      return channelValue.round().clamp(0, 255);
    }

    if (isNchw) {
      return [
        List.generate(
          3,
          (channel) => List.generate(
            inputSize,
            (y) => List.generate(inputSize, (x) {
              final pixel = image.getPixel(x, y);
              final mappedChannel = useBgrOrder ? (2 - channel) : channel;
              return switch (mappedChannel) {
                0 => convertChannel(pixel.r),
                1 => convertChannel(pixel.g),
                _ => convertChannel(pixel.b),
              };
            }),
          ),
        ),
      ];
    }

    return [
      List.generate(
        inputSize,
        (y) => List.generate(inputSize, (x) {
          final pixel = image.getPixel(x, y);
          if (useBgrOrder) {
            return [
              convertChannel(pixel.b),
              convertChannel(pixel.g),
              convertChannel(pixel.r),
            ];
          }
          return [
            convertChannel(pixel.r),
            convertChannel(pixel.g),
            convertChannel(pixel.b),
          ];
        }),
      ),
    ];
  }

  Object _createTensorBuffer(Tensor tensor) {
    final zero = switch (tensor.type) {
      TensorType.float32 || TensorType.float16 || TensorType.float64 => 0.0,
      _ => 0,
    };
    final safeShape = tensor.shape
        .map((dimension) => math.max(dimension, 1))
        .toList(growable: false);

    Object build(int depth) {
      if (depth == safeShape.length) return zero;
      return List.generate(safeShape[depth], (_) => build(depth + 1));
    }

    return build(0);
  }

  ({int index, Object output, Tensor tensor}) _selectDetectionOutput(
    Map<int, Object> outputs,
    List<Tensor> outputTensors,
  ) {
    for (var i = 0; i < outputTensors.length; i++) {
      final tensor = outputTensors[i];
      if (_isYoloDetectionShape(tensor.shape)) {
        return (index: i, output: outputs[i]!, tensor: tensor);
      }
    }

    throw StateError(
      'No YOLO detection output found. Output shapes: '
      '${outputTensors.map((tensor) => tensor.shape).toList()}',
    );
  }

  bool _isYoloDetectionShape(List<int> shape) {
    if (shape.length == 3) {
      final dim1 = shape[1];
      final dim2 = shape[2];
      return _looksLikeAnchorChannelPair(dim1, dim2) ||
          _looksLikeAnchorChannelPair(dim2, dim1);
    }

    if (shape.length == 2) {
      final dim1 = shape[0];
      final dim2 = shape[1];
      return _looksLikeAnchorChannelPair(dim1, dim2) ||
          _looksLikeAnchorChannelPair(dim2, dim1);
    }

    return false;
  }

  bool _looksLikeAnchorChannelPair(int anchors, int channels) {
    if (anchors <= channels) return false;
    if (channels < _minimumYoloChannels) return false;

    final maxExpectedChannels = _labels.isEmpty
        ? 4 + 1000
        : 4 + _labels.length + 128;
    return channels <= maxExpectedChannels;
  }

  int get _minimumYoloChannels => 4 + math.max(1, _labels.length);

  /// Detects if the output tensor is in post-NMS format from Ultralytics
  /// TFLite export. In this format:
  /// - Shape is [1, maxDetections, channels] where channels = 4+1+1+maskCoeffs
  /// - Channel 4 is confidence (0-1)
  /// - Channel 5 is class index (integer)
  bool _isPostNmsFormat(List<double> flat, List<int> shape) {
    if (shape.length != 3) return false;

    final numDetections = shape[1];
    final channels = shape[2];

    // Post-NMS format has exactly 6+ channels (4 box + 1 conf + 1 classIdx + masks)
    // and channel 5 should contain integer-like values (class indices).
    if (channels < 6) return false;
    if (numDetections > 1000) return false; // raw YOLO has 8400 anchors

    // Check first few valid detections: channel 4 should be in [0,1] (confidence)
    // and channel 5 should be a non-negative integer (class index).
    var postNmsVotes = 0;
    var rawVotes = 0;
    final samplesToCheck = math.min(10, numDetections);

    for (var i = 0; i < samplesToCheck; i++) {
      final baseIdx = i * channels;
      if (baseIdx + 5 >= flat.length) break;

      final conf = flat[baseIdx + 4];
      final classIdx = flat[baseIdx + 5];

      // In post-NMS: conf is [0,1], classIdx is integer >= 0
      if (conf >= 0 && conf <= 1 && classIdx >= 0 && classIdx == classIdx.roundToDouble()) {
        postNmsVotes++;
      } else {
        rawVotes++;
      }
    }

    return postNmsVotes > rawVotes;
  }

  /// Parses post-NMS output format: [1, maxDetections, 4+1+1+maskCoeffs]
  /// where each detection is [xmin, ymin, xmax, ymax, confidence, classIndex, ...maskCoeffs]
  /// Box coordinates are normalized (0-1) relative to the letterboxed 640x640 input.
  ({List<_DetectionCandidate> detections, int maskCoefficientCount})
  _parsePostNmsOutput({
    required List<double> flat,
    required List<int> shape,
    required _LetterboxTransform transform,
  }) {
    final numDetections = shape[1];
    final channels = shape[2];
    final maskCoefficientCount = math.max(0, channels - 6);

    if (kDebugMode) {
      print('[TfliteService]   Post-NMS: detections=$numDetections, channels=$channels, maskCoeffs=$maskCoefficientCount');
    }

    final detections = <_DetectionCandidate>[];

    for (var i = 0; i < numDetections; i++) {
      final baseIdx = i * channels;
      if (baseIdx + 5 >= flat.length) break;

      final confidence = flat[baseIdx + 4];
      if (confidence < confidenceThreshold) continue;

      final classIndex = flat[baseIdx + 5].round();
      if (classIndex < 0) continue;

      // Box coordinates are normalized [0,1] relative to input (640x640)
      final xMin = flat[baseIdx + 0];
      final yMin = flat[baseIdx + 1];
      final xMax = flat[baseIdx + 2];
      final yMax = flat[baseIdx + 3];

      // Convert from normalized input coords to image coords
      final inputXMin = xMin * inputSize;
      final inputYMin = yMin * inputSize;
      final inputXMax = xMax * inputSize;
      final inputYMax = yMax * inputSize;

      final imageLeft = transform.inputXToImage(inputXMin);
      final imageTop = transform.inputYToImage(inputYMin);
      final imageRight = transform.inputXToImage(inputXMax);
      final imageBottom = transform.inputYToImage(inputYMax);

      final box = _BoundingBox(
        left: (imageLeft / transform.imageWidth).clamp(0.0, 1.0),
        top: (imageTop / transform.imageHeight).clamp(0.0, 1.0),
        right: (imageRight / transform.imageWidth).clamp(0.0, 1.0),
        bottom: (imageBottom / transform.imageHeight).clamp(0.0, 1.0),
        inputLeft: xMin.clamp(0.0, 1.0),
        inputTop: yMin.clamp(0.0, 1.0),
        inputRight: xMax.clamp(0.0, 1.0),
        inputBottom: yMax.clamp(0.0, 1.0),
      );

      if (!box.isValid) continue;

      final maskCoefficients = maskCoefficientCount == 0
          ? const <double>[]
          : flat.sublist(baseIdx + 6, baseIdx + 6 + maskCoefficientCount);

      detections.add(
        _DetectionCandidate(
          name: _labelFor(classIndex),
          classIndex: classIndex,
          confidence: confidence,
          box: box,
          maskCoefficients: maskCoefficients,
        ),
      );
    }

    return (detections: detections, maskCoefficientCount: maskCoefficientCount);
  }

  ({List<_DetectionCandidate> detections, int maskCoefficientCount})
  _parseYoloOutput({
    required Object output,
    required Tensor tensor,
    required _LetterboxTransform transform,
  }) {
    final shape = tensor.shape;
    final flat = _flattenTensorValues(output, tensor);
    if (flat.isEmpty) {
      return (detections: const [], maskCoefficientCount: 0);
    }

    final layout = _resolveYoloLayout(shape);
    final classCount = _resolveClassCount(layout.channels);
    final maskCoefficientCount = math.max(0, layout.channels - 4 - classCount);

    if (kDebugMode) {
      print('[TfliteService]   YOLO layout: shape=$shape, anchors=${layout.anchors}, channels=${layout.channels}, channelsFirst=${layout.channelsFirst}, classCount=$classCount, maskCoeffs=$maskCoefficientCount');
      // Log first few anchors' raw values to verify data layout
      for (var a = 0; a < math.min(3, layout.anchors); a++) {
        final rawValues = List.generate(
          math.min(layout.channels, 14),
          (ch) => _valueAt(flat: flat, layout: layout, anchor: a, channel: ch)
              .toStringAsFixed(3),
        );
        print('[TfliteService]   Anchor[$a] raw: $rawValues');
      }
    }

    if (classCount <= 0) {
      return (detections: const [], maskCoefficientCount: maskCoefficientCount);
    }

    final detections = <_DetectionCandidate>[];
    for (var anchor = 0; anchor < layout.anchors; anchor++) {
      final xCenter = _valueAt(
        flat: flat,
        layout: layout,
        anchor: anchor,
        channel: 0,
      );
      final yCenter = _valueAt(
        flat: flat,
        layout: layout,
        anchor: anchor,
        channel: 1,
      );
      final width = _valueAt(
        flat: flat,
        layout: layout,
        anchor: anchor,
        channel: 2,
      );
      final height = _valueAt(
        flat: flat,
        layout: layout,
        anchor: anchor,
        channel: 3,
      );

      var bestClassIndex = 0;
      var bestScore = double.negativeInfinity;
      for (var classIndex = 0; classIndex < classCount; classIndex++) {
        final score = _scoreToProbability(
          _valueAt(
            flat: flat,
            layout: layout,
            anchor: anchor,
            channel: 4 + classIndex,
          ),
        );

        if (score > bestScore) {
          bestScore = score;
          bestClassIndex = classIndex;
        }
      }

      if (bestScore < confidenceThreshold) continue;

      final box = _BoundingBox.fromCenter(
        xCenter: xCenter,
        yCenter: yCenter,
        width: width,
        height: height,
        transform: transform,
      );
      if (!box.isValid) continue;

      final maskCoefficients = maskCoefficientCount == 0
          ? const <double>[]
          : List.generate(
              maskCoefficientCount,
              (index) => _valueAt(
                flat: flat,
                layout: layout,
                anchor: anchor,
                channel: 4 + classCount + index,
              ),
              growable: false,
            );

      detections.add(
        _DetectionCandidate(
          name: _labelFor(bestClassIndex),
          classIndex: bestClassIndex,
          confidence: bestScore,
          box: box,
          maskCoefficients: maskCoefficients,
        ),
      );
    }

    return (detections: detections, maskCoefficientCount: maskCoefficientCount);
  }

  _YoloLayout _resolveYoloLayout(List<int> shape) {
    if (shape.length == 3) {
      final dim1 = shape[1];
      final dim2 = shape[2];

      if (_looksLikeAnchorChannelPair(dim1, dim2)) {
        return _YoloLayout(anchors: dim1, channels: dim2, channelsFirst: false);
      }

      if (_looksLikeAnchorChannelPair(dim2, dim1)) {
        return _YoloLayout(anchors: dim2, channels: dim1, channelsFirst: true);
      }
    }

    if (shape.length == 2) {
      final dim1 = shape[0];
      final dim2 = shape[1];

      if (_looksLikeAnchorChannelPair(dim1, dim2)) {
        return _YoloLayout(anchors: dim1, channels: dim2, channelsFirst: false);
      }

      if (_looksLikeAnchorChannelPair(dim2, dim1)) {
        return _YoloLayout(anchors: dim2, channels: dim1, channelsFirst: true);
      }
    }

    throw StateError('Unsupported YOLO detection output shape: $shape');
  }

  int _resolveClassCount(int channels) {
    final availableAfterBox = channels - 4;
    if (availableAfterBox <= 0) return 0;

    if (_labels.isNotEmpty) {
      return math.min(_labels.length, availableAfterBox);
    }

    return availableAfterBox;
  }

  _MaskPrototype? _selectMaskPrototype({
    required Map<int, Object> outputs,
    required List<Tensor> outputTensors,
    required int detectionOutputIndex,
    required int maskCoefficientCount,
  }) {
    for (var i = 0; i < outputTensors.length; i++) {
      if (i == detectionOutputIndex) continue;

      final tensor = outputTensors[i];
      final layout = _resolveMaskPrototypeLayout(
        tensor.shape,
        maskCoefficientCount,
      );
      if (layout == null) continue;

      return _MaskPrototype(
        values: _flattenTensorValues(outputs[i], tensor),
        width: layout.width,
        height: layout.height,
        channels: layout.channels,
        channelsFirst: layout.channelsFirst,
      );
    }

    return null;
  }

  _MaskPrototypeLayout? _resolveMaskPrototypeLayout(
    List<int> shape,
    int maskCoefficientCount,
  ) {
    if (shape.length == 4) {
      final dim1 = shape[1];
      final dim2 = shape[2];
      final dim3 = shape[3];

      if (dim1 == maskCoefficientCount && dim2 > 1 && dim3 > 1) {
        return _MaskPrototypeLayout(
          width: dim3,
          height: dim2,
          channels: dim1,
          channelsFirst: true,
        );
      }

      if (dim3 == maskCoefficientCount && dim1 > 1 && dim2 > 1) {
        return _MaskPrototypeLayout(
          width: dim2,
          height: dim1,
          channels: dim3,
          channelsFirst: false,
        );
      }
    }

    if (shape.length == 3) {
      final dim0 = shape[0];
      final dim1 = shape[1];
      final dim2 = shape[2];

      if (dim0 == maskCoefficientCount && dim1 > 1 && dim2 > 1) {
        return _MaskPrototypeLayout(
          width: dim2,
          height: dim1,
          channels: dim0,
          channelsFirst: true,
        );
      }

      if (dim2 == maskCoefficientCount && dim0 > 1 && dim1 > 1) {
        return _MaskPrototypeLayout(
          width: dim1,
          height: dim0,
          channels: dim2,
          channelsFirst: false,
        );
      }
    }

    return null;
  }

  double _valueAt({
    required List<double> flat,
    required _YoloLayout layout,
    required int anchor,
    required int channel,
  }) {
    final index = layout.channelsFirst
        ? channel * layout.anchors + anchor
        : anchor * layout.channels + channel;

    if (index < 0 || index >= flat.length) return 0;
    return flat[index];
  }

  List<_DetectionCandidate> _nonMaxSuppression(
    List<_DetectionCandidate> detections,
  ) {
    final selected = <_DetectionCandidate>[];

    for (final detection in detections) {
      final overlapsExisting = selected.any(
        (kept) => _iou(detection.box, kept.box) >= iouThreshold,
      );
      if (!overlapsExisting) selected.add(detection);
    }

    return selected;
  }

  double _iou(_BoundingBox a, _BoundingBox b) {
    final left = math.max(a.left, b.left);
    final top = math.max(a.top, b.top);
    final right = math.min(a.right, b.right);
    final bottom = math.min(a.bottom, b.bottom);

    final intersectionWidth = math.max(0.0, right - left);
    final intersectionHeight = math.max(0.0, bottom - top);
    final intersection = intersectionWidth * intersectionHeight;
    final union = a.area + b.area - intersection;

    if (union <= 0) return 0;
    return intersection / union;
  }

  double _scoreToProbability(double value) {
    // Always apply sigmoid for YOLO raw logits.
    // Values in [0,1] are NOT necessarily probabilities — they are logits
    // that happen to fall in that range and still need sigmoid transformation.
    return 1 / (1 + math.exp(-value));
  }

  List<double> _flattenTensorValues(Object? value, Tensor tensor) {
    final values = <double>[];
    final shouldDequantize =
        tensor.type == TensorType.uint8 ||
        tensor.type == TensorType.int8 ||
        tensor.type == TensorType.int16;
    final params = shouldDequantize ? tensor.params : null;

    void visit(Object? node) {
      if (node is num) {
        final rawValue = node.toDouble();
        if (params != null && params.scale > 0) {
          values.add(params.scale * (rawValue - params.zeroPoint));
        } else {
          values.add(rawValue);
        }
        return;
      }

      if (node is Iterable) {
        for (final child in node) {
          visit(child);
        }
      }
    }

    visit(value);
    return values;
  }

  String _labelFor(int index) {
    if (index >= 0 && index < _labels.length) return _labels[index];
    return 'Class $index';
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}

class _YoloLayout {
  const _YoloLayout({
    required this.anchors,
    required this.channels,
    required this.channelsFirst,
  });

  final int anchors;
  final int channels;
  final bool channelsFirst;
}

class _MaskPrototypeLayout {
  const _MaskPrototypeLayout({
    required this.width,
    required this.height,
    required this.channels,
    required this.channelsFirst,
  });

  final int width;
  final int height;
  final int channels;
  final bool channelsFirst;
}

class _LetterboxedImage {
  const _LetterboxedImage({required this.image, required this.transform});

  final img.Image image;
  final _LetterboxTransform transform;
}

class _LetterboxTransform {
  const _LetterboxTransform({
    required this.imageWidth,
    required this.imageHeight,
    required this.inputSize,
    required this.scale,
    required this.padLeft,
    required this.padTop,
  });

  final int imageWidth;
  final int imageHeight;
  final int inputSize;
  final double scale;
  final double padLeft;
  final double padTop;

  double inputXToImage(double x) => (x - padLeft) / scale;
  double inputYToImage(double y) => (y - padTop) / scale;
}

class _MaskPrototype {
  const _MaskPrototype({
    required this.values,
    required this.width,
    required this.height,
    required this.channels,
    required this.channelsFirst,
  });

  static const double _threshold = 0.5;

  final List<double> values;
  final int width;
  final int height;
  final int channels;
  final bool channelsFirst;

  List<List<Map<String, double>>> buildPolygons({
    required _BoundingBox box,
    required List<double> coefficients,
    required _LetterboxTransform transform,
  }) {
    if (values.isEmpty ||
        coefficients.isEmpty ||
        width <= 0 ||
        height <= 0 ||
        transform.imageWidth <= 0 ||
        transform.imageHeight <= 0) {
      return const [];
    }

    final coefficientCount = math.min(coefficients.length, channels);
    if (coefficientCount <= 0) return const [];

    final left = (box.inputLeft * width).floor().clamp(0, width - 1).toInt();
    final top = (box.inputTop * height).floor().clamp(0, height - 1).toInt();
    final right = (box.inputRight * width)
        .ceil()
        .clamp(left + 1, width)
        .toInt();
    final bottom = (box.inputBottom * height)
        .ceil()
        .clamp(top + 1, height)
        .toInt();

    final polygons = <List<Map<String, double>>>[];

    for (var y = top; y < bottom; y++) {
      int? spanStart;

      for (var x = left; x <= right; x++) {
        final inside =
            x < right &&
            _maskProbabilityAt(
                  x: x,
                  y: y,
                  coefficients: coefficients,
                  coefficientCount: coefficientCount,
                ) >=
                _threshold;

        if (inside && spanStart == null) {
          spanStart = x;
        } else if (!inside && spanStart != null) {
          final polygon = _spanPolygon(
            left: spanStart,
            top: y,
            right: x,
            bottom: y + 1,
            transform: transform,
          );
          if (polygon.isNotEmpty) polygons.add(polygon);
          spanStart = null;
        }
      }
    }

    if (polygons.isNotEmpty) return polygons;

    return [
      [
        {
          'x': box.left * transform.imageWidth,
          'y': box.top * transform.imageHeight,
        },
        {
          'x': box.right * transform.imageWidth,
          'y': box.top * transform.imageHeight,
        },
        {
          'x': box.right * transform.imageWidth,
          'y': box.bottom * transform.imageHeight,
        },
        {
          'x': box.left * transform.imageWidth,
          'y': box.bottom * transform.imageHeight,
        },
      ],
    ];
  }

  double _maskProbabilityAt({
    required int x,
    required int y,
    required List<double> coefficients,
    required int coefficientCount,
  }) {
    var logit = 0.0;
    for (var channel = 0; channel < coefficientCount; channel++) {
      logit += coefficients[channel] * _valueAt(channel: channel, x: x, y: y);
    }

    return 1 / (1 + math.exp(-logit));
  }

  double _valueAt({required int channel, required int x, required int y}) {
    final index = channelsFirst
        ? channel * width * height + y * width + x
        : (y * width + x) * channels + channel;

    if (index < 0 || index >= values.length) return 0;
    return values[index];
  }

  List<Map<String, double>> _spanPolygon({
    required int left,
    required int top,
    required int right,
    required int bottom,
    required _LetterboxTransform transform,
  }) {
    final inputX1 = left / width * transform.inputSize;
    final inputY1 = top / height * transform.inputSize;
    final inputX2 = right / width * transform.inputSize;
    final inputY2 = bottom / height * transform.inputSize;

    final x1 = transform
        .inputXToImage(inputX1)
        .clamp(0.0, transform.imageWidth.toDouble());
    final y1 = transform
        .inputYToImage(inputY1)
        .clamp(0.0, transform.imageHeight.toDouble());
    final x2 = transform
        .inputXToImage(inputX2)
        .clamp(0.0, transform.imageWidth.toDouble());
    final y2 = transform
        .inputYToImage(inputY2)
        .clamp(0.0, transform.imageHeight.toDouble());

    if (x2 <= x1 || y2 <= y1) return const [];

    return [
      {'x': x1, 'y': y1},
      {'x': x2, 'y': y1},
      {'x': x2, 'y': y2},
      {'x': x1, 'y': y2},
    ];
  }
}

class _DetectionCandidate {
  const _DetectionCandidate({
    required this.name,
    required this.classIndex,
    required this.confidence,
    required this.box,
    required this.maskCoefficients,
  });

  final String name;
  final int classIndex;
  final double confidence;
  final _BoundingBox box;
  final List<double> maskCoefficients;

  Map<String, dynamic> toMap({
    required int imageWidth,
    required int imageHeight,
    required _LetterboxTransform transform,
    required _MaskPrototype? maskPrototype,
  }) {
    final maskPolygons =
        maskPrototype?.buildPolygons(
          box: box,
          coefficients: maskCoefficients,
          transform: transform,
        ) ??
        const <List<Map<String, double>>>[];

    return {
      'name': name,
      'score': (confidence * 100).round(),
      'confidence': confidence,
      'classIndex': classIndex,
      'box': box.toNormalizedMap(),
      'rawBox': box.toInputScaledMap(
        width: TfliteService.inputSize,
        height: TfliteService.inputSize,
      ),
      'imageBox': box.toScaledMap(width: imageWidth, height: imageHeight),
      if (maskPolygons.isNotEmpty) 'maskPolygons': maskPolygons,
    };
  }
}

class _BoundingBox {
  const _BoundingBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.inputLeft,
    required this.inputTop,
    required this.inputRight,
    required this.inputBottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;
  final double inputLeft;
  final double inputTop;
  final double inputRight;
  final double inputBottom;

  double get width => math.max(0, right - left);
  double get height => math.max(0, bottom - top);
  double get area => width * height;
  bool get isValid => width > 0 && height > 0 && area.isFinite;

  factory _BoundingBox.fromCenter({
    required double xCenter,
    required double yCenter,
    required double width,
    required double height,
    required _LetterboxTransform transform,
  }) {
    final normalized =
        xCenter.abs() <= 2 &&
        yCenter.abs() <= 2 &&
        width.abs() <= 2 &&
        height.abs() <= 2;
    final inputScale = normalized ? TfliteService.inputSize.toDouble() : 1.0;

    final cx = xCenter * inputScale;
    final cy = yCenter * inputScale;
    final w = width.abs() * inputScale;
    final h = height.abs() * inputScale;

    final inputLeft = cx - w / 2;
    final inputTop = cy - h / 2;
    final inputRight = cx + w / 2;
    final inputBottom = cy + h / 2;

    final imageLeft = transform.inputXToImage(inputLeft);
    final imageTop = transform.inputYToImage(inputTop);
    final imageRight = transform.inputXToImage(inputRight);
    final imageBottom = transform.inputYToImage(inputBottom);

    return _BoundingBox(
      left: (imageLeft / transform.imageWidth).clamp(0.0, 1.0),
      top: (imageTop / transform.imageHeight).clamp(0.0, 1.0),
      right: (imageRight / transform.imageWidth).clamp(0.0, 1.0),
      bottom: (imageBottom / transform.imageHeight).clamp(0.0, 1.0),
      inputLeft: (inputLeft / transform.inputSize).clamp(0.0, 1.0),
      inputTop: (inputTop / transform.inputSize).clamp(0.0, 1.0),
      inputRight: (inputRight / transform.inputSize).clamp(0.0, 1.0),
      inputBottom: (inputBottom / transform.inputSize).clamp(0.0, 1.0),
    );
  }

  Map<String, double> toNormalizedMap() {
    return {
      'xMin': left,
      'yMin': top,
      'xMax': right,
      'yMax': bottom,
      'left': left,
      'top': top,
      'right': right,
      'bottom': bottom,
      'width': width,
      'height': height,
    };
  }

  Map<String, double> toScaledMap({required int width, required int height}) {
    return {
      'xMin': left * width,
      'yMin': top * height,
      'xMax': right * width,
      'yMax': bottom * height,
      'left': left * width,
      'top': top * height,
      'right': right * width,
      'bottom': bottom * height,
      'width': this.width * width,
      'height': this.height * height,
    };
  }

  Map<String, double> toInputScaledMap({
    required int width,
    required int height,
  }) {
    final inputWidth = math.max(0.0, inputRight - inputLeft);
    final inputHeight = math.max(0.0, inputBottom - inputTop);

    return {
      'xMin': inputLeft * width,
      'yMin': inputTop * height,
      'xMax': inputRight * width,
      'yMax': inputBottom * height,
      'left': inputLeft * width,
      'top': inputTop * height,
      'right': inputRight * width,
      'bottom': inputBottom * height,
      'width': inputWidth * width,
      'height': inputHeight * height,
    };
  }
}
