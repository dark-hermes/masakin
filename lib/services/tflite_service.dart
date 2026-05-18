import 'dart:io';
import 'dart:math' as math;

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
  });

  static const int inputSize = 640;

  final String modelPath;
  final String labelsPath;
  final double confidenceThreshold;
  final double iouThreshold;
  final int maxResults;

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
      throw StateError('Unsupported model input shape: $inputShape');
    }

    final isNchw = inputShape[1] == 3;
    final resizedImage = img.copyResize(
      decodedImage,
      width: inputSize,
      height: inputSize,
      interpolation: img.Interpolation.linear,
    );
    final input = _buildInputTensor(
      image: resizedImage,
      inputType: inputTensor.type,
      isNchw: isNchw,
    );

    final outputTensors = interpreter.getOutputTensors();
    if (outputTensors.isEmpty) {
      throw StateError('Model has no output tensors.');
    }

    final outputs = <int, Object>{};
    for (var i = 0; i < outputTensors.length; i++) {
      outputs[i] = _createTensorBuffer(
        outputTensors[i].shape,
        outputTensors[i].type,
      );
    }

    interpreter.runForMultipleInputs([input], outputs);

    final candidates = _parseOutputs(outputs, outputTensors)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final selected = _nonMaxSuppression(candidates).take(maxResults);

    return selected
        .map(
          (detection) => detection.toMap(
            imageWidth: decodedImage.width,
            imageHeight: decodedImage.height,
          ),
        )
        .toList(growable: false);
  }

  Object _buildInputTensor({
    required img.Image image,
    required TensorType inputType,
    required bool isNchw,
  }) {
    num normalize(num value) {
      if (inputType == TensorType.float32) return value / 255.0;
      return value.round().clamp(0, 255);
    }

    if (isNchw) {
      return [
        List.generate(
          3,
          (channel) => List.generate(
            inputSize,
            (y) => List.generate(inputSize, (x) {
              final pixel = image.getPixel(x, y);
              return switch (channel) {
                0 => normalize(pixel.r),
                1 => normalize(pixel.g),
                _ => normalize(pixel.b),
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
          return [normalize(pixel.r), normalize(pixel.g), normalize(pixel.b)];
        }),
      ),
    ];
  }

  Object _createTensorBuffer(List<int> shape, TensorType type) {
    final zero = type == TensorType.float32 ? 0.0 : 0;
    final safeShape = shape.map((dimension) => math.max(dimension, 1)).toList();

    Object build(int depth) {
      if (depth == safeShape.length) return zero;
      return List.generate(safeShape[depth], (_) => build(depth + 1));
    }

    return build(0);
  }

  List<_DetectionCandidate> _parseOutputs(
    Map<int, Object> outputs,
    List<Tensor> outputTensors,
  ) {
    if (outputs.length == 1) {
      return _parseYoloRows(
        _rowsFromSingleOutput(outputs[0]!, outputTensors[0].shape),
      );
    }

    return _parseMultiOutputFallback(outputs, outputTensors);
  }

  List<List<double>> _rowsFromSingleOutput(Object output, List<int> shape) {
    final flat = _flatten(output);
    if (flat.isEmpty) return const [];

    if (shape.length == 3) {
      final dim1 = shape[1];
      final dim2 = shape[2];
      if (_looksChannelsFirst(channels: dim1, anchors: dim2)) {
        return List.generate(
          dim2,
          (anchor) => List.generate(dim1, (channel) {
            return flat[channel * dim2 + anchor];
          }),
          growable: false,
        );
      }

      return List.generate(
        dim1,
        (row) => flat.sublist(row * dim2, (row + 1) * dim2),
        growable: false,
      );
    }

    if (shape.length == 2) {
      final dim1 = shape[0];
      final dim2 = shape[1];
      if (_looksChannelsFirst(channels: dim1, anchors: dim2)) {
        return List.generate(
          dim2,
          (anchor) => List.generate(dim1, (channel) {
            return flat[channel * dim2 + anchor];
          }),
          growable: false,
        );
      }

      return List.generate(
        dim1,
        (row) => flat.sublist(row * dim2, (row + 1) * dim2),
        growable: false,
      );
    }

    if (shape.length == 4 && shape.last >= 6) {
      final rows = shape[1] * shape[2];
      final columns = shape[3];
      return List.generate(
        rows,
        (row) => flat.sublist(row * columns, (row + 1) * columns),
        growable: false,
      );
    }

    throw StateError('Unsupported YOLO output shape: $shape');
  }

  bool _looksChannelsFirst({required int channels, required int anchors}) {
    final expectedMaxChannels = math.max(6, _labels.length + 5);
    return channels <= expectedMaxChannels && anchors > channels;
  }

  List<_DetectionCandidate> _parseYoloRows(List<List<double>> rows) {
    final detections = <_DetectionCandidate>[];

    for (final row in rows) {
      if (row.length < 6) continue;

      final detection = _parseYoloRow(row);
      if (detection == null) continue;
      if (detection.confidence < confidenceThreshold) continue;

      detections.add(detection);
    }

    return detections;
  }

  _DetectionCandidate? _parseYoloRow(List<double> row) {
    late final int classIndex;
    late final double confidence;

    if (_labels.isNotEmpty && row.length == _labels.length + 4) {
      final best = _bestClass(row, 4);
      classIndex = best.index;
      confidence = _probability(best.score);
    } else if (_labels.isNotEmpty && row.length >= _labels.length + 5) {
      final objectness = _probability(row[4]);
      final best = _bestClass(row, 5);
      classIndex = best.index;
      confidence = objectness * _probability(best.score);
    } else if (row.length == 6) {
      classIndex = row[5].round();
      confidence = _probability(row[4]);
    } else {
      final objectness = _probability(row[4]);
      final best = _bestClass(row, 5);
      classIndex = best.index;
      confidence = objectness * _probability(best.score);
    }

    final box = _Box.fromYoloRow(row);
    if (box.width <= 0 || box.height <= 0) return null;

    return _DetectionCandidate(
      name: _labelFor(classIndex),
      classIndex: classIndex,
      confidence: confidence.clamp(0.0, 1.0),
      box: box,
    );
  }

  List<_DetectionCandidate> _parseMultiOutputFallback(
    Map<int, Object> outputs,
    List<Tensor> outputTensors,
  ) {
    final boxesIndex = outputTensors.indexWhere(
      (tensor) => tensor.shape.isNotEmpty && tensor.shape.last == 4,
    );
    final classesIndex = _findOutputTensor(outputTensors, ['class']);
    final scoresIndex = _findOutputTensor(outputTensors, [
      'score',
      'confidence',
    ]);

    if (boxesIndex < 0 || classesIndex < 0 || scoresIndex < 0) {
      return const [];
    }

    final boxes = _flatten(outputs[boxesIndex]);
    final classes = _flatten(outputs[classesIndex]);
    final scores = _flatten(outputs[scoresIndex]);
    final count = math.min(scores.length, boxes.length ~/ 4);
    final detections = <_DetectionCandidate>[];

    for (var i = 0; i < count; i++) {
      final confidence = _probability(scores[i]);
      if (confidence < confidenceThreshold) continue;

      final yMin = boxes[i * 4];
      final xMin = boxes[i * 4 + 1];
      final yMax = boxes[i * 4 + 2];
      final xMax = boxes[i * 4 + 3];
      final classIndex = classes[i].round();

      detections.add(
        _DetectionCandidate(
          name: _labelFor(classIndex),
          classIndex: classIndex,
          confidence: confidence,
          box: _Box.fromCorners(
            left: xMin,
            top: yMin,
            right: xMax,
            bottom: yMax,
          ),
        ),
      );
    }

    return detections;
  }

  ({int index, double score}) _bestClass(List<double> row, int startIndex) {
    var index = 0;
    var score = double.negativeInfinity;

    for (var i = startIndex; i < row.length; i++) {
      if (row[i] > score) {
        index = i - startIndex;
        score = row[i];
      }
    }

    return (index: index, score: score);
  }

  List<_DetectionCandidate> _nonMaxSuppression(
    List<_DetectionCandidate> detections,
  ) {
    final selected = <_DetectionCandidate>[];

    for (final detection in detections) {
      final shouldSuppress = selected.any((current) {
        return current.classIndex == detection.classIndex &&
            _iou(current.box, detection.box) > iouThreshold;
      });
      if (!shouldSuppress) selected.add(detection);
    }

    return selected;
  }

  double _iou(_Box a, _Box b) {
    final left = math.max(a.left, b.left);
    final top = math.max(a.top, b.top);
    final right = math.min(a.right, b.right);
    final bottom = math.min(a.bottom, b.bottom);
    final intersection =
        math.max(0.0, right - left) * math.max(0.0, bottom - top);
    final union = a.width * a.height + b.width * b.height - intersection;
    return union <= 0 ? 0 : intersection / union;
  }

  int _findOutputTensor(List<Tensor> tensors, List<String> names) {
    return tensors.indexWhere((tensor) {
      final name = tensor.name.toLowerCase();
      return names.any(name.contains);
    });
  }

  double _probability(double value) {
    if (value >= 0 && value <= 1) return value;
    return 1 / (1 + math.exp(-value));
  }

  List<double> _flatten(Object? value) {
    final result = <double>[];

    void visit(Object? node) {
      if (node is num) {
        result.add(node.toDouble());
        return;
      }
      if (node is Iterable) {
        for (final child in node) {
          visit(child);
        }
      }
    }

    visit(value);
    return result;
  }

  String _labelFor(int index) {
    if (index >= 0 && index < _labels.length) return _labels[index];
    if (index > 0 && index - 1 < _labels.length) return _labels[index - 1];
    return 'Class $index';
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}

class _DetectionCandidate {
  const _DetectionCandidate({
    required this.name,
    required this.classIndex,
    required this.confidence,
    required this.box,
  });

  final String name;
  final int classIndex;
  final double confidence;
  final _Box box;

  Map<String, dynamic> toMap({
    required int imageWidth,
    required int imageHeight,
  }) {
    return {
      'name': name,
      'score': (confidence * 100).round(),
      'confidence': confidence,
      'classIndex': classIndex,
      'box': box.toNormalizedMap(),
      'rawBox': box.toScaledMap(
        width: TfliteService.inputSize,
        height: TfliteService.inputSize,
      ),
      'imageBox': box.toScaledMap(width: imageWidth, height: imageHeight),
    };
  }
}

class _Box {
  const _Box({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => math.max(0, right - left);
  double get height => math.max(0, bottom - top);

  factory _Box.fromYoloRow(List<double> row) {
    final centerX = row[0];
    final centerY = row[1];
    final width = row[2].abs();
    final height = row[3].abs();
    final normalized =
        centerX <= 1.5 && centerY <= 1.5 && width <= 1.5 && height <= 1.5;

    final scale = normalized ? 1.0 : TfliteService.inputSize.toDouble();
    final x = centerX / scale;
    final y = centerY / scale;
    final w = width / scale;
    final h = height / scale;

    return _Box.fromCorners(
      left: x - w / 2,
      top: y - h / 2,
      right: x + w / 2,
      bottom: y + h / 2,
    );
  }

  factory _Box.fromCorners({
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) {
    final normalized =
        left <= 1.5 && top <= 1.5 && right <= 1.5 && bottom <= 1.5;
    final scale = normalized ? 1.0 : TfliteService.inputSize.toDouble();

    return _Box(
      left: (left / scale).clamp(0.0, 1.0),
      top: (top / scale).clamp(0.0, 1.0),
      right: (right / scale).clamp(0.0, 1.0),
      bottom: (bottom / scale).clamp(0.0, 1.0),
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
}
