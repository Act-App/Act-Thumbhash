import 'dart:isolate';

/// Runs [computation] in a short-lived isolate and returns its result.
Future<R> runIsolated<R>(R Function() computation) => Isolate.run(computation);
