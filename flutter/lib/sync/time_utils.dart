import 'package:clock/clock.dart';

/// Wall-clock milliseconds, read through package:clock so tests running
/// under fakeAsync control it too.
int nowMs() => clock.now().millisecondsSinceEpoch;
