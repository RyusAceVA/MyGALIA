import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Indicateur de progression linéaire « en vague » de Material 3
/// Expressive : la partie accomplie ondule, le reste de la piste est
/// plat, séparé par un petit espace et terminé par un point d'arrêt.
///
/// Sans [value] : deux segments ondulés parcourent la piste en boucle.
/// Avec [value] : la vague s'aplatit au tout début et à la fin (en
/// dessous de 10 % et à partir de 95 %), comme le prévoit Material.
class WavyLinearProgressIndicator extends StatefulWidget {
  const WavyLinearProgressIndicator({
    super.key,
    this.value,
    this.color,
    this.trackColor,
    this.semanticsLabel,
  });

  final double? value;

  /// Couleur de la vague et du point d'arrêt (par défaut : primaire).
  final Color? color;

  /// Couleur de la piste (par défaut : conteneur secondaire).
  final Color? trackColor;

  final String? semanticsLabel;

  /// Hauteur : épaisseur du trait plus deux amplitudes.
  static const double height = _WavyPainter.thickness + 2 * _WavyPainter.amplitude;

  @override
  State<WavyLinearProgressIndicator> createState() => _WavyLinearProgressIndicatorState();
}

class _WavyLinearProgressIndicatorState extends State<WavyLinearProgressIndicator>
    with SingleTickerProviderStateMixin {
  static const Duration _amplitudeRamp = Duration(milliseconds: 500);

  late final Ticker _ticker;
  final _WaveFrame _frame = _WaveFrame();
  bool _reduceMotion = false;

  // Rampe d'amplitude (la vague apparaît ou s'aplatit en douceur).
  late double _ampFrom = _targetAmplitude;
  late double _ampTo = _ampFrom;
  Duration _ampChangedAt = Duration.zero;

  double get _targetAmplitude {
    final double? value = widget.value;
    if (value == null) return 1;
    return value <= 0.1 || value >= 0.95 ? 0 : 1;
  }

  double _amplitudeAt(Duration elapsed) {
    final double k = ((elapsed - _ampChangedAt).inMicroseconds / _amplitudeRamp.inMicroseconds)
        .clamp(0, 1)
        .toDouble();
    return _ampFrom + (_ampTo - _ampFrom) * Curves.easeInOut.transform(k);
  }

  /// Images nécessaires : animation continue, vague qui défile, ou rampe
  /// d'amplitude pas encore terminée.
  bool get _needsFrames {
    final double amplitude = _amplitudeAt(_frame.elapsed);
    return widget.value == null || amplitude != _ampTo || (!_reduceMotion && amplitude > 0);
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _frame.amplitude = _amplitudeAt(_frame.elapsed);
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant WavyLinearProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    final double target = _targetAmplitude;
    if (target != _ampTo) {
      _ampFrom = _amplitudeAt(_frame.elapsed);
      _ampTo = target;
      _ampChangedAt = _frame.elapsed;
      if (_reduceMotion) _ampFrom = target;
    }
    _frame.amplitude = _amplitudeAt(_frame.elapsed);
    _syncTicker();
  }

  void _syncTicker() {
    if (_needsFrames) {
      if (_ticker.isActive) return;
      // Le temps du ticker repart de zéro : on recale le début de la rampe.
      _ampChangedAt -= _frame.elapsed;
      _frame.elapsed = Duration.zero;
      _ticker.start();
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    _frame.update(elapsed, _amplitudeAt(elapsed));
    if (!_needsFrames) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double? value = widget.value;
    return Semantics(
      label: widget.semanticsLabel,
      value: value == null ? null : '${(value.clamp(0, 1) * 100).round()} %',
      child: RepaintBoundary(
        child: SizedBox(
          width: double.infinity,
          height: WavyLinearProgressIndicator.height,
          child: CustomPaint(
            painter: _WavyPainter(
              frame: _frame,
              value: value,
              color: widget.color ?? scheme.primary,
              trackColor: widget.trackColor ?? scheme.secondaryContainer,
              waveMoves: !_reduceMotion,
            ),
          ),
        ),
      ),
    );
  }
}

/// Temps écoulé et amplitude courante, lus par le peintre à chaque image.
class _WaveFrame extends ChangeNotifier {
  Duration elapsed = Duration.zero;
  double amplitude = 0;

  void update(Duration newElapsed, double newAmplitude) {
    elapsed = newElapsed;
    amplitude = newAmplitude;
    notifyListeners();
  }
}

class _WavyPainter extends CustomPainter {
  _WavyPainter({
    required this.frame,
    required this.value,
    required this.color,
    required this.trackColor,
    required this.waveMoves,
  }) : super(repaint: frame);

  // Mesures Material 3 Expressive (dp).
  static const double thickness = 4;
  static const double amplitude = 3;
  static const double _gap = 4;
  static const double _stopRadius = 2;
  static const double _determinateWavelength = 40;
  static const double _indeterminateWavelength = 20;

  /// Défilement de la vague : une longueur d'onde par période (s).
  static const double _determinatePeriod = 1.5;
  static const double _indeterminatePeriod = 1;

  /// Cycle des deux segments de l'animation continue (ms).
  static const double _cycleMs = 1800;
  static const Curve _line1Head = Interval(0, 750 / _cycleMs, curve: Cubic(0.2, 0, 0.8, 1));
  static const Curve _line1Tail =
      Interval(333 / _cycleMs, (333 + 750) / _cycleMs, curve: Cubic(0.4, 0, 1, 1));
  static const Curve _line2Head =
      Interval(1000 / _cycleMs, (1000 + 567) / _cycleMs, curve: Cubic(0, 0, 0.65, 1));
  static const Curve _line2Tail =
      Interval(1267 / _cycleMs, (1267 + 533) / _cycleMs, curve: Cubic(0.1, 0, 0.45, 1));

  final _WaveFrame frame;
  final double? value;
  final Color color;
  final Color trackColor;
  final bool waveMoves;

  @override
  void paint(Canvas canvas, Size size) {
    final double cy = size.height / 2;
    const double cap = thickness / 2;
    const double start = cap;
    final double end = math.max(start, size.width - cap);
    final Paint active = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Paint track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;
    final double seconds = frame.elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final double? progress = value;

    // Segments actifs (abscisses des centres des extrémités arrondies).
    final List<(double, double)> segments;
    final double wavelength;
    final double phase;
    if (progress == null) {
      final double t = (seconds * 1000 % _cycleMs) / _cycleMs;
      double x(double f) => start + (end - start) * f;
      segments = [
        (x(_line1Tail.transform(t)), x(_line1Head.transform(t))),
        (x(_line2Tail.transform(t)), x(_line2Head.transform(t))),
      ].where(((double, double) s) => s.$2 - s.$1 > 0.5).toList();
      wavelength = _indeterminateWavelength;
      phase = seconds / _indeterminatePeriod;
    } else {
      final double v = progress.clamp(0, 1).toDouble();
      segments = v > 0 ? [(start, start + (end - start) * v)] : const [];
      wavelength = _determinateWavelength;
      phase = waveMoves ? seconds / _determinatePeriod : 0;
    }

    // Piste : ce qui reste, à distance des segments actifs.
    const double clearance = thickness + _gap;
    double trackFrom = start;
    for (final (double a, double b) in segments) {
      if (a - clearance > trackFrom) {
        canvas.drawLine(Offset(trackFrom, cy), Offset(a - clearance, cy), track);
      }
      trackFrom = math.max(trackFrom, b + clearance);
    }
    final bool trackReachesEnd = trackFrom < end;
    if (trackReachesEnd) {
      canvas.drawLine(Offset(trackFrom, cy), Offset(end, cy), track);
    }
    // Point d'arrêt au bout de la piste (progression déterminée).
    if (progress != null && trackReachesEnd) {
      canvas.drawCircle(Offset(end, cy), _stopRadius, Paint()..color = color);
    }

    final double a = amplitude * frame.amplitude;
    for (final (double x0, double x1) in segments) {
      final Path wave = Path();
      double y(double x) => cy + a * math.sin(2 * math.pi * (x / wavelength - phase));
      wave.moveTo(x0, y(x0));
      for (double x = x0; x < x1;) {
        x = math.min(x + 1.5, x1);
        wave.lineTo(x, y(x));
      }
      if (x1 - x0 < 0.5) {
        canvas.drawCircle(Offset(x0, y(x0)), cap, Paint()..color = color);
      } else {
        canvas.drawPath(wave, active);
      }
    }
  }

  @override
  bool shouldRepaint(_WavyPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.waveMoves != waveMoves ||
      !identical(oldDelegate.frame, frame);
}
