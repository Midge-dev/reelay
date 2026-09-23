import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// What a screen should look like when Back returns to it: which item had
/// focus, how far each list was scrolled ([bucket], via PageStorageKey),
/// and any screen-local state it chooses to keep there (Search's query).
///
/// AppRoot rebuilds a screen from scratch whenever its AppState comes back
/// round, so without this every return landed on the screen's default
/// focus with an empty query and every list at the top. One memory belongs
/// to one AppState *object* ([ScreenMemory.of]) — a fresh visit (a rail
/// tap) builds a new state and starts clean; Back hands the same object
/// back and gets its memory with it.
class ScreenMemory {
  final bucket = PageStorageBucket();
  String? focusedId;

  static final _byState = Expando<ScreenMemory>('screen-memory');

  static ScreenMemory of(Object state) => _byState[state] ??= ScreenMemory();

  /// A state rebuilt from another (a refresh on return, a copyWith after
  /// removing a row) is still the same screen to the user.
  static void carry(Object from, Object to) {
    final memory = _byState[from];
    if (memory != null) _byState[to] = memory;
  }

  static _ScreenMemoryScopeState? _scopeOf(BuildContext context) =>
      context.findAncestorStateOfType<_ScreenMemoryScopeState>();

  /// True while a screen is being returned to and its remembered item
  /// hasn't taken focus back yet — a screen's own "focus the first thing"
  /// default should stand aside, or it scrolls to the top first.
  static bool restoringOf(BuildContext context) =>
      _scopeOf(context)?._pendingId != null;

  /// Screen-local state kept across a return, e.g. Search's query.
  static T? read<T>(BuildContext context, String id) =>
      _scopeOf(context)?.widget.memory.bucket.readState(context, identifier: id)
          as T?;

  static void write(BuildContext context, String id, Object? value) =>
      _scopeOf(context)?.widget.memory.bucket
          .writeState(context, value, identifier: id);
}

/// Hosts one screen's [ScreenMemory]. Key it by the memory so a different
/// screen of the same type (another movie's detail) gets its own State.
class ScreenMemoryScope extends StatefulWidget {
  final ScreenMemory memory;
  final Widget child;

  const ScreenMemoryScope({
    super.key,
    required this.memory,
    required this.child,
  });

  @override
  State<ScreenMemoryScope> createState() => _ScreenMemoryScopeState();
}

class _ScreenMemoryScopeState extends State<ScreenMemoryScope> {
  final _contentFocus = FocusNode(
    debugLabel: 'screen-memory-scope',
    canRequestFocus: false,
    skipTraversal: true,
  );
  String? _pendingId;

  @override
  void initState() {
    super.initState();
    _pendingId = widget.memory.focusedId;
    if (_pendingId == null) return;
    // The first key press abandons a restore still waiting on its item
    // (a detail page's cast loads after the page): focus must never jump
    // once the user has started moving.
    HardwareKeyboard.instance.addHandler(_abandonOnInput);
    // A remembered item that no longer exists (removed from Continue
    // Watching) would otherwise leave nothing focused, since the screen
    // stood its own default aside. A microtask from the first post-frame
    // callback runs once every item's own post-frame claim has had its
    // turn (a nested post-frame callback would wait for a frame nothing
    // schedules).
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => scheduleMicrotask(_fallBackIfUnrestored),
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_abandonOnInput);
    _contentFocus.dispose();
    super.dispose();
  }

  bool _abandonOnInput(KeyEvent event) {
    if (event is KeyDownEvent) _settle();
    return false;
  }

  void _settle() {
    _pendingId = null;
    HardwareKeyboard.instance.removeHandler(_abandonOnInput);
  }

  void _fallBackIfUnrestored() {
    if (!mounted || _pendingId == null) return;
    if (_contentFocus.hasFocus) return;
    final first = _contentFocus.traversalDescendants
        .where((n) => n.canRequestFocus)
        .firstOrNull;
    if (first == null) return; // nothing built yet; the restore may still land
    // Still pending: an item that arrives with the page's data (a detail
    // page's cast) takes focus back when it mounts, unless a key has been
    // pressed by then.
    first.requestFocus();
  }

  /// Called by the [RememberFocus] whose id matches; true if it should
  /// take focus now.
  bool _claim(String id) {
    if (_pendingId != id) return false;
    _settle();
    return true;
  }

  // Recording doesn't settle a pending restore: a screen that keeps its
  // own default focus while its data loads still hands focus back to the
  // remembered item once that item exists.
  void _record(String id) => widget.memory.focusedId = id;

  @override
  Widget build(BuildContext context) => PageStorage(
    bucket: widget.memory.bucket,
    child: Focus(focusNode: _contentFocus, child: widget.child),
  );
}

/// Marks [child] as something a screen can return focus to. [id] must be
/// stable across rebuilds and unique on the screen (prefix it by row when
/// the same title can sit in two rows). Don't nest these.
class RememberFocus extends StatefulWidget {
  final String id;
  final Widget child;

  const RememberFocus({super.key, required this.id, required this.child});

  @override
  State<RememberFocus> createState() => _RememberFocusState();
}

class _RememberFocusState extends State<RememberFocus> {
  final _node = FocusNode(
    debugLabel: 'remember-focus',
    canRequestFocus: false,
    skipTraversal: true,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ScreenMemory._scopeOf(context)?._claim(widget.id) ?? false) {
        _node.traversalDescendants
            .where((n) => n.canRequestFocus)
            .firstOrNull
            ?.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _node,
    onFocusChange: (focused) {
      if (focused) ScreenMemory._scopeOf(context)?._record(widget.id);
    },
    child: widget.child,
  );
}
