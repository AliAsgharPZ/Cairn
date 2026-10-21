import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Length-prefixed JSON framing shared by the sync session and the
/// overflow protocol: a 4-byte little-endian length + UTF-8 JSON body.
Uint8List frameMessage(Map<String, Object?> json) {
  final payload = utf8.encode(jsonEncode(json));
  final out = Uint8List(4 + payload.length);
  ByteData.view(out.buffer).setUint32(0, payload.length, Endian.little);
  out.setRange(4, out.length, payload);
  return out;
}

/// Decodes a byte stream into framed JSON messages.
Stream<Map<String, Object?>> decodeFrames(Stream<List<int>> source) {
  final controller = StreamController<Map<String, Object?>>();
  final buffer = BytesBuilder(copy: false);
  var expected = -1;
  void drain() {
    while (true) {
      if (expected < 0) {
        if (buffer.length < 4) return;
        final bytes = buffer.takeBytes();
        expected =
            ByteData.view(Uint8List.fromList(bytes.sublist(0, 4)).buffer)
                .getUint32(0, Endian.little);
        if (bytes.length > 4) buffer.add(bytes.sublist(4));
      }
      if (buffer.length < expected) return;
      final bytes = buffer.takeBytes();
      final payload = bytes.sublist(0, expected);
      if (bytes.length > expected) buffer.add(bytes.sublist(expected));
      expected = -1;
      controller.add(
          (jsonDecode(utf8.decode(payload)) as Map).cast<String, Object?>());
    }
  }

  final sub = source.listen((chunk) {
    buffer.add(chunk);
    drain();
  }, onError: controller.addError, onDone: controller.close);
  controller.onCancel = () => sub.cancel();
  return controller.stream;
}
