import 'package:flutter/widgets.dart';

/// Hand-vendored subset of Phosphor icon glyphs, as plain [IconData] rather
/// than importing `package:phosphor_flutter` — that package's
/// `PhosphorIconData extends IconData`, which no longer compiles on this
/// Flutter SDK (`IconData` became a `final` class). The `phosphor_flutter`
/// dependency in pubspec.yaml is kept anyway, purely so Flutter's asset
/// build picks up its bundled font files (declared in its own pubspec,
/// resolved via `fontPackage` below) — its Dart library is never imported.
/// Codepoints copied from phosphor_flutter 2.1.0's generated icon tables;
/// add more here if a new icon is needed, rather than reaching for the
/// package import.
class PhosphorIconsRegular {
  const PhosphorIconsRegular._();

  static const backspace = IconData(
    0xe0ae,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const arrowRight = IconData(
    0xe06c,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const arrowsClockwise = IconData(
    0xe094,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const deviceMobile = IconData(
    0xe1e0,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const linkSimple = IconData(
    0xe2e6,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const playCircle = IconData(
    0xe3d2,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const palette = IconData(
    0xe6c8,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const info = IconData(
    0xe2ce,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const user = IconData(
    0xe4c2,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const play = IconData(
    0xe3d0,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const check = IconData(
    0xe182,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const dotOutline = IconData(
    0xece0,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );

  static const arrowClockwise = IconData(
    0xe036,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const arrowCounterClockwise = IconData(
    0xe038,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const bookmarkSimple = IconData(
    0xe0ea,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const caretDown = IconData(
    0xe136,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const caretRight = IconData(
    0xe13a,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const caretUp = IconData(
    0xe13c,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const chatCircleText = IconData(
    0xe16e,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const clock = IconData(
    0xe19a,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const cloudSlash = IconData(
    0xe1b6,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const closedCaptioning = IconData(
    0xe1a4,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const fastForward = IconData(
    0xe6a6,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const filmSlate = IconData(
    0xe8c2,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const funnel = IconData(
    0xe266,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const gear = IconData(
    0xe270,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const hardDrives = IconData(
    0xe2a0,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const house = IconData(
    0xe2c2,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const magnifyingGlass = IconData(
    0xe30c,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const minus = IconData(
    0xe32a,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const monitor = IconData(
    0xe32e,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const plus = IconData(
    0xe3d4,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const rewind = IconData(
    0xe6a8,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const televisionSimple = IconData(
    0xeae6,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const userPlus = IconData(
    0xe4d0,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const usersThree = IconData(
    0xe68e,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const warning = IconData(
    0xe4e0,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const x = IconData(
    0xe4f6,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
}

/// See [PhosphorIconsRegular] — same vendoring rationale, Fill weight.
class PhosphorIconsFill {
  const PhosphorIconsFill._();

  static const hardDrives = IconData(
    0xe2a0,
    fontFamily: 'PhosphorFill',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const bookmarkSimple = IconData(
    0xe0ea,
    fontFamily: 'PhosphorFill',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const checkCircle = IconData(
    0xe184,
    fontFamily: 'PhosphorFill',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const filmSlate = IconData(
    0xe8c2,
    fontFamily: 'PhosphorFill',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const gear = IconData(
    0xe270,
    fontFamily: 'PhosphorFill',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const house = IconData(
    0xe2c2,
    fontFamily: 'PhosphorFill',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const magnifyingGlass = IconData(
    0xe30c,
    fontFamily: 'PhosphorFill',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const pause = IconData(
    0xe39e,
    fontFamily: 'PhosphorFill',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const play = IconData(
    0xe3d0,
    fontFamily: 'PhosphorFill',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const televisionSimple = IconData(
    0xeae6,
    fontFamily: 'PhosphorFill',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
  static const usersThree = IconData(
    0xe68e,
    fontFamily: 'PhosphorFill',
    fontPackage: 'phosphor_flutter',
    matchTextDirection: true,
  );
}
