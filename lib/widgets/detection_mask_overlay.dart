import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/tflite_service.dart';

class DetectionMaskOverlay extends StatelessWidget {
  const DetectionMaskOverlay({
    super.key,
    required this.detections,
    required this.imageSize,
    required this.fit,
    this.showLabels = true,
  });

  final List<Map<String, dynamic>> detections;
  final Size imageSize;
  final BoxFit fit;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        final transform = _ImageOverlayTransform.fromSizes(
          canvasSize: canvasSize,
          imageSize: imageSize,
          fit: fit,
        );

        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _DetectionMaskPainter(
                    detections: detections,
                    imageSize: imageSize,
                    transform: transform,
                  ),
                ),
              ),
            ),
            if (showLabels)
              for (final detection in detections)
                if (_DetectionBounds.tryParse(
                      detection: detection,
                      imageSize: imageSize,
                    )
                    case final bounds?)
                  _DetectionLabel(
                    detection: detection,
                    bounds: bounds,
                    transform: transform,
                    canvasSize: canvasSize,
                  ),
          ],
        );
      },
    );
  }
}

class _DetectionMaskPainter extends CustomPainter {
  const _DetectionMaskPainter({
    required this.detections,
    required this.imageSize,
    required this.transform,
  });

  final List<Map<String, dynamic>> detections;
  final Size imageSize;
  final _ImageOverlayTransform transform;

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF22C55E).withValues(alpha: 0.24);

    for (final detection in detections) {
      final path = _pathForDetection(detection);
      if (path == null) continue;

      canvas.drawPath(path, fillPaint);
    }
  }

  Path? _pathForDetection(Map<String, dynamic> detection) {
    final mask = _DetectionMask.tryParse(detection);
    if (mask != null && mask.polygons.isNotEmpty) {
      final path = Path();
      for (final polygon in mask.polygons) {
        if (polygon.length < 3) continue;

        final first = transform.toScreenPoint(polygon.first);
        path.moveTo(first.dx, first.dy);
        for (final point in polygon.skip(1)) {
          final screenPoint = transform.toScreenPoint(point);
          path.lineTo(screenPoint.dx, screenPoint.dy);
        }
        path.close();
      }
      return path;
    }

    final bounds = _DetectionBounds.tryParse(
      detection: detection,
      imageSize: imageSize,
    );
    if (bounds == null) return null;

    final rect = transform.toScreenRect(bounds.rect);
    if (rect.width <= 0 || rect.height <= 0) return null;

    return Path()..addPolygon([
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ], true);
  }

  @override
  bool shouldRepaint(covariant _DetectionMaskPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.transform != transform;
  }
}

class _DetectionLabel extends StatelessWidget {
  const _DetectionLabel({
    required this.detection,
    required this.bounds,
    required this.transform,
    required this.canvasSize,
  });

  final Map<String, dynamic> detection;
  final _DetectionBounds bounds;
  final _ImageOverlayTransform transform;
  final Size canvasSize;

  @override
  Widget build(BuildContext context) {
    final label = _labelFor(detection);
    if (label.isEmpty) return const SizedBox.shrink();

    final rect = transform.toScreenRect(bounds.rect);
    if (rect.width <= 0 || rect.height <= 0) return const SizedBox.shrink();

    final labelTop = math.max(transform.imageRect.top + 4, rect.top - 30);
    final labelLeft = rect.left
        .clamp(8.0, math.max(8.0, canvasSize.width - 128))
        .toDouble();
    final maxLabelWidth = math.max(72.0, canvasSize.width - labelLeft - 8);

    return Positioned(
      left: labelLeft,
      top: labelTop,
      child: IgnorePointer(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxLabelWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E),
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _labelFor(Map<String, dynamic> detection) {
    final name = detection['name']?.toString().trim();
    final confidence = _confidenceText(
      detection['confidence'] ?? detection['score'],
    );
    if (name == null || name.isEmpty) return confidence;
    if (confidence.isEmpty) return name;
    return '$name $confidence';
  }

  String _confidenceText(Object? value) {
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

class _ImageOverlayTransform {
  const _ImageOverlayTransform({
    required this.scale,
    required this.offsetX,
    required this.offsetY,
    required this.imageRect,
  });

  final double scale;
  final double offsetX;
  final double offsetY;
  final Rect imageRect;

  factory _ImageOverlayTransform.fromSizes({
    required Size canvasSize,
    required Size imageSize,
    required BoxFit fit,
  }) {
    if (canvasSize.width <= 0 ||
        canvasSize.height <= 0 ||
        imageSize.width <= 0 ||
        imageSize.height <= 0) {
      return const _ImageOverlayTransform(
        scale: 0,
        offsetX: 0,
        offsetY: 0,
        imageRect: Rect.zero,
      );
    }

    final scale = fit == BoxFit.cover
        ? math.max(
            canvasSize.width / imageSize.width,
            canvasSize.height / imageSize.height,
          )
        : math.min(
            canvasSize.width / imageSize.width,
            canvasSize.height / imageSize.height,
          );
    final renderedWidth = imageSize.width * scale;
    final renderedHeight = imageSize.height * scale;
    final offsetX = (canvasSize.width - renderedWidth) / 2;
    final offsetY = (canvasSize.height - renderedHeight) / 2;

    return _ImageOverlayTransform(
      scale: scale,
      offsetX: offsetX,
      offsetY: offsetY,
      imageRect: Rect.fromLTWH(offsetX, offsetY, renderedWidth, renderedHeight),
    );
  }

  Offset toScreenPoint(Offset imagePoint) {
    return Offset(
      offsetX + imagePoint.dx * scale,
      offsetY + imagePoint.dy * scale,
    );
  }

  Rect toScreenRect(Rect imageRect) {
    return Rect.fromLTWH(
      offsetX + imageRect.left * scale,
      offsetY + imageRect.top * scale,
      imageRect.width * scale,
      imageRect.height * scale,
    );
  }
}

class _DetectionMask {
  const _DetectionMask({required this.polygons});

  final List<List<Offset>> polygons;

  static _DetectionMask? tryParse(Map<String, dynamic> detection) {
    final rawPolygons = detection['maskPolygons'];
    if (rawPolygons is! Iterable) return null;

    final polygons = <List<Offset>>[];
    for (final rawPolygon in rawPolygons) {
      if (rawPolygon is! Iterable) continue;

      final points = <Offset>[];
      for (final rawPoint in rawPolygon) {
        final point = _pointFrom(rawPoint);
        if (point != null) points.add(point);
      }

      if (points.length >= 3) polygons.add(points);
    }

    if (polygons.isEmpty) return null;
    return _DetectionMask(polygons: polygons);
  }

  static Offset? _pointFrom(Object? value) {
    if (value is Map) {
      final x = _asDouble(value['x']);
      final y = _asDouble(value['y']);
      if (x == null || y == null) return null;
      return Offset(x, y);
    }

    if (value is List && value.length >= 2) {
      final x = _asDouble(value[0]);
      final y = _asDouble(value[1]);
      if (x == null || y == null) return null;
      return Offset(x, y);
    }

    return null;
  }
}

class _DetectionBounds {
  const _DetectionBounds(this.rect);

  final Rect rect;

  static _DetectionBounds? tryParse({
    required Map<String, dynamic> detection,
    required Size imageSize,
  }) {
    final mask = _DetectionMask.tryParse(detection);
    if (mask != null) {
      final bounds = _boundsFromPolygons(mask.polygons);
      if (bounds != null) return _DetectionBounds(bounds);
    }

    final imageBox = _mapFrom(detection['imageBox']);
    final normalizedBox = _mapFrom(detection['box']);
    final rawBox = _mapFrom(detection['rawBox']);

    final fromImage = _fromMap(imageBox);
    if (fromImage != null) {
      return _DetectionBounds(
        fromImage._toImagePixelRect(
          sourceWidth: imageSize.width,
          sourceHeight: imageSize.height,
          targetWidth: imageSize.width,
          targetHeight: imageSize.height,
        ),
      );
    }

    final fromNormalized = _fromMap(normalizedBox);
    if (fromNormalized != null) {
      return _DetectionBounds(
        fromNormalized._toImagePixelRect(
          sourceWidth: 1,
          sourceHeight: 1,
          targetWidth: imageSize.width,
          targetHeight: imageSize.height,
        ),
      );
    }

    final fromRaw = _fromMap(rawBox);
    if (fromRaw != null) {
      return _DetectionBounds(
        fromRaw._toImagePixelRect(
          sourceWidth: TfliteService.inputSize.toDouble(),
          sourceHeight: TfliteService.inputSize.toDouble(),
          targetWidth: imageSize.width,
          targetHeight: imageSize.height,
        ),
      );
    }

    return null;
  }

  static Rect? _boundsFromPolygons(List<List<Offset>> polygons) {
    double? left;
    double? top;
    double? right;
    double? bottom;

    for (final polygon in polygons) {
      for (final point in polygon) {
        left = left == null ? point.dx : math.min(left, point.dx);
        top = top == null ? point.dy : math.min(top, point.dy);
        right = right == null ? point.dx : math.max(right, point.dx);
        bottom = bottom == null ? point.dy : math.max(bottom, point.dy);
      }
    }

    if (left == null || top == null || right == null || bottom == null) {
      return null;
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }

  static Map<String, dynamic>? _mapFrom(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  static _RawDetectionBox? _fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;

    final left = _readDouble(map, const ['left', 'xMin', 'xmin', 'x1']);
    final top = _readDouble(map, const ['top', 'yMin', 'ymin', 'y1']);
    final right = _readDouble(map, const ['right', 'xMax', 'xmax', 'x2']);
    final bottom = _readDouble(map, const ['bottom', 'yMax', 'ymax', 'y2']);
    final width = _readDouble(map, const ['width', 'w']);
    final height = _readDouble(map, const ['height', 'h']);

    if (left == null || top == null) return null;

    final resolvedRight = right ?? (width == null ? null : left + width);
    final resolvedBottom = bottom ?? (height == null ? null : top + height);
    if (resolvedRight == null || resolvedBottom == null) return null;

    return _RawDetectionBox(
      left: left,
      top: top,
      right: resolvedRight,
      bottom: resolvedBottom,
    );
  }

  static double? _readDouble(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      final parsed = _asDouble(value);
      if (parsed != null) return parsed;
    }
    return null;
  }
}

class _RawDetectionBox {
  const _RawDetectionBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  Rect _toImagePixelRect({
    required double sourceWidth,
    required double sourceHeight,
    required double targetWidth,
    required double targetHeight,
  }) {
    final safeSourceWidth = math.max(sourceWidth, 1);
    final safeSourceHeight = math.max(sourceHeight, 1);
    final normalizedLeft = (left / safeSourceWidth).clamp(0.0, 1.0);
    final normalizedTop = (top / safeSourceHeight).clamp(0.0, 1.0);
    final normalizedRight = (right / safeSourceWidth).clamp(0.0, 1.0);
    final normalizedBottom = (bottom / safeSourceHeight).clamp(0.0, 1.0);

    return Rect.fromLTRB(
      normalizedLeft * targetWidth,
      normalizedTop * targetHeight,
      normalizedRight * targetWidth,
      normalizedBottom * targetHeight,
    );
  }
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}
