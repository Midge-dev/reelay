import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard, KeyEvent, KeyUpEvent;

/// Spike: does the `dpad` pub package (fluttercandies) cover the remaining
/// items on docs/focus-navigation-qa-checklist.md (#2, #4-9) without more
/// hand-rolled focus code? Items #1/#3 were already fixed by hand in the
/// deleted flutter-reelay POC; they're re-exercised here too (via the
/// package's own dialog-restore + onLongSelect) as a sanity check, not
/// because they were still open.
///
/// NOT meant to be merged — throwaway research code, same as the prior POC.
/// Real focus/D-pad verification happens on the Shield with real remote
/// input (adb shell input keyevent), never taps — see checklist item #0.
void main() => runApp(const SpikeApp());

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'dpad spike',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0D12),
        colorScheme: ThemeData.dark().colorScheme.copyWith(
              primary: const Color(0xFF6C8CFF),
            ),
      ),
      builder: Dpad.wrap(
        debugOverlay: true,
        theme: const DpadThemeData(scrollPadding: 64),
      ),
      home: const SpikeHome(),
    );
  }
}

class SpikeHome extends StatefulWidget {
  const SpikeHome({super.key});

  @override
  State<SpikeHome> createState() => _SpikeHomeState();
}

class _SpikeHomeState extends State<SpikeHome> {
  // #2: room cards to remove, mutable so we can test "remove last item in
  // row" (hazard: nearest-by-distance fallback might jump to the sidebar)
  // vs. "remove a middle item" (should land on a neighbor).
  final List<String> _rooms = List.generate(5, (i) => 'Room ${i + 1}');

  // #6: correction re-fire counter, incremented via onFocusChange on each
  // of three sibling buttons in the same detail panel.
  int _correctionFireCount = 0;
  String _lastCorrectionSource = '(none yet)';

  void _removeRoom(String room) {
    setState(() => _rooms.remove(room));
  }

  void _fireCorrection(String source) {
    setState(() {
      _correctionFireCount++;
      _lastCorrectionSource = source;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(destinations: const ['Home', 'Search', 'Settings']),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 36),
              children: [
                const _SectionLabel('#1/#2/#3 — Rooms row (long-press remove)'),
                _RoomsRow(rooms: _rooms, onRemove: _removeRoom),
                const SizedBox(height: 12),
                _SectionLabel(
                  'TEST-ONLY direct remove (bypasses long-press, for adb verification of #2\'s focus-reclaim only — not part of the real UX pattern)',
                ),
                _TestRemoveRow(rooms: _rooms, onRemove: _removeRoom),
                const SizedBox(height: 40),

                const _SectionLabel(
                  '#4 — whole-card scroll-into-view: GOOD pattern (whole card is one DpadFocusable)',
                ),
                _TallCardRow(wrapWholeCard: true),
                const SizedBox(height: 40),

                const _SectionLabel(
                  '#4 — HAZARD pattern (only the inner button is the DpadFocusable target)',
                ),
                _TallCardRow(wrapWholeCard: false),
                const SizedBox(height: 40),

                const _SectionLabel(
                  '#5 — nested horizontal-in-vertical scroll, no custom scroll code: watch for double-adjustment flash',
                ),
                _TallCardRow(wrapWholeCard: true, cardCount: 10),
                const SizedBox(height: 40),

                _SectionLabel(
                  '#6 — correction re-fire: moved $_correctionFireCount times, last from $_lastCorrectionSource',
                ),
                _CorrectionPanel(onFire: _fireCorrection),
                const SizedBox(height: 40),

                const _SectionLabel('#7 — text field arrow-key escape to sibling'),
                const _SearchRow(),
                const SizedBox(height: 40),

                const _SectionLabel('#8 — menu internal nav must not self-dismiss'),
                const _MenuDemo(),
                const SizedBox(height: 40),

                const _SectionLabel('#9 — scaled card seam (image/info boundary)'),
                const _SeamCard(),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sidebar — verticalEdge: stop, so up/down never falls off the rail. Also
// the thing #2's "nearest by distance" fallback could wrongly jump to.
// ---------------------------------------------------------------------------

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.destinations});
  final List<String> destinations;

  @override
  Widget build(BuildContext context) {
    return DpadRegion(
      debugLabel: 'sidebar',
      verticalEdge: DpadEdgeBehavior.stop,
      child: Container(
        width: 96,
        color: const Color(0xFF11141B),
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: [
            for (int i = 0; i < destinations.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DpadFocusable(
                  entry: i == 0,
                  debugLabel: 'sidebar:${destinations[i]}',
                  onSelect: () {},
                  effects: const [DpadGlowEffect()],
                  child: Container(
                    width: 64,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      destinations[i][0],
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TEST-ONLY: direct one-press remove, no confirm sheet. Exists solely so
// adb (no root, no --longpress dwell support on this device) can verify
// #2's disposal-time focus-reclaim without needing a genuine held key.
// ---------------------------------------------------------------------------

class _TestRemoveRow extends StatelessWidget {
  const _TestRemoveRow({required this.rooms, required this.onRemove});
  final List<String> rooms;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return DpadRegion(
      debugLabel: 'test-remove-row',
      child: SizedBox(
        height: 56,
        child: rooms.isEmpty
            ? const SizedBox.shrink()
            : ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 36),
                itemCount: rooms.length,
                itemBuilder: (context, i) {
                  final room = rooms[i];
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: DpadFocusable(
                      debugLabel: 'test-remove:$room',
                      onSelect: () => onRemove(room),
                      effects: const [DpadGlowEffect()],
                      child: Container(
                        width: 140,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.red.withAlpha(40),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('remove $room', style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// #1/#2/#3: room cards row with long-press-to-remove via onLongSelect
// (native to the package — no hand-rolled DpadLongPress port needed) and a
// modal bottom sheet for confirm (Dpad's own dialog-restore handles #1).
// ---------------------------------------------------------------------------

class _RoomsRow extends StatelessWidget {
  const _RoomsRow({required this.rooms, required this.onRemove});
  final List<String> rooms;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return DpadRegion(
      debugLabel: 'rooms-row',
      memoryKey: 'rooms-row',
      child: SizedBox(
        height: 180,
        child: rooms.isEmpty
            ? const Center(
                child: Text('(row empty — verify focus moved to next section, not sidebar)'),
              )
            : ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
                itemCount: rooms.length,
                itemBuilder: (context, i) {
                  final room = rooms[i];
                  return Padding(
                    padding: const EdgeInsets.only(right: 20),
                    child: DpadFocusable(
                      autofocus: i == 0,
                      debugLabel: 'room:$room',
                      onSelect: () {},
                      onLongSelect: () => _confirmRemoveAfterRelease(context, room),
                      effects: const [
                        DpadScaleEffect(scale: 1.06),
                        DpadGlowEffect(),
                      ],
                      child: Container(
                        width: 160,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B2130),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: Text(room, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  // The onLongSelect guard on Remove/Cancel wasn't enough: Flutter delivers
  // a KeyUpEvent to whichever node currently has focus, not to whoever
  // received the matching KeyDownEvent. onLongSelect fires ~500ms into the
  // hold, autofocuses "Remove", but the physical button is still down —
  // so the eventual real release lands on "Remove" itself and gets
  // consumed as a completed press, exactly the checklist #3 hazard, just
  // via the trailing release instead of a repeat event. Root fix: don't
  // open the sheet (and steal focus) until that release has genuinely
  // happened — observed globally via HardwareKeyboard, independent of
  // whatever currently has focus.
  void _confirmRemoveAfterRelease(BuildContext context, String room) {
    final selectKeys = Dpad.keySetOf(context).select;
    late bool Function(KeyEvent) handler;
    handler = (KeyEvent event) {
      if (event is KeyUpEvent && selectKeys.contains(event.logicalKey)) {
        HardwareKeyboard.instance.removeHandler(handler);
        _confirmRemove(context, room);
      }
      return false;
    };
    HardwareKeyboard.instance.addHandler(handler);
  }

  void _confirmRemove(BuildContext context, String room) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161A22),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Remove $room?', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                // onLongSelect is set (even though it does the same thing as
                // onSelect) as a guard against the auto-repeat race: a
                // DpadFocusable with no onLongSelect fires onSelect
                // immediately on key-DOWN, not on release. If the physical
                // button from opening this sheet is still held when this
                // button autofocuses, Android's own key-repeat delivers
                // another down event here — with only onSelect wired up,
                // that fires instantly (removed before you see the sheet).
                // With onLongSelect also wired, a down event here just
                // starts *this* widget's own press/timer instead of firing
                // immediately, so it can only resolve on a genuine release.
                DpadFocusable(
                  autofocus: true,
                  onSelect: () {
                    onRemove(room);
                    Navigator.pop(context);
                  },
                  onLongSelect: () {
                    onRemove(room);
                    Navigator.pop(context);
                  },
                  effects: const [DpadTintEffect(opacity: 0.18)],
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 8),
                    child: Text('Remove'),
                  ),
                ),
                DpadFocusable(
                  onSelect: () => Navigator.pop(context),
                  onLongSelect: () => Navigator.pop(context),
                  effects: const [DpadTintEffect(opacity: 0.18)],
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 8),
                    child: Text('Cancel'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// #4/#5: tall cards where the actionable control sits below other content.
// wrapWholeCard=true follows the README's "one DpadFocusable per visual
// unit" best practice; wrapWholeCard=false deliberately reproduces the
// hazard (only the inner button is the focus target, so DpadScroll.
// ensureVisible sizes to the button's own render box, not the card).
// ---------------------------------------------------------------------------

class _TallCardRow extends StatelessWidget {
  const _TallCardRow({required this.wrapWholeCard, this.cardCount = 6});
  final bool wrapWholeCard;
  final int cardCount;

  @override
  Widget build(BuildContext context) {
    return DpadRegion(
      debugLabel: 'tall-cards-${wrapWholeCard ? 'whole' : 'button-only'}',
      child: SizedBox(
        height: 250,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
          itemCount: cardCount,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(right: 20),
            child: wrapWholeCard ? _WholeCardFocusable(index: i) : _ButtonOnlyFocusable(index: i),
          ),
        ),
      ),
    );
  }
}

class _CardChrome extends StatelessWidget {
  const _CardChrome({required this.index, required this.buttonFocused});
  final int index;
  final bool buttonFocused;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      decoration: BoxDecoration(
        color: const Color(0xFF1B2130),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 90, color: Colors.white.withAlpha(20)),
          const SizedBox(height: 8),
          Text('Card $index', style: const TextStyle(fontWeight: FontWeight.w700)),
          const Text('status line', style: TextStyle(color: Colors.white54, fontSize: 12)),
          const Spacer(),
          Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: buttonFocused ? Theme.of(context).colorScheme.primary : Colors.white12,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('Join', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _WholeCardFocusable extends StatefulWidget {
  const _WholeCardFocusable({required this.index});
  final int index;

  @override
  State<_WholeCardFocusable> createState() => _WholeCardFocusableState();
}

class _WholeCardFocusableState extends State<_WholeCardFocusable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return DpadFocusable(
      debugLabel: 'whole-card:${widget.index}',
      onSelect: () {},
      onFocusChange: (f) => setState(() => _focused = f),
      effects: const [DpadBorderEffect()],
      child: _CardChrome(index: widget.index, buttonFocused: _focused),
    );
  }
}

class _ButtonOnlyFocusable extends StatefulWidget {
  const _ButtonOnlyFocusable({required this.index});
  final int index;

  @override
  State<_ButtonOnlyFocusable> createState() => _ButtonOnlyFocusableState();
}

class _ButtonOnlyFocusableState extends State<_ButtonOnlyFocusable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      decoration: BoxDecoration(
        color: const Color(0xFF1B2130),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 90, color: Colors.white.withAlpha(20)),
          const SizedBox(height: 8),
          Text('Card ${widget.index}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const Text('status line', style: TextStyle(color: Colors.white54, fontSize: 12)),
          const Spacer(),
          DpadFocusable(
            debugLabel: 'button-only:${widget.index}',
            onSelect: () {},
            onFocusChange: (f) => setState(() => _focused = f),
            effects: const [DpadBorderEffect()],
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: const Text('Join', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// #6: three sibling buttons in one region; each tap of onFocusChange(true)
// logs a "correction" fire. The bug class was a boolean that only flips
// false->true once — verify moving laterally between B1/B2/B3 repeatedly
// increments every time, not just on first entry to the panel.
// ---------------------------------------------------------------------------

class _CorrectionPanel extends StatelessWidget {
  const _CorrectionPanel({required this.onFire});
  final ValueChanged<String> onFire;

  @override
  Widget build(BuildContext context) {
    return DpadRegion(
      debugLabel: 'correction-panel',
      child: Row(
        children: [
          for (final label in ['B1', 'B2', 'B3'])
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: DpadFocusable(
                debugLabel: 'correction:$label',
                onSelect: () {},
                onFocusChange: (f) {
                  if (f) onFire(label);
                },
                effects: const [DpadGlowEffect()],
                child: Container(
                  width: 90,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B2130),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(label),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// #7: bare TextField next to a sibling button. Per the README this should
// need zero extra wiring — arrows edit mid-text, escape at the caret edge.
// ---------------------------------------------------------------------------

class _SearchRow extends StatelessWidget {
  const _SearchRow({super.key});

  @override
  Widget build(BuildContext context) {
    return DpadRegion(
      debugLabel: 'search-row',
      child: Row(
        children: [
          SizedBox(
            width: 280,
            child: TextField(
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1B2130),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                hintText: 'Search…',
              ),
            ),
          ),
          const SizedBox(width: 16),
          DpadFocusable(
            debugLabel: 'search:filter-button',
            onSelect: () {},
            effects: const [DpadGlowEffect()],
            child: Container(
              width: 90,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF1B2130),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('Filter'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// #8: dropdown menu — Up/Down moves between rows, focus-loss dismisses.
// Verify pressing Down past the last row does nothing (no false dismiss).
// ---------------------------------------------------------------------------

class _MenuDemo extends StatelessWidget {
  const _MenuDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return DpadFocusable(
      debugLabel: 'menu:opener',
      onSelect: () => _openMenu(context),
      effects: const [DpadGlowEffect()],
      child: Container(
        width: 160,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF1B2130),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text('Open menu'),
      ),
    );
  }

  void _openMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161A22),
      builder: (context) {
        return SafeArea(
          child: DpadRegion(
            debugLabel: 'menu-region',
            verticalEdge: DpadEdgeBehavior.stop,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final row in ['Row A', 'Row B', 'Row C', 'Row D'])
                    DpadFocusable(
                      autofocus: row == 'Row A',
                      debugLabel: 'menu:$row',
                      onSelect: () => Navigator.pop(context),
                      effects: const [DpadTintEffect(opacity: 0.18)],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
                        child: Text(row),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// #9: scaled-on-focus card with an image/info seam — inspect pixel-level at
// scale for a fractional-pixel boundary artifact, same bug class as the
// real app's RoomCard GPU-scaling-seam fix.
// ---------------------------------------------------------------------------

class _SeamCard extends StatelessWidget {
  const _SeamCard({super.key});

  @override
  Widget build(BuildContext context) {
    return DpadFocusable(
      debugLabel: 'seam-card',
      onSelect: () {},
      effects: const [DpadScaleEffect(scale: 1.15)],
      child: SizedBox(
        width: 220,
        height: 150,
        child: Column(
          children: [
            Expanded(
              child: Container(color: const Color(0xFF6C8CFF)),
            ),
            Expanded(
              child: Container(color: const Color(0xFF1B2130)),
            ),
          ],
        ),
      ),
    );
  }
}
