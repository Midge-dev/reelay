import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../kit/text.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

/// Ports ui/common/DigitalClock.kt — ticks to the next minute boundary
/// rather than polling every second. Uses MediaQuery's 24-hour-format flag
/// instead of full locale-aware java.text.DateFormat (not worth adding the
/// intl package for this one label).
class DigitalClock extends StatefulWidget {
  const DigitalClock({super.key});

  @override
  State<DigitalClock> createState() => _DigitalClockState();
}

class _DigitalClockState extends State<DigitalClock> {
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleNextTick();
  }

  void _scheduleNextTick() {
    final msToNextMinute =
        60000 - (DateTime.now().millisecondsSinceEpoch % 60000);
    _timer = Timer(Duration(milliseconds: msToNextMinute), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleNextTick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final use24Hour =
        MediaQuery.maybeOf(context)?.alwaysUse24HourFormat ?? false;
    // Home's clock sits over the hero backdrop, so it gets scrim.chip
    // (DESIGN.md #2: no glyph touches raw artwork).
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppScrims.chip,
        borderRadius: BorderRadius.circular(AppShape.radiusSm.du(context)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md.du(context),
          vertical: AppSpacing.xs.du(context),
        ),
        child: AppText(
          _format(_now, use24Hour),
          style: AppTypography.caption.copyWith(
            fontFeatures: AppTypography.tabular,
          ),
          color: AppColors.inkOnArt,
        ),
      ),
    );
  }

  String _format(DateTime time, bool use24Hour) {
    final minute = time.minute.toString().padLeft(2, '0');
    if (use24Hour) {
      return '${time.hour.toString().padLeft(2, '0')}:$minute';
    }
    final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final period = time.hour < 12 ? 'AM' : 'PM';
    return '$hour12:$minute $period';
  }
}
