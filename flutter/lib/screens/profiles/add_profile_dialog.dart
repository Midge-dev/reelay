import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../data/jellyfin/jellyfin_auth_api.dart';
import '../../theme/phosphor_icons.dart';

import '../../focus/back_handler.dart';
import '../../kit/button.dart';
import '../../kit/surface_style.dart';
import '../../kit/card.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../auth/plex_pin_link_panel.dart';
import '../common/click_to_type_text_field.dart';
import '../onboarding/jellyfin_link_step.dart';

const _dialogWidth = 800.0;

/// Making a profile from 07b: its names and whichever accounts it signed
/// in with — Plex, Jellyfin or both, never neither.
typedef CreateProfile = Future<void> Function({
  required String name,
  required String watchTogetherName,
  String? token,
  (JellyfinServerInfo, JellyfinSession)? jellyfin,
});

/// Ports screen 07b — a dialog over the picker, not a new destination.
/// Two names (display, Watch Together) and one sign-in per platform,
/// reusing setup's own flows rather than second copies: Plex's PIN-link
/// panel inline, and Jellyfin's O3/O3b over the whole screen, since it
/// doesn't fit in the dialog.
class AddProfileDialog extends StatefulWidget {
  final CreateProfile onCreate;
  final VoidCallback onCancel;
  // Defaults to the real Plex sign-in flow; overridable so tests can drive
  // the "signed in" state without a real PIN-link network round trip.
  final Widget Function(ValueChanged<String> onLinked) linkPanelBuilder;

  AddProfileDialog({
    super.key,
    required this.onCreate,
    required this.onCancel,
    Widget Function(ValueChanged<String> onLinked)? linkPanelBuilder,
  }) : linkPanelBuilder =
           linkPanelBuilder ??
           ((onLinked) => PlexPinLinkPanel(onLinked: onLinked));

  @override
  State<AddProfileDialog> createState() => _AddProfileDialogState();
}

class _AddProfileDialogState extends State<AddProfileDialog> {
  final _nameFocus = FocusNode(debugLabel: 'add-profile-name');
  String _name = '';
  String _watchTogetherName = '';
  bool _linking = false;
  String? _token;
  bool _linkingJellyfin = false;
  (JellyfinServerInfo, JellyfinSession)? _jellyfin;
  final _jellyfinSignInFocus = FocusNode(debugLabel: 'add-profile-jellyfin');
  final _createFocus = FocusNode(debugLabel: 'add-profile-create');
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _nameFocus.requestFocus(),
    );
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _jellyfinSignInFocus.dispose();
    _createFocus.dispose();
    super.dispose();
  }

  bool get _hasAccount => _token != null || _jellyfin != null;

  void _closeJellyfin() {
    setState(() => _linkingJellyfin = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _jellyfinSignInFocus.requestFocus();
    });
  }

  Future<void> _create() async {
    if (_name.trim().isEmpty || !_hasAccount || _creating) return;
    setState(() => _creating = true);
    await widget.onCreate(
      name: _name.trim(),
      watchTogetherName: _watchTogetherName.trim().isEmpty
          ? _name.trim()
          : _watchTogetherName.trim(),
      token: _token,
      jellyfin: _jellyfin,
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountsKicker = _name.trim().isEmpty
        ? 'ACCOUNTS'
        : "${_name.trim().toUpperCase()}'S ACCOUNTS";
    final canCreate = _name.trim().isNotEmpty && _hasAccount && !_creating;

    if (_linkingJellyfin) {
      return Positioned.fill(
        child: JellyfinLinkStep(
          kicker: _name.trim().isEmpty
              ? 'NEW PROFILE · JELLYFIN'
              : 'NEW PROFILE · ${_name.trim().toUpperCase()} · JELLYFIN',
          showSteps: false,
          onBack: _closeJellyfin,
          onLinked: (server, session) {
            _jellyfin = (server, session);
            _closeJellyfin();
          },
        ),
      );
    }

    return Positioned.fill(
      child: ColoredBox(
        color: AppScrims.dialog,
        child: Center(
          child: BackHandler(
            onBack: widget.onCancel,
            child: ConstrainedBox(
              // maxHeight, not just maxWidth — two account rows plus the
              // info box and buttons can exceed the screen height at this
              // padding; scrolls internally rather than overflowing.
              constraints: BoxConstraints(
                maxWidth: _dialogWidth.du(context),
                maxHeight: MediaQuery.sizeOf(context).height * 0.9,
              ),
              child: Container(
                padding: EdgeInsets.all(AppSpacing.xxxl.du(context)),
                decoration: BoxDecoration(
                  color: AppColors.surfaceOverlay,
                  borderRadius: BorderRadius.circular(
                    AppShape.radiusLg.du(context),
                  ),
                  border: Border.all(color: AppColors.lineStrong),
                  boxShadow: AppElevation.overlay,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(
                            PhosphorIconsRegular.userPlus,
                            size: 22,
                            tint: AppColors.accent300,
                          ),
                          SizedBox(width: AppSpacing.md.du(context)),
                          AppText('NEW PROFILE', style: AppTypography.micro),
                        ],
                      ),
                      SizedBox(height: AppSpacing.lg.du(context)),
                      AppText(
                        'Who\'s joining this device?',
                        style: AppTypography.title2,
                      ),
                      SizedBox(height: AppSpacing.xl.du(context)),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _LabeledField(
                              label: 'Name',
                              value: _name,
                              focusNode: _nameFocus,
                              onChanged: (v) => setState(() => _name = v),
                            ),
                          ),
                          SizedBox(width: AppSpacing.lg.du(context)),
                          Expanded(
                            child: _LabeledField(
                              label: 'Name in Watch Together',
                              value: _watchTogetherName,
                              onChanged: (v) =>
                                  setState(() => _watchTogetherName = v),
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: AppSpacing.xl.du(context),
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: AppColors.lineStrong),
                            ),
                          ),
                        ),
                      ),
                      AppText(accountsKicker, style: AppTypography.micro),
                      SizedBox(height: AppSpacing.lg.du(context)),
                      _AccountRow(
                        platform: 'Plex',
                        name: _name,
                        linking: _linking,
                        signedIn: _token != null ? 'Signed in' : null,
                        onSignIn: () => setState(() {
                          _token = null;
                          _linking = true;
                        }),
                      ),
                      if (_linking && _token == null)
                        Padding(
                          padding: EdgeInsets.only(
                            top: AppSpacing.lg.du(context),
                          ),
                          child: widget.linkPanelBuilder(
                            (token) => setState(() {
                              _token = token;
                              _linking = false;
                            }),
                          ),
                        ),
                      SizedBox(height: AppSpacing.md.du(context)),
                      // Down from the last account is Create profile once
                      // it's ready — Cancel sat nearer and took the press.
                      Focus(
                        canRequestFocus: false,
                        skipTraversal: true,
                        onKeyEvent: (_, event) {
                          if (event is! KeyDownEvent ||
                              event.logicalKey !=
                                  LogicalKeyboardKey.arrowDown ||
                              !canCreate) {
                            return KeyEventResult.ignored;
                          }
                          _createFocus.requestFocus();
                          return KeyEventResult.handled;
                        },
                        child: _AccountRow(
                          platform: 'Jellyfin',
                          name: _name,
                          signedIn: switch (_jellyfin) {
                            (final server, final session) =>
                              'Signed in to ${server.name} as ${session.userName}',
                            null => null,
                          },
                          focusNode: _jellyfinSignInFocus,
                          onSignIn: () =>
                              setState(() => _linkingJellyfin = true),
                        ),
                      ),
                      SizedBox(height: AppSpacing.xl.du(context)),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg.du(context),
                          vertical: AppSpacing.md.du(context),
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border(
                            left: BorderSide(
                              color: AppColors.warning,
                              width: 4.du(context),
                            ),
                          ),
                          borderRadius: BorderRadius.circular(
                            AppShape.radiusSm.du(context),
                          ),
                        ),
                        child: AppText(
                          '${_name.trim().isEmpty ? 'They' : _name.trim()} will see exactly what their own accounts can see. '
                          "Switching profiles is not a lock — it changes whose library is on screen, not who's allowed at the TV.",
                          color: AppColors.ink2,
                        ),
                      ),
                      SizedBox(height: AppSpacing.xl.du(context)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppButton(
                            onClick: canCreate ? _create : () {},
                            focusNode: _createFocus,
                            enabled: canCreate,
                            child: const AppText('Create profile'),
                          ),
                          SizedBox(width: AppSpacing.md.du(context)),
                          AppOutlinedButton(
                            onClick: widget.onCancel,
                            child: const AppText('Cancel'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final String value;
  final FocusNode? focusNode;
  final ValueChanged<String> onChanged;

  const _LabeledField({
    required this.label,
    required this.value,
    this.focusNode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppText(label, color: AppColors.ink3),
        SizedBox(height: AppSpacing.sm.du(context)),
        ClickToTypeTextField(
          value: value,
          onValueChange: onChanged,
          focusNode: focusNode,
        ),
      ],
    );
  }
}

SurfaceBorder get _accountBorder => SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

/// One platform's sign-in in 07b. The whole row is the focus target — a
/// small button at its far edge sat outside the column the D-pad moves
/// down, so neither could be reached from the name fields. Signed in, it
/// stays live as Change, so focus has somewhere to come back to.
class _AccountRow extends StatelessWidget {
  final String platform;
  final String name;

  /// "Signed in to Loft as sam"; null until signed in.
  final String? signedIn;

  /// Plex's PIN panel is open below the row.
  final bool linking;
  final FocusNode? focusNode;
  final VoidCallback onSignIn;

  const _AccountRow({
    required this.platform,
    required this.name,
    required this.signedIn,
    this.linking = false,
    this.focusNode,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    final who = name.trim().isEmpty
        ? 'They sign in'
        : '${name.trim()} signs in';
    final linked = signedIn != null;
    return AppCard(
      onClick: onSignIn,
      enabled: !linking,
      focusNode: focusNode,
      border: _accountBorder,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 96.du(context)),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.xl.du(context),
            vertical: AppSpacing.md.du(context),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppIcon(
                linked
                    ? PhosphorIconsFill.checkCircle
                    : PhosphorIconsRegular.hardDrives,
                size: 26,
                tint: linked ? AppColors.success : AppColors.ink2,
              ),
              SizedBox(width: AppSpacing.lg.du(context)),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(platform, style: AppTypography.label),
                    SizedBox(height: 3.du(context)),
                    AppText(
                      signedIn ?? '$who with their own $platform account',
                      style: AppTypography.caption,
                      color: AppColors.ink3,
                    ),
                  ],
                ),
              ),
              if (!linking)
                AppText(
                  linked ? 'Change' : 'Sign in',
                  style: AppTypography.label,
                  color: AppColors.accent300,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
