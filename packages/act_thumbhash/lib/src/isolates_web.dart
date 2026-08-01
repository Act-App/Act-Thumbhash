/// Runs [computation] on the event loop and returns its result.
///
/// This is the fallback for platforms without isolate support, such as the
/// web. The computation still runs on the calling thread, but is scheduled as
/// a new event-loop task rather than a microtask, so the browser gets one
/// chance to paint or handle input before the work starts. Unlike the isolate
/// implementation, the closure runs against live captured state: callers must
/// not mutate inputs until the returned future completes.
Future<R> runIsolated<R>(R Function() computation) {
  return Future<R>.delayed(Duration.zero, computation);
}
