import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class GraphDisplay extends StatelessWidget {
  final List<Offset> points;

  const GraphDisplay({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: GraphPainter(points: points),
      child: Container(),
    );
  }
}

class GraphPainter extends CustomPainter {
  final List<Offset> points;

  GraphPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.green.withAlpha(77)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    final axisPaint = Paint()
      ..color = Colors.green.withAlpha(153)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final plotPaint = Paint()
      ..color = Colors.limeAccent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(size.width, size.height),
        [Colors.limeAccent.withAlpha(230), Colors.green.withAlpha(230)],
      );

    // Draw grid
    const gridStep = 20.0;
    for (double i = gridStep; i < size.width; i += gridStep) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), gridPaint);
    }
    for (double i = gridStep; i < size.height; i += gridStep) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), gridPaint);
    }

    // Draw axes
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), axisPaint);
    canvas.drawLine(
      Offset(centerX, 0),
      Offset(centerX, size.height),
      axisPaint,
    );

    // Draw plot if points are available
    if (points.isNotEmpty) {
      final path = Path();
      final (minX, maxX, minY, maxY) = _getBounds(points);

      final rangeX = maxX - minX;
      final rangeY = maxY - minY;

      // Transform points to canvas coordinates
      final transformedPoints = points.map((p) {
        final double x = rangeX == 0
            ? size.width / 2
            : (p.dx - minX) / rangeX * size.width;
        final double y = rangeY == 0
            ? size.height / 2
            : size.height - ((p.dy - minY) / rangeY * size.height);
        return Offset(x, y);
      }).toList();

      path.moveTo(transformedPoints.first.dx, transformedPoints.first.dy);
      for (var i = 1; i < transformedPoints.length; i++) {
        path.lineTo(transformedPoints[i].dx, transformedPoints[i].dy);
      }

      canvas.drawPath(path, plotPaint);

      // Draw rulers
      _drawRuler(canvas, size, minX, maxX, true, axisPaint);
      _drawRuler(canvas, size, minY, maxY, false, axisPaint);
    }
  }

  void _drawRuler(
    Canvas canvas,
    Size size,
    double minVal,
    double maxVal,
    bool isXAxis,
    Paint axisPaint,
  ) {
    const tickCount = 5;
    final range = maxVal - minVal;
    if (range == 0) return;

    final textStyle = TextStyle(
      color: Colors.green.withAlpha(204),
      fontSize: 10,
    );

    for (int i = 0; i <= tickCount; i++) {
      final double value = minVal + (range * i / tickCount);
      final double normalizedValue = i / tickCount;

      final textPainter = TextPainter(
        text: TextSpan(text: value.toStringAsFixed(1), style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      if (isXAxis) {
        final x = normalizedValue * size.width;
        canvas.drawLine(
          Offset(x, size.height / 2 - 5),
          Offset(x, size.height / 2 + 5),
          axisPaint,
        );
        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2, size.height / 2 + 8),
        );
      } else {
        final y = size.height - (normalizedValue * size.height);
        canvas.drawLine(
          Offset(size.width / 2 - 5, y),
          Offset(size.width / 2 + 5, y),
          axisPaint,
        );
        textPainter.paint(
          canvas,
          Offset(size.width / 2 + 8, y - textPainter.height / 2),
        );
      }
    }
  }

  (double, double, double, double) _getBounds(List<Offset> points) {
    if (points.isEmpty) {
      return (0, 0, 0, 0);
    }
    double minX = points.first.dx;
    double maxX = points.first.dx;
    double minY = points.first.dy;
    double maxY = points.first.dy;

    for (final point in points) {
      if (point.dx < minX) minX = point.dx;
      if (point.dx > maxX) maxX = point.dx;
      if (point.dy < minY) minY = point.dy;
      if (point.dy > maxY) maxY = point.dy;
    }
    return (minX, maxX, minY, maxY);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
