import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Length-prefixed JSON framing: each message is a 4-byte little-endian
/// unsigned length followed by that many UTF-8 JSON bytes. Used identically
/// over stdio and (on Windows) Named Pipes.

/// Encodes one JSON object into a framed byte chunk.
Uint8List frameMessage(Map<String, Object?> json) {
  final payload = utf8.encode(jsonEncode(json));
  final out = Uint8List(4 + payload.length);
  ByteData.view(out.buffer).setUint32(0, payload.length, Endian.little);
  out.setRange(4, out.length, payload);
  return out;
}

/// Decodes a byte stream into a stream of JSON objects. Tolerates chunks
/// split anywhere (including inside the length prefix).
Stream<Map<String, Object?>> decodeMessages(Stream<List<int>> source) {
  final controller = StreamController<Map<String, Object?>>();
  final buffer = BytesBuilder(copy: false);
  var expectedLength = -1;

  void drain() {
    while (true) {
      if (expectedLength < 0) {
        if (buffer.length < 4) return;
        final bytes = buffer.takeBytes();
        expectedLength =
            ByteData.view(Uint8List.fromList(bytes.sublist(0, 4)).buffer)
                .getUint32(0, Endian.little);
        if (bytes.length > 4) buffer.add(bytes.sublist(4));
      }
      if (buffer.length < expectedLength) return;
      final bytes = buffer.takeBytes();
      final payload = bytes.sublist(0, expectedLength);
      if (bytes.length > expectedLength) {
        buffer.add(bytes.sublist(expectedLength));
      }
      expectedLength = -1;
      controller.add(
          (jsonDecode(utf8.decode(payload)) as Map).cast<String, Object?>());
    }
  }

  final sub = source.listen(
    (chunk) {
      buffer.add(chunk);
      drain();
    },
    onError: controller.addError,
    onDone: controller.close,
  );
  controller.onCancel = () => sub.cancel();
  return controller.stream;
}
