import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_gamepads/just_gamepads.dart';

void main() => runApp(const GamepadTesterApp());

/// Lists every connected controller with its live buttons and axes.
///
/// Also a hardware checklist: press each button and push each stick, and the
/// matching cell lights up in the standard layout.
class GamepadTesterApp extends StatelessWidget {
  const GamepadTesterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'just_gamepads tester',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const GamepadTesterPage(),
    );
  }
}

class GamepadTesterPage extends StatefulWidget {
  const GamepadTesterPage({super.key});

  @override
  State<GamepadTesterPage> createState() => _GamepadTesterPageState();
}

class _GamepadTesterPageState extends State<GamepadTesterPage> {
  final _manager = GamepadManager.instance;
  final _subscriptions = <StreamSubscription<Object>>[];

  @override
  void initState() {
    super.initState();
    _subscriptions
      ..add(
        _manager.connections.listen((event) {
          // Printed so the example doubles as a log-based smoke test.
          debugPrint('just_gamepads: $event');
          setState(() {});
        }),
      )
      ..add(_manager.stateChanges.listen((_) => setState(() {})));
    _manager.start().then((_) {
      final platform = kIsWasm
          ? 'web, wasm'
          : kIsWeb
          ? 'web, js'
          : defaultTargetPlatform.name;
      debugPrint(
        'just_gamepads: started ($platform), '
        '${_manager.connected.length} connected',
      );
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _manager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pads = _manager.connected;
    return Scaffold(
      appBar: AppBar(title: const Text('just_gamepads tester')),
      body: pads.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No controller connected.\n\n'
                  'Connect one and press a button. Browsers only expose a '
                  'controller after a button press while the page has focus.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final info in pads)
                  _PadCard(
                    info: info,
                    state: _manager.latestState(info.id) ?? GamepadState.empty,
                    isActive: _manager.mostRecentlyActiveId == info.id,
                  ),
              ],
            ),
    );
  }
}

class _PadCard extends StatelessWidget {
  const _PadCard({
    required this.info,
    required this.state,
    required this.isActive,
  });

  final GamepadInfo info;
  final GamepadState state;
  final bool isActive;

  static const _buttonNames = {
    GamepadButton.a: 'A',
    GamepadButton.b: 'B',
    GamepadButton.x: 'X',
    GamepadButton.y: 'Y',
    GamepadButton.leftBumper: 'LB',
    GamepadButton.rightBumper: 'RB',
    GamepadButton.leftTriggerButton: 'LT',
    GamepadButton.rightTriggerButton: 'RT',
    GamepadButton.back: 'Back',
    GamepadButton.start: 'Start',
    GamepadButton.leftStick: 'LS',
    GamepadButton.rightStick: 'RS',
    GamepadButton.dpadUp: 'Up',
    GamepadButton.dpadDown: 'Down',
    GamepadButton.dpadLeft: 'Left',
    GamepadButton.dpadRight: 'Right',
  };

  String _hex(int? value) => value == null
      ? '-'
      : '0x${value.toRadixString(16).padLeft(4, '0').toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isActive ? scheme.primary : scheme.outlineVariant,
          width: isActive ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(info.name, style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${info.type.name} · vendor ${_hex(info.vendorId)} · '
              'product ${_hex(info.productId)} · id ${info.id}'
              '${isActive ? ' · active' : ''}',
              style: text.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final MapEntry(:key, :value) in _buttonNames.entries)
                  _ButtonChip(
                    label: value,
                    down: state.buttonsDown.contains(key),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            for (final axis in GamepadAxis.values)
              _AxisBar(name: axis, value: state.axes[axis]),
          ],
        ),
      ),
    );
  }
}

class _ButtonChip extends StatelessWidget {
  const _ButtonChip({required this.label, required this.down});

  final String label;
  final bool down;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 44),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: down ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: down ? scheme.onPrimary : scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AxisBar extends StatelessWidget {
  const _AxisBar({required this.name, required this.value});

  final String name;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isTrigger = name.endsWith('Trigger');
    final v = value ?? 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(name)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 10,
                child: CustomPaint(
                  painter: _AxisPainter(
                    value: v,
                    signed: !isTrigger,
                    track: scheme.surfaceContainerHighest,
                    fill: scheme.primary,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              value == null ? 'n/a' : v.toStringAsFixed(2),
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AxisPainter extends CustomPainter {
  _AxisPainter({
    required this.value,
    required this.signed,
    required this.track,
    required this.fill,
  });

  final double value;
  final bool signed;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = track);
    final paint = Paint()..color = fill;
    if (signed) {
      final mid = size.width / 2;
      final end = mid + value.clamp(-1.0, 1.0) * mid;
      canvas.drawRect(
        Rect.fromLTRB(
          end < mid ? end : mid,
          0,
          end < mid ? mid : end,
          size.height,
        ),
        paint,
      );
    } else {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width * value.clamp(0.0, 1.0), size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_AxisPainter old) =>
      old.value != value || old.fill != fill || old.track != track;
}
