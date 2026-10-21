import 'package:cairn_toolhost/cairn_toolhost.dart';

/// The Tool Host process entry point. See runToolHost for the contract:
/// framed JSON-RPC on stdin/stdout, diagnostics on stderr.
Future<void> main(List<String> args) => runToolHost(args);
