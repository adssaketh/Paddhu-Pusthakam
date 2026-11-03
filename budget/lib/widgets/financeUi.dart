// Small building blocks shared by the Loans and Fixed deposits screens and the Home lines, so they look
// like one family: a gradient hero card with a big number, rounded cards, pills and thin progress bars.

import 'package:budget/colors.dart';
import 'package:flutter/material.dart';

Color finCardColor(BuildContext context) =>
    getColor(context, "lightDarkAccentHeavyLight");

/// A colour for a bank / loan name, the same every time.
Color finColorFor(String name) {
  int h = 0;
  for (final int c in name.toLowerCase().codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.5, 0.42).toColor();
}

class FinCard extends StatelessWidget {
  const FinCard({Key? key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap})
      : super(key: key);
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: finCardColor(context),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

class FinSectionTitle extends StatelessWidget {
  const FinSectionTitle(this.text, {Key? key, this.trailing}) : super(key: key);
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
      child: Row(children: [
        Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class FinPill extends StatelessWidget {
  const FinPill(this.text, {Key? key, this.icon, this.onHero = false, this.color}) : super(key: key);
  final String text;
  final IconData? icon;
  final bool onHero;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color fg = onHero ? Colors.white : (color ?? cs.onSurface);
    final Color bg = onHero
        ? Colors.white.withOpacity(0.18)
        : (color ?? cs.primary).withOpacity(0.12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 5)],
        Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg)),
      ]),
    );
  }
}

class FinProgress extends StatelessWidget {
  const FinProgress(this.value, {Key? key, this.height = 7, this.color, this.onHero = false})
      : super(key: key);
  final double value;
  final double height;
  final Color? color;
  final bool onHero;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value.isNaN ? 0 : value.clamp(0.0, 1.0).toDouble(),
        minHeight: height,
        backgroundColor: onHero ? Colors.white.withOpacity(0.22) : (color ?? cs.primary).withOpacity(0.15),
        valueColor: AlwaysStoppedAnimation<Color>(onHero ? Colors.white : (color ?? cs.primary)),
      ),
    );
  }
}

/// The big gradient card at the top of a screen.
class FinHero extends StatelessWidget {
  const FinHero({
    Key? key,
    required this.label,
    required this.amount,
    this.caption,
    this.progress,
    this.progressLeft,
    this.progressRight,
    this.pills = const [],
    this.icon,
  }) : super(key: key);

  final String label;
  final String amount;
  final String? caption;
  final double? progress;
  final String? progressLeft;
  final String? progressRight;
  final List<Widget> pills;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color a = cs.primary;
    final Color b = Color.lerp(cs.primary, cs.tertiary, 0.6) ?? cs.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b]),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: a.withOpacity(0.28), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (icon != null) ...[Icon(icon, color: Colors.white70, size: 18), const SizedBox(width: 8)],
          Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(amount,
              style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800)),
        ),
        if (caption != null)
          Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(caption!, style: const TextStyle(color: Colors.white70, fontSize: 13))),
        if (progress != null) ...[
          const SizedBox(height: 16),
          FinProgress(progress!, height: 9, onHero: true),
          if (progressLeft != null || progressRight != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Expanded(child: Text(progressLeft ?? '', style: const TextStyle(color: Colors.white, fontSize: 12.5))),
                Text(progressRight ?? '', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
              ]),
            ),
        ],
        if (pills.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: pills),
        ],
      ]),
    );
  }
}

/// Label above, value below, for a row of figures.
class FinStat extends StatelessWidget {
  const FinStat(this.label, this.value, {Key? key, this.bold = false, this.color}) : super(key: key);
  final String label;
  final String value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(fontSize: 15, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color)),
    ]);
  }
}

/// "Label ........ value" line for breakdowns.
class FinLine extends StatelessWidget {
  const FinLine(this.label, this.value, {Key? key, this.bold = false, this.dim = false}) : super(key: key);
  final String label;
  final String value;
  final bool bold;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final Color base = Theme.of(context).colorScheme.onSurface;
    final TextStyle s = TextStyle(
        fontSize: bold ? 16 : 14,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
        color: dim ? base.withOpacity(0.6) : base);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [Expanded(child: Text(label, style: s)), Text(value, style: s)]),
    );
  }
}

/// Round avatar with the first letter, coloured from the name.
class FinAvatar extends StatelessWidget {
  const FinAvatar(this.name, {Key? key, this.size = 40}) : super(key: key);
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color c = finColorFor(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.withOpacity(0.16), borderRadius: BorderRadius.circular(size * 0.35)),
      child: Text(name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
          style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: size * 0.45)),
    );
  }
}

InputDecoration finInput(BuildContext context, String label, {String? suffix, String? prefix}) {
  final Color c = Theme.of(context).colorScheme.onSurface.withOpacity(0.12);
  OutlineInputBorder b(Color color) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: color));
  return InputDecoration(
    labelText: label,
    suffixText: suffix,
    prefixText: prefix,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    enabledBorder: b(c),
    focusedBorder: b(Theme.of(context).colorScheme.primary),
    border: b(c),
  );
}
