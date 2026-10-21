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
// Shutdown contract (learned from a real Windows CI hang, run
// 39635044715: the round-trip test passed its assertions but the
// process never exited): exactly one owner — the main isolate —
// closes the handle, exactly once, and it does so from OUTSIDE the
// reader isolate. Closing the handle is what unblocks the reader's
// pending ReadFile (it then reports 'closed' and exits on its own);
// Isolate.kill() does NOT preempt a blocking FFI call, and a writer
// isolate closing the handle on its own raced the reader. Every
// channel must be closed by its owner when done.
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
    int handle = _invalidHandleValue;
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
      if (ConnectNamedPipe(handle, nullptr) == 0) {
        // In blocking (PIPE_WAIT) mode a 0 return means the client
        // raced us (ERROR_PIPE_CONNECTED, 535 — the pipe IS connected
        // and usable) or the handle is broken. Reading GetLastError()
        // through the FFI boundary proved unreliable here (CI on real
        // Windows returned 0 for a genuine 535, which a previous
        // version wrongly treated as fatal), so probe the connection
        // state directly instead: PeekNamedPipe succeeds on a
        // connected pipe even when no data is waiting.
        final probe =
            PeekNamedPipe(handle, nullptr, 0, nullptr, nullptr, nullptr);
        if (probe == 0) {
          args.reply.send(
              'ConnectNamedPipe failed and the pipe is not connected');
          CloseHandle(handle);
          return;
        }
      }
    } else {
      // The server may not have created the instance yet (host still
      // starting): retry briefly on FILE_NOT_FOUND / PIPE_BUSY.
      var lastError = 0;
      for (var attempt = 0; attempt < 50; attempt++) {
        final h = CreateFile(
          path,
          _genericRead | _genericWrite,
          0,
          nullptr,
          _openExisting,
          0,
          0,
        );
        if (h != _invalidHandleValue) {
          handle = h;
          break;
        }
        lastError = GetLastError();
        if (lastError != 2 /* ERROR_FILE_NOT_FOUND */ &&
            lastError != 231 /* ERROR_PIPE_BUSY */) {
          break;
        }
        sleep(const Duration(milliseconds: 100));
      }
      if (handle == _invalidHandleValue) {
        args.reply.send('CreateFile error $lastError');
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
      // The handle is closed by the main isolate (single owner);
      // closing it here too could close a recycled handle value.
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

  var handleClosed = false;
  return PipeChannel._(
    controller.stream,
    sinkController.sink,
    () {
      // Single-owner close: this (main) isolate closes the handle
      // exactly once. That unblocks the reader isolate's pending
      // ReadFile, which reports 'closed' and exits by itself; the
      // writer is told to exit without touching the handle.
      if (!handleClosed) {
        handleClosed = true;
        CloseHandle(handle);
      }
      writerPort.send('close');
      if (!controller.isClosed) {
        controller.close();
      }
      inbound.close();
      // Last resort only: if an isolate still has not exited after
      // the handle close gave it its chance, kill it.
      Timer(const Duration(seconds: 2), () {
        reader.kill();
        writer.kill();
      });
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
