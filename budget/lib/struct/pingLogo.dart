// Business logos from Ping (contract/ping-paddhu/SPEC.md section 10). Paddhu never fetches a logo from the internet: it asks Ping,
// which answers only Paddhu (package and signing certificate). Without Ping, an older Ping, or before Ping knows this Paddhu, the
// screens look as they did before (no logo).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const MethodChannel _pingLogoChannel =
    MethodChannel('com.mansaketh.paddhupusthakam/ping');

final RegExp _brandKeyRe = RegExp(r'^[a-z0-9]{1,40}$');

/// true for a `brandKey` as the contract defines it (lower-case letters and digits).
bool isValidBrandKey(String? key) => key != null && _brandKeyRe.hasMatch(key);

final Map<String, Future<Uint8List?>> _logoFutures = {};

/// The logo bytes for a brand key, or (when Ping sent no key, for example an older Ping) for a business-style sender header.
/// null = no logo. Asked once per key while the app runs; the 24 hour cache is on the Android side.
Future<Uint8List?> loadPingLogo({String? brandKey, String? sender}) {
  final String? key = isValidBrandKey(brandKey) ? brandKey : null;
  final String? from = (sender != null && sender.trim().isNotEmpty) ? sender.trim() : null;
  if (key == null && from == null) return Future.value(null);
  return _logoFutures.putIfAbsent(key ?? 'sender:$from', () async {
    try {
      final Uint8List? bytes = await _pingLogoChannel.invokeMethod<Uint8List>(
          'getLogo', {if (key != null) 'brandKey': key, if (key == null) 'sender': from});
      return (bytes == null || bytes.isEmpty) ? null : bytes;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  });
}

/// A round logo, or nothing at all (a zero-size box) while loading and when there is none.
class PingLogoAvatar extends StatelessWidget {
  const PingLogoAvatar({super.key, this.brandKey, this.sender, this.size = 36});
  final String? brandKey;
  final String? sender;
  final double size;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: loadPingLogo(brandKey: brandKey, sender: sender),
      builder: (context, snapshot) {
        final Uint8List? bytes = snapshot.data;
        if (bytes == null) return const SizedBox.shrink();
        return Container(
          width: size,
          height: size,
          margin: const EdgeInsetsDirectional.only(end: 8),
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          clipBehavior: Clip.antiAlias,
          child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        );
      },
    );
  }
}
