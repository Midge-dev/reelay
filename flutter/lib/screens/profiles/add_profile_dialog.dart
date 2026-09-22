import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../focus/back_handler.dart';
import '../../kit/button.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../auth/plex_pin_link_panel.dart';
import '../common/click_to_type_text_field.dart';
import '../common/jellyfin_coming_soon_row.dart';

const _dialogWidth = 800.0;

/// Ports screen 07b — a dialog over the picker, not a new destination.
/// Two names (display, Watch Together) and one Plex sign-in, reusing the
/// same PIN-link panel first-run login uses rather than a second copy of
/// that flow. Jellyfin's slot uses the same disabled treatment it gets
/// everywhere else in this app (see JellyfinComingSoonRow).
class AddProfileDialog extends StatefulWidget {
  final Future<void> Function({
    required String name,
    required String watchTogetherName,
    required String token,
  })
  onCreate;
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
    super.dispose();
  }

  Future<void> _create() async {
    final token = _token;
    if (_name.trim().isEmpty || token == null || _creating) return;
    setState(() => _creating = true);
    await widget.onCreate(
      name: _name.trim(),
      watchTogetherName: _watchTogetherName.trim().isEmpty
          ? _name.trim()
          : _watchTogetherName.trim(),
      token: token,
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountsKicker = _name.trim().isEmpty
        ? 'ACCOUNTS'
        : "${_name.trim().toUpperCase()}'S ACCOUNTS";
    final canCreate = _name.trim().isNotEmpty && _token != null && !_creating;

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
                maxWidth: _dialogWidth,
                maxHeight: MediaQuery.sizeOf(context).height * 0.9,
              ),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.xxxl),
                decoration: BoxDecoration(
                  color: AppColors.surfaceOverlay,
                  borderRadius: BorderRadius.circular(AppShape.radiusLg),
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
                          const AppIcon(
                            Icons.person_add,
                            size: 22,
                            tint: AppColors.accent300,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          const AppText(
                            'NEW PROFILE',
                            style: AppTypography.micro,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const AppText(
                        'Who\'s joining this device?',
                        style: AppTypography.title2,
                      ),
                      const SizedBox(height: AppSpacing.xl),
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
                          const SizedBox(width: AppSpacing.lg),
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
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xl,
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
                      const SizedBox(height: AppSpacing.lg),
                      _PlexAccountRow(
                        name: _name,
                        linking: _linking,
                        linked: _token != null,
                        onSignIn: () => setState(() => _linking = true),
                      ),
                      if (_linking && _token == null)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.lg),
                          child: widget.linkPanelBuilder(
                            (token) => setState(() {
                              _token = token;
                              _linking = false;
                            }),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.md),
                      const JellyfinComingSoonRow(),
                      const SizedBox(height: AppSpacing.xl),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.md,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: const Border(
                            left: BorderSide(
                              color: AppColors.warning,
                              width: 4,
                            ),
                          ),
                          borderRadius: BorderRadius.circular(
                            AppShape.radiusSm,
                          ),
                        ),
                        child: AppText(
                          '${_name.trim().isEmpty ? 'They' : _name.trim()} will see exactly what their own accounts can see. '
                          "Switching profiles is not a lock — it changes whose library is on screen, not who's allowed at the TV.",
                          color: AppColors.ink2,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppButton(
                            onClick: canCreate ? _create : () {},
                            enabled: canCreate,
                            child: const AppText('Create profile'),
                          ),
                          const SizedBox(width: AppSpacing.md),
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
        const SizedBox(height: AppSpacing.sm),
        ClickToTypeTextField(
          value: value,
          onValueChange: onChanged,
          focusNode: focusNode,
        ),
      ],
    );
  }
}

class _PlexAccountRow extends StatelessWidget {
  final String name;
  final bool linking;
  final bool linked;
  final VoidCallback onSignIn;

  const _PlexAccountRow({
    required this.name,
    required this.linking,
    required this.linked,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    final who = name.trim().isEmpty ? 'They' : name.trim();
    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: linked ? AppColors.accent : AppColors.line),
        borderRadius: BorderRadius.circular(AppShape.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AppIcon(
            linked ? Icons.check_circle : Icons.dns,
            size: 26,
            tint: linked ? AppColors.success : AppColors.ink2,
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppText('Plex', style: AppTypography.label),
                const SizedBox(height: 3),
                AppText(
                  linked
                      ? 'Signed in'
                      : '$who signs in with their own Plex account',
                  style: AppTypography.caption,
                  color: AppColors.ink3,
                ),
              ],
            ),
          ),
          if (!linked && !linking)
            AppOutlinedButton(
              compact: true,
              onClick: onSignIn,
              child: const AppText('Sign in'),
            ),
        ],
      ),
    );
  }
}
