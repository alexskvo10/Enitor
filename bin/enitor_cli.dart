import 'dart:io';

import 'package:enitor/cli/cli.dart';
import 'package:enitor/cli/mcp_runner.dart';
import 'package:enitor/cli/transport.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first == 'mcp') {
    await runMcp();
    exit(0);
  }
  final code = await runCli(
    args,
    transport: WindowsPipeTransport(),
    out: stdout,
    err: stderr,
  );
  exit(code);
}
