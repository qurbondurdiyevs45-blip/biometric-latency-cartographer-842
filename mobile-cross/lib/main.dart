import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:ui' as ui;

void main() {
  runApp(const LatencyCartographerApp());
}

class LatencyCartographerApp extends StatelessWidget {
  const LatencyCartographerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Biometric Latency Cartographer',
      theme: ThemeData.dark(useMaterial3: true),
      home: const LatencyTesterScreen(),
    );
  }
}

class LatencyTesterScreen extends StatefulWidget {
  const LatencyTesterScreen({super.key});

  @override
  State<LatencyTesterScreen> createState() => _LatencyTesterScreenState();
}

class _LatencyTesterScreenState extends State<LatencyTesterScreen> with SingleTickerProviderStateMixin {
  final List<double> _latencyHistory = [];
  Offset _pointerPosition = Offset.zero;
  Duration _lastFrameTimestamp = Duration.zero;
  double _currentDelta = 0.0;
  bool _isImpeller = false;

  @override
  void initState() {
    super.initState();
    _checkBackend();
    _createTicker();
  }

  void _checkBackend() {
    // Attempt to detect if Impeller is active via platform dispatcher flags
    final String renderer = ui.PlatformDispatcher.instance.views.first.platformDispatcher.toString();
    setState(() {
      _isImpeller = renderer.contains('Impeller');
    });
  }

  void _createTicker() {
    Ticker((Duration elapsed) {
      setState(() {
        _currentDelta = (elapsed - _lastFrameTimestamp).inMicroseconds / 1000.0;
        _lastFrameTimestamp = elapsed;
      });
    }).start();
  }

  void _handlePointerMove(PointerEvent event) {
    final double latency = (DateTime.now().millisecondsSinceEpoch - event.timeStamp.inMilliseconds).toDouble();
    setState(() {
      _pointerPosition = event.position;
      _latencyHistory.add(latency);
      if (_latencyHistory.length > 100) _latencyHistory.removeAt(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Listener(
        onPointerDown: _handlePointerMove,
        onPointerMove: _handlePointerMove,
        child: Stack(
          children: [
            CustomPaint(
              painter: LatencyPainter(_pointerPosition, _latencyHistory, _isImpeller),
              size: Size.infinite,
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('BIOMETRIC LATENCY CARTOGRAPHER', 
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2)),
                    Text('Backend: ${_isImpeller ? 'Impeller (Vulkan/Metal)' : 'Skia (OpenGL)'}',
                      style: TextStyle(color: _isImpeller ? Colors.greenAccent : Colors.orangeAccent)),
                    Text('Frame Delta: ${_currentDelta.toStringAsFixed(3)}ms'),
                    if (_latencyHistory.isNotEmpty)
                      Text('Input Latency: ${_latencyHistory.last.toStringAsFixed(2)}ms'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LatencyPainter extends CustomPainter {
  final Offset position;
  final List<double> history;
  final bool isImpeller;

  LatencyPainter(this.position, this.history, this.isImpeller);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint glowPaint = Paint()
      ..color = isImpeller ? Colors.cyan.withOpacity(0.5) : Colors.red.withOpacity(0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);

    final Paint corePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Draw Crosshair
    canvas.drawCircle(position, 40, glowPaint);
    canvas.drawCircle(position, 4, corePaint);
    canvas.drawLine(Offset(0, position.dy), Offset(size.width, position.dy), Paint()..color = Colors.white10);
    canvas.drawLine(Offset(position.dx, 0), Offset(position.dx, size.height), Paint()..color = Colors.white10);

    // Draw Latency Graph
    if (history.length > 2) {
      final Path path = Path();
      final double graphHeight = 100;
      final double startY = size.height - 50;
      final double stepX = size.width / 100;

      path.moveTo(0, startY - history[0]);
      for (int i = 1; i < history.length; i++) {
        path.lineTo(i * stepX, startY - (history[i] * 2));
      }

      canvas.drawPath(path, Paint()
        ..color = isImpeller ? Colors.cyanAccent : Colors.orangeAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(covariant LatencyPainter oldDelegate) => true;
}