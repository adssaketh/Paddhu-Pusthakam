// A Home-page row that shows only a title and a total; tapping it opens the details underneath.
// Whether it is open is remembered in the app settings under [settingKey].

import 'package:budget/struct/settings.dart';
import 'package:flutter/material.dart';

class FinCollapsible extends StatefulWidget {
  const FinCollapsible({
    Key? key,
    required this.settingKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.total,
    required this.details,
    this.footer,
  }) : super(key: key);

  final String settingKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final String total;

  /// Shown when open.
  final Widget details;
  final Widget? footer;

  @override
  State<FinCollapsible> createState() => _FinCollapsibleState();
}

class _FinCollapsibleState extends State<FinCollapsible> {
  late bool _open = appStateSettings[widget.settingKey] == true;

  void _toggle() {
    setState(() => _open = !_open);
    updateSettings(widget.settingKey, _open, updateGlobalState: false);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.14), borderRadius: BorderRadius.circular(13)),
                child: Icon(widget.icon, size: 20, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(widget.subtitle,
                      style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
                ]),
              ),
              Text(widget.total, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(width: 2),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.expand_more, color: cs.onSurface.withOpacity(0.55)),
              ),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _open
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  widget.details,
                  if (widget.footer != null) widget.footer!,
                ])
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
