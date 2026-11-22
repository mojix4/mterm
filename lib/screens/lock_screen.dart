import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../l10n.dart';
import '../store.dart';
import '../themes.dart';

/// Covers the whole app with the PIN screen when app lock is on.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child});
  final Widget child;
  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool locked = Store.i.settings.lockEnabled && Store.i.settings.pinHash.isNotEmpty;
  DateTime? pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final s = Store.i.settings;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final p = pausedAt;
      pausedAt = null;
      if (s.lockEnabled && s.pinHash.isNotEmpty && p != null &&
          DateTime.now().difference(p).inSeconds >= s.lockAfter && !locked) {
        setState(() => locked = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Offstage(offstage: locked, child: TickerMode(enabled: !locked, child: widget.child)),
      if (locked) PinPad(onUnlocked: () => setState(() => locked = false)),
    ]);
  }
}

/// PIN entry. In unlock mode it checks the stored PIN; in set mode it asks twice and returns it.
class PinPad extends StatefulWidget {
  const PinPad({super.key, this.onUnlocked, this.setMode = false});
  final VoidCallback? onUnlocked;
  final bool setMode;
  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  String pin = '';
  String? first;
  bool error = false;
  late final AnimationController shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 380));

  String title(S s) {
    if (!widget.setMode) return s['lockEnter'];
    return first == null ? s['lockChoose'] : s['lockRepeat'];
  }

  @override
  void initState() {
    super.initState();
    if (!widget.setMode && Store.i.settings.biometric) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bio());
    }
  }

  @override
  void dispose() {
    shake.dispose();
    super.dispose();
  }

  Future<void> _bio() async {
    try {
      final auth = LocalAuthentication();
      final reason = S.of(context)['bioReason'];
      if (!await auth.isDeviceSupported()) return;
      final ok = await auth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(biometricOnly: !Platform.isWindows, stickyAuth: true),
      );
      if (ok) widget.onUnlocked?.call();
    } catch (_) {}
  }

  void _tap(String k) {
    HapticFeedback.selectionClick();
    setState(() {
      error = false;
      if (k == '⌫') {
        if (pin.isNotEmpty) pin = pin.substring(0, pin.length - 1);
      } else if (pin.length < 4) {
        pin += k;
      }
    });
    if (pin.length == 4) Future.delayed(const Duration(milliseconds: 120), _done);
  }

  void _fail() {
    HapticFeedback.heavyImpact();
    shake.forward(from: 0);
    setState(() {
      error = true;
      pin = '';
    });
  }

  void _done() {
    // the user may have hit backspace (or left) during the short delay
    if (!mounted || pin.length != 4) return;
    if (!widget.setMode) {
      if (Store.hashPin(pin) == Store.i.settings.pinHash) {
        widget.onUnlocked?.call();
      } else {
        _fail();
      }
      return;
    }
    if (first == null) {
      setState(() {
        first = pin;
        pin = '';
      });
    } else if (first == pin) {
      Navigator.of(context).pop(pin);
    } else {
      first = null;
      _fail();
    }
  }

  Widget _header(S s, Palette p) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(22)),
          child: Icon(Icons.lock_outline, color: p.green, size: 34),
        ),
        const SizedBox(height: 20),
        Text(title(s), textAlign: TextAlign.center, style: TextStyle(fontSize: 17, color: p.text)),
        const SizedBox(height: 6),
        Text(error ? s['wrongPin'] : ' ', style: TextStyle(color: p.red, fontSize: 13)),
        const SizedBox(height: 18),
        AnimatedBuilder(
          animation: shake,
          builder: (_, child) {
            final t = shake.value;
            final dx = (t == 0 || t == 1) ? 0.0 : 10 * (1 - t) * ((t * 20).floor().isEven ? 1 : -1);
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                4,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  margin: const EdgeInsets.symmetric(horizontal: 9),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < pin.length ? p.text : Colors.transparent,
                    border: Border.all(color: error ? p.red : p.muted, width: 2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]);

  static const _gapY = 14.0, _gapX = 26.0;

  /// Keypad width that fits [height] (4 square rows) and at most 300 wide.
  static double _padWidth(double height) {
    final cell = ((height - 3 * _gapY) / 4).clamp(36.0, (300 - 2 * _gapX) / 3);
    return cell * 3 + 2 * _gapX;
  }

  Widget _keypad(double width, Palette p) {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'bio', '0', '⌫'];
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: width,
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 3,
          mainAxisSpacing: _gapY,
          crossAxisSpacing: _gapX,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          children: keys.map((k) {
            if (k == 'bio') {
              final show = !widget.setMode && Store.i.settings.biometric;
              return show
                  ? IconButton(onPressed: _bio, icon: Icon(Icons.fingerprint, size: 34, color: p.green))
                  : const SizedBox();
            }
            return InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _tap(k),
              child: Container(
                alignment: Alignment.center,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: k == '⌫' ? Colors.transparent : p.surface),
                child: k == '⌫'
                    ? Icon(Icons.backspace_outlined, color: p.muted)
                    : Text(k, style: TextStyle(fontSize: 26, color: p.text)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final p = context.pal;
    final close = widget.setMode
        ? IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop())
        : null;
    return Material(
      color: p.bg,
      child: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          // Landscape / short screens: header beside the keypad.
          if (box.maxWidth > box.maxHeight && box.maxHeight < 560) {
            return Stack(children: [
              Row(children: [
                Expanded(child: Center(child: SingleChildScrollView(child: _header(s, p)))),
                Expanded(child: Center(child: _keypad(_padWidth(box.maxHeight - 32), p))),
              ]),
              if (close != null) PositionedDirectional(top: 0, start: 0, child: close),
            ]);
          }
          const headerH = 200.0;
          final top = close == null ? 0.0 : 48.0;
          return Column(children: [
            if (close != null) Align(alignment: AlignmentDirectional.centerStart, child: close),
            const Spacer(flex: 2),
            _header(s, p),
            const Spacer(),
            _keypad(_padWidth(box.maxHeight - headerH - top - 40), p),
            const Spacer(),
          ]);
        }),
      ),
    );
  }
}
