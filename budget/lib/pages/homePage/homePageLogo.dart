import 'package:flutter/material.dart';

/// The Paddhu Pusthakam logo shown on the home page, in the empty space above the greeting.
/// The picture is assets/images/app_logo.png (a copy of the launcher icon). Change [size] to make it bigger or smaller.
class HomePageLogo extends StatelessWidget {
  const HomePageLogo({this.size = 84, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        'assets/images/app_logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        // never break the home page if the picture is missing
        errorBuilder: (_, __, ___) => SizedBox(width: size, height: size),
      ),
    );
  }
}
