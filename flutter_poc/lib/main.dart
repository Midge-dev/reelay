import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const ReelayFocusPocApp());
}

class ReelayFocusPocApp extends StatelessWidget {
  const ReelayFocusPocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reelay Focus POC',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        scaffoldBackgroundColor: const Color(0xFF0D0D12),
      ),
      home: const PocHomeScreen(),
    );
  }
}

class PocHomeScreen extends StatelessWidget {
  const PocHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          NavRail(),
          Expanded(child: CardRow()),
        ],
      ),
    );
  }
}

class NavRail extends StatefulWidget {
  const NavRail({super.key});

  @override
  State<NavRail> createState() => _NavRailState();
}

class _NavRailState extends State<NavRail> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      onFocusChange: (hasFocus) => setState(() => _expanded = hasFocus),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: _expanded ? 200 : 72,
        color: const Color(0xFF17171D),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            _NavItem(icon: Icons.home, label: 'Home', expanded: _expanded),
            _NavItem(icon: Icons.search, label: 'Search', expanded: _expanded),
            _NavItem(icon: Icons.settings, label: 'Settings', expanded: _expanded),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool expanded;

  const _NavItem({required this.icon, required this.label, required this.expanded});

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _focused ? Colors.deepPurple.withValues(alpha: 0.5) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(widget.icon, color: Colors.white),
            ClipRect(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 150),
                child: SizedBox(
                  width: widget.expanded ? 120 : 0,
                  child: widget.expanded
                      ? Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Text(
                            widget.label,
                            style: const TextStyle(color: Colors.white),
                            overflow: TextOverflow.clip,
                            softWrap: false,
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CardRow extends StatefulWidget {
  const CardRow({super.key});

  @override
  State<CardRow> createState() => _CardRowState();
}

class _CardRowState extends State<CardRow> {
  final List<String> _rooms = List.generate(6, (i) => 'Room ${i + 1}');

  void _removeRoom(String room) {
    setState(() => _rooms.remove(room));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          height: 216,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _rooms.length,
            separatorBuilder: (context, index) => const SizedBox(width: 20),
            itemBuilder: (context, index) {
              final room = _rooms[index];
              return RoomCard(
                key: ValueKey(room),
                title: room,
                onRemove: () => _removeRoom(room),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Detects a D-pad "select" key held long enough to count as a long-press.
/// GestureDetector.onLongPress never fires for this — it only recognizes
/// pointer/touch gestures, not held key events — confirmed empirically on
/// the Shield. Mirrors the real app's DpadLongPress.kt: TV remotes send one
/// raw key-down/key-up pair with real elapsed time between them while held,
/// no OS auto-repeat, so a timer started on key-down and cancelled on
/// key-up (before it fires) is what actually detects the hold.
class _DpadLongPressDetector {
  _DpadLongPressDetector({required this.onLongPress});

  static const threshold = Duration(milliseconds: 500);

  final VoidCallback onLongPress;
  Timer? _timer;
  bool _fired = false;

  static final _selectKeys = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.gameButtonA,
  };

  KeyEventResult handle(KeyEvent event) {
    if (!_selectKeys.contains(event.logicalKey)) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      _timer ??= Timer(threshold, () {
        _fired = true;
        onLongPress();
      });
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      _timer?.cancel();
      _timer = null;
      if (_fired) {
        // Swallow the trailing release tied to the gesture that just opened
        // the overlay, so it isn't also read as a click on whatever the
        // overlay just focused.
        _fired = false;
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  void dispose() => _timer?.cancel();
}

/// Deliberately naive first pass: swaps between the confirm overlay and the
/// card content via if/else, mirroring the original Compose bug pattern, to
/// test empirically whether Flutter's focus system has the same hazard.
class RoomCard extends StatefulWidget {
  final String title;
  final VoidCallback onRemove;

  const RoomCard({super.key, required this.title, required this.onRemove});

  @override
  State<RoomCard> createState() => _RoomCardState();
}

class _RoomCardState extends State<RoomCard> {
  bool _focused = false;
  bool _confirmingRemove = false;
  final _cardFocusNode = FocusNode(debugLabel: 'card-artwork');
  final _cancelFocusNode = FocusNode(debugLabel: 'cancel-button');
  late final _longPress = _DpadLongPressDetector(onLongPress: _openConfirm);

  @override
  void dispose() {
    _longPress.dispose();
    _cardFocusNode.dispose();
    _cancelFocusNode.dispose();
    super.dispose();
  }

  void _openConfirm() {
    setState(() => _confirmingRemove = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cancelFocusNode.requestFocus();
    });
  }

  void _closeConfirm() {
    setState(() => _confirmingRemove = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cardFocusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Fix pattern: the card stays mounted continuously; the confirm overlay
    // layers on top of it in a Stack instead of replacing it, so toggling
    // _confirmingRemove never disposes whatever currently holds focus.
    return SizedBox(
      width: 220,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            _buildCard(),
            if (_confirmingRemove) _buildConfirmOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildCard() {
    return Focus(
      focusNode: _cardFocusNode,
      canRequestFocus: !_confirmingRemove,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) => _longPress.handle(event),
      child: AnimatedScale(
          scale: _focused ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: _focused ? Colors.purpleAccent : Colors.transparent,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(height: 120, color: Colors.blueGrey.shade700),
                Container(
                  height: 60,
                  color: const Color(0xFF1C1C22),
                  padding: const EdgeInsets.all(8),
                  child: Text(widget.title, style: const TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
    );
  }

  Widget _buildConfirmOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black87,
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Remove?', style: TextStyle(color: Colors.white)),
            const SizedBox(height: 12),
            Focus(
              child: TextButton(
                // Removing disposes this card entirely — focus restoration
                // after removal is the parent row's job (checklist item #2),
                // not this card's, so no _closeConfirm() call here.
                onPressed: widget.onRemove,
                child: const Text('Remove'),
              ),
            ),
            Focus(
              focusNode: _cancelFocusNode,
              child: TextButton(
                onPressed: _closeConfirm,
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
