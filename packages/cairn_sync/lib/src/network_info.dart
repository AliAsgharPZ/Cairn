import 'dart:io';

/// LAN presence detection: which IPv4 addresses does this device
/// currently have on real network interfaces (Wi-Fi / Ethernet /
/// Tailscale)? The studio used to have NO answer to "am I even on a
/// network?" — pairing asked the owner to type an IP address into a
/// device whose own address was shown nowhere. These helpers are the
/// fix: plain `dart:io` interface enumeration, no plugins.

/// Non-loopback IPv4 addresses of this device, best first (private
/// LAN ranges and the Tailscale CGNAT range before anything else).
Future<List<String>> lanIpv4Addresses() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
    includeLinkLocal: true,
  );
  final addresses = <String>[];
  for (final iface in interfaces) {
    for (final addr in iface.addresses) {
      if (!addr.isLoopback) addresses.add(addr.address);
    }
  }
  addresses.sort((a, b) => _rank(a).compareTo(_rank(b)));
  return addresses;
}

int _rank(String ip) {
  final parts = ip.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null)) return 9;
  final a = parts[0]!, b = parts[1]!;
  if (a == 192 && b == 168) return 0; // home/office LAN
  if (a == 10) return 1; // private LAN / hotspot
  if (a == 172 && b >= 16 && b <= 31) return 2; // private LAN
  if (a == 100 && b >= 64 && b <= 127) return 3; // Tailscale CGNAT
  if (a == 169 && b == 254) return 8; // link-local (no DHCP — half-broken)
  return 5;
}

/// True when the device has at least one usable LAN address.
Future<bool> hasLanAddress() async => (await lanIpv4Addresses()).isNotEmpty;

/// This device's primary LAN address, or null when offline.
Future<String?> primaryLanAddress() async {
  final all = await lanIpv4Addresses();
  return all.isEmpty ? null : all.first;
}
