import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

// Windows Named Pipe transport for the Tool Host (M5 remainder).
//
// The Tool Host protocol is transport-agnostic (framed bytes over a
// Stream/Sink pair); this file provides that pair over a real Win32
// named pipe (\\.\pipe\<name>) for the shipped Windows configuration.
// stdio remains the development/test transport.
//
// Threading: Win32 pipe IO is blocking, and a single isolate blocked
// in ReadFile could never send — so the handle is opened in a
// short-lived helper isolate, reads run in a dedicated reader isolate,
// and writes in a dedicated writer isolate. The OS handle is a plain
// integer valid across isolates of the same process.
//
// Access control: a \\.\pipe name is reachable by processes of the
// same user session under the default ACL; v1's trust model is
// same-user (the app spawns its own host). Cross-user hardening is
// out of scope and NOT claimed here.

// Win32 constants (stable values, defined locally to avoid depending
// on generated constant names).
const _pipeAccessDuplex = 0x00000003;
const _pipeTypeByte = 0x00000000;
const _pipeReadModeByte = 0x00000000;
const _pipeWait = 0x00000000;
const _genericRead = 0x80000000;
const _genericWrite = 0x40000000;
const _openExisting = 3;
const _invalidHandleValue = -1;

/// A connected named-pipe byte channel: [stream] of inbound bytes and
/// [sink] for outbound bytes — exactly what ToolHostClient /
/// ToolHostServer consume.
class PipeChannel {
  PipeChannel._(this.stream, this._sink, this._teardown);

  final Stream<List<int>> stream;
  final StreamSink<List<int>> _sink;
  final void Function() _teardown;

  StreamSink<List<int>> get sink => _sink;

  Future<void> close() async {
    await _sink.close();
    _teardown();
  }
}

String _pipePath(String name) => '\\\\.\\pipe\\$name';

/// Opens the pipe handle in a helper isolate (ConnectNamedPipe blocks
/// until a client arrives on the server side) and returns the raw
/// process-wide handle value.
Future<int> _openHandle({required bool server, required String name}) async {
  final port = ReceivePort();
  await Isolate.spawn(
    _openIsolate,
    (server: server, name: name, reply: port.sendPort),
    errorsAreFatal: false,
  );
  final message = await port.first;
  if (message is int) return message;
  throw StateError('named pipe open failed: $message');
}

void _openIsolate(({bool server, String name, SendPort reply}) args) {
  final path = _pipePath(args.name).toNativeUtf16();
  try {
    final int handle;
    if (args.server) {
      handle = CreateNamedPipe(
        path,
        _pipeAccessDuplex,
        _pipeTypeByte | _pipeReadModeByte | _pipeWait,
        1, // one instance: one app <-> one host
        65536,
        65536,
        0,
        nullptr,
      );
      if (handle == _invalidHandleValue) {
        args.reply.send('CreateNamedPipe error ${GetLastError()}');
        return;
      }
      if (ConnectNamedPipe(handle, nullptr) == 0 &&
          GetLastError() != 535 /* ERROR_PIPE_CONNECTED */) {
        args.reply.send('ConnectNamedPipe error ${GetLastError()}');
        CloseHandle(handle);
        return;
      }
    } else {
      handle = CreateFile(
        path,
        _genericRead | _genericWrite,
        0,
        nullptr,
        _openExisting,
        0,
        0,
      );
      if (handle == _invalidHandleValue) {
        args.reply.send('CreateFile error ${GetLastError()}');
        return;
      }
    }
    args.reply.send(handle);
  } finally {
    malloc.free(path);
  }
}

void _readerIsolate(({int handle, SendPort toMain}) args) {
  final buffer = malloc<Uint8>(65536);
  final readCount = malloc<Uint32>();
  try {
    while (true) {
      final ok = ReadFile(args.handle, buffer, 65536, readCount, nullptr);
      if (ok == 0 || readCount.value == 0) {
        args.toMain.send('closed');
        return;
      }
      final bytes = Uint8List.fromList(buffer.asTypedList(readCount.value));
      args.toMain.send(bytes);
    }
  } finally {
    malloc.free(buffer);
    malloc.free(readCount);
  }
}

void _writerIsolate(({int handle, SendPort ready}) args) {
  final port = ReceivePort();
  args.ready.send(port.sendPort);
  final written = malloc<Uint32>();
  port.listen((message) {
    if (message == 'close') {
      CloseHandle(args.handle);
      malloc.free(written);
      Isolate.exit();
    }
    if (message is Uint8List) {
      final buffer = malloc<Uint8>(message.length);
      buffer.asTypedList(message.length).setAll(0, message);
      var offset = 0;
      while (offset < message.length) {
        final ok = WriteFile(args.handle, buffer + offset,
            message.length - offset, written, nullptr);
        if (ok == 0 || written.value == 0) break;
        offset += written.value;
      }
      malloc.free(buffer);
    }
  });
}

Future<PipeChannel> _channel({required bool server, required String name}) async {
  if (!Platform.isWindows) {
    throw UnsupportedError('named pipes are a Windows transport');
  }
  final handle = await _openHandle(server: server, name: name);

  // Reader isolate → inbound stream.
  final inbound = ReceivePort();
  final reader = await Isolate.spawn(
    _readerIsolate,
    (handle: handle, toMain: inbound.sendPort),
    errorsAreFatal: false,
  );
  final controller = StreamController<List<int>>();
  inbound.listen((message) {
    if (message is Uint8List) {
      controller.add(message);
    } else if (message == 'closed') {
      controller.close();
    }
  });

  // Writer isolate ← outbound sink.
  final writerReady = ReceivePort();
  final writer = await Isolate.spawn(
    _writerIsolate,
    (handle: handle, ready: writerReady.sendPort),
    errorsAreFatal: false,
  );
  final writerPort = await writerReady.first as SendPort;
  final sinkController = StreamController<List<int>>();
  sinkController.stream.listen(
    (chunk) => writerPort.send(Uint8List.fromList(chunk)),
    onDone: () => writerPort.send('close'),
  );

  return PipeChannel._(
    controller.stream,
    sinkController.sink,
    () {
      reader.kill();
      writer.kill();
      inbound.close();
    },
  );
}

/// Listens on `\\.\pipe\<name>` and returns the channel once a client
/// connects (the Tool Host side).
Future<PipeChannel> listenNamedPipe(String name) =>
    _channel(server: true, name: name);

/// Connects to a listening `\\.\pipe\<name>` (the app side).
Future<PipeChannel> connectNamedPipe(String name) =>
    _channel(server: false, name: name);
