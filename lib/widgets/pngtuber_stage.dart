import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../pngtuber/pngtuber_controller.dart';
import '../pngtuber/pngtuber_math.dart';

class PNGTuberStage extends StatelessWidget {
  const PNGTuberStage({super.key, required this.controller});

  final PNGTuberController controller;

  @override
  Widget build(BuildContext context) {
    final video = controller.video!;
    final track = controller.track!;
    return ColoredBox(
      color: Colors.black,
      child: AspectRatio(
        aspectRatio: track.width / track.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoPlayer(video),
            IgnorePointer(
              child: CustomPaint(
                painter: MouthSpritePainter(controller: controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MouthSpritePainter extends CustomPainter {
  MouthSpritePainter({required this.controller})
    : super(repaint: controller.renderSignal);

  final PNGTuberController controller;

  @override
  void paint(Canvas canvas, Size size) {
    final track = controller.track!;
    final frame = track.frameAt(controller.renderPosition);
    if (!frame.valid) return;

    final quad = applyCalibration(
      frame.quad,
      enabled: track.calibrationApplied,
      offset: track.calibration.offset,
      scale: track.calibration.scale,
      rotationDegrees: track.calibration.rotation,
    );
    canvas.save();
    canvas.scale(size.width / track.width, size.height / track.height);
    final current = controller.sprites[controller.mouthState]!;
    final previous =
        controller.sprites[controller.previousMouthState] ?? current;
    final blend = controller.mouthBlend;
    if (blend < 1 && previous != current) {
      _drawSprite(canvas, previous, quad, 1 - blend);
    }
    _drawSprite(canvas, current, quad, blend);
    canvas.restore();
  }

  void _drawSprite(
    Canvas canvas,
    ui.Image sprite,
    List<Offset> quad,
    double opacity,
  ) {
    final source = <Offset>[
      Offset.zero,
      Offset(sprite.width.toDouble(), 0),
      Offset(sprite.width.toDouble(), sprite.height.toDouble()),
      Offset(0, sprite.height.toDouble()),
    ];
    _drawTriangle(
      canvas,
      sprite,
      opacity,
      source[0],
      source[1],
      source[2],
      quad[0],
      quad[1],
      quad[2],
    );
    _drawTriangle(
      canvas,
      sprite,
      opacity,
      source[0],
      source[2],
      source[3],
      quad[0],
      quad[2],
      quad[3],
    );
  }

  void _drawTriangle(
    Canvas canvas,
    ui.Image sprite,
    double opacity,
    Offset s0,
    Offset s1,
    Offset s2,
    Offset d0,
    Offset d1,
    Offset d2,
  ) {
    final transform = computeAffine(s0, s1, s2, d0, d1, d2);
    if (transform == null) return;
    canvas.save();
    canvas.clipPath(
      Path()
        ..moveTo(d0.dx, d0.dy)
        ..lineTo(d1.dx, d1.dy)
        ..lineTo(d2.dx, d2.dy)
        ..close(),
      doAntiAlias: true,
    );
    canvas.transform(
      Float64List.fromList(<double>[
        transform.a,
        transform.b,
        0,
        0,
        transform.c,
        transform.d,
        0,
        0,
        0,
        0,
        1,
        0,
        transform.e,
        transform.f,
        0,
        1,
      ]),
    );
    canvas.drawImage(
      sprite,
      Offset.zero,
      Paint()
        ..filterQuality = FilterQuality.high
        ..color = ui.Color.fromRGBO(255, 255, 255, opacity),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MouthSpritePainter oldDelegate) {
    return oldDelegate.controller != controller;
  }
}
