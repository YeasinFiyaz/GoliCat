import 'package:material_ui/material_ui.dart';

/// A button icon that melts into a small spinner while work is in progress.
/// Keeps the button's size and colour, so nothing around it jumps or greys
/// out: the spinner takes the button's own text colour.
class BusyIcon extends StatelessWidget {
  const BusyIcon({super.key, required this.busy, required this.icon, this.size = 18});
  final bool busy;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween(begin: 0.7, end: 1.0).animate(anim), child: child),
      ),
      child: busy
          ? SizedBox(
              key: const ValueKey('spinner'),
              width: size,
              height: size,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                strokeCap: StrokeCap.round,
                color: IconTheme.of(context).color ?? DefaultTextStyle.of(context).style.color,
              ),
            )
          : Icon(icon, key: const ValueKey('icon'), size: size),
    );
  }
}

/// Swaps a button label while busy (e.g. "End trip" → "Ending…").
class BusyLabel extends StatelessWidget {
  const BusyLabel({super.key, required this.busy, required this.text, required this.busyText});
  final bool busy;
  final String text, busyText;

  @override
  Widget build(BuildContext context) {
    // A plain swap: cross-fading two different strings on top of each other
    // reads as garbled text for a moment.
    return Text(busy ? busyText : text);
  }
}
