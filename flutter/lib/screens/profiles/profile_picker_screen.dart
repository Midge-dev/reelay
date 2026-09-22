import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../data/settings/app_settings.dart';
import '../../kit/card.dart';
import '../../kit/icon.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import 'add_profile_dialog.dart';

const _avatarSize = 190.0;
const _itemWidth = 230.0;
const _itemGap = 56.0;

/// Ports screen 07 — first screen after launch, and only once a second
/// profile exists (AppRootController.start() never shows this for a
/// single-profile household). No rail, no rows — nothing but the choice.
class ProfilePickerScreen extends StatefulWidget {
  final List<Profile> profiles;
  final ValueChanged<Profile> onSelectProfile;
  final Future<void> Function({required String name, required String watchTogetherName, required String token}) onAddProfile;
  // Forwarded to AddProfileDialog — see its own doc comment.
  final Widget Function(ValueChanged<String> onLinked)? linkPanelBuilder;

  const ProfilePickerScreen({
    super.key,
    required this.profiles,
    required this.onSelectProfile,
    required this.onAddProfile,
    this.linkPanelBuilder,
  });

  @override
  State<ProfilePickerScreen> createState() => _ProfilePickerScreenState();
}

class _ProfilePickerScreenState extends State<ProfilePickerScreen> {
  final _firstFocus = FocusNode(debugLabel: 'profile-picker-first');
  bool _showingAddDialog = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstFocus.requestFocus());
  }

  @override
  void dispose() {
    _firstFocus.dispose();
    super.dispose();
  }

  Future<void> _addProfile({required String name, required String watchTogetherName, required String token}) async {
    await widget.onAddProfile(name: name, watchTogetherName: watchTogetherName, token: token);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.canvas,
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppText('Reelay', style: AppTypography.title2, color: AppColors.ink3),
                    const SizedBox(height: AppSpacing.md),
                    const AppText("Who's watching?", style: AppTypography.title1),
                  ],
                ),
                const SizedBox(height: 72),
                Wrap(
                  spacing: _itemGap,
                  runSpacing: _itemGap,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final (index, profile) in widget.profiles.indexed)
                      _ProfileItem(
                        profile: profile,
                        focusNode: index == 0 ? _firstFocus : null,
                        onClick: () => widget.onSelectProfile(profile),
                      ),
                    _AddProfileItem(onClick: () => setState(() => _showingAddDialog = true)),
                  ],
                ),
                const SizedBox(height: 40),
                const AppText(
                  'Each profile sees only what its own accounts can reach',
                  color: AppColors.ink3,
                ),
              ],
            ),
          ),
          if (_showingAddDialog)
            AddProfileDialog(
              onCreate: _addProfile,
              onCancel: () => setState(() => _showingAddDialog = false),
              linkPanelBuilder: widget.linkPanelBuilder,
            ),
        ],
      ),
    );
  }
}

class _ProfileItem extends StatefulWidget {
  final Profile profile;
  final FocusNode? focusNode;
  final VoidCallback onClick;

  const _ProfileItem({required this.profile, this.focusNode, required this.onClick});

  @override
  State<_ProfileItem> createState() => _ProfileItemState();
}

class _ProfileItemState extends State<_ProfileItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final thumb = profile.thumb;
    return SizedBox(
      width: _itemWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: _avatarSize,
            height: _avatarSize,
            child: AppCard(
              onClick: widget.onClick,
              focusNode: widget.focusNode,
              shape: const CircleBorder(),
              onFocusChange: (focused) => setState(() => _focused = focused),
              child: thumb != null
                  ? ClipOval(child: Image.network(thumb, fit: BoxFit.cover, width: _avatarSize, height: _avatarSize))
                  : ColoredBox(
                      color: AppColors.surface,
                      child: Center(
                        child: AppText(
                          profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                          style: AppTypography.display,
                          color: AppColors.inkOnArt,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppText(
            profile.name,
            style: _focused ? AppTypography.title2 : AppTypography.title2.copyWith(fontWeight: FontWeight.w400),
            color: _focused ? AppColors.ink : AppColors.ink2,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppText('Plex · ${profile.plexUsername}', color: AppColors.ink3),
        ],
      ),
    );
  }
}

class _AddProfileItem extends StatelessWidget {
  final VoidCallback onClick;

  const _AddProfileItem({required this.onClick});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _itemWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: _avatarSize,
            height: _avatarSize,
            child: AppCard(
              onClick: onClick,
              shape: const CircleBorder(),
              colors: SurfaceColors(
                container: AppColors.transparent,
                content: AppColors.ink3,
                focusedContainer: AppColors.surfaceRaised,
                focusedContent: AppColors.ink,
              ),
              child: const Center(child: AppIcon(Icons.add, size: 44)),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const AppText('Add', color: AppColors.ink3),
        ],
      ),
    );
  }
}
