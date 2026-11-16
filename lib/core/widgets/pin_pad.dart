import 'package:flutter/material.dart';

/// 4-dot PIN display with a numeric keypad.
class PinPad extends StatefulWidget {
  const PinPad({super.key, required this.onCompleted, this.length = 4});
  final ValueChanged<String> onCompleted;
  final int length;

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> {
  String _pin = '';

  void clear() => setState(() => _pin = '');

  void _tap(String d) {
    if (_pin.length >= widget.length) return;
    setState(() => _pin += d);
    if (_pin.length == widget.length) {
      final value = _pin;
      Future.delayed(const Duration(milliseconds: 150), () => widget.onCompleted(value));
    }
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.length, (i) {
            final filled = i < _pin.length;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 10),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? scheme.primary : Colors.transparent,
                border: Border.all(color: filled ? scheme.primary : scheme.outline, width: 2),
              ),
            );
          }),
        ),
        const SizedBox(height: 36),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['', '0', '<'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map((k) {
                if (k.isEmpty) return const SizedBox(width: 72, height: 72);
                return SizedBox(
                  width: 72,
                  height: 72,
                  child: Material(
                    color: scheme.surface,
                    shape: CircleBorder(side: BorderSide(color: scheme.outline)),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => k == '<' ? _back() : _tap(k),
                      child: Center(
                        child: k == '<'
                            ? Icon(Icons.backspace_outlined, color: scheme.onSurface)
                            : Text(k, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500)),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
