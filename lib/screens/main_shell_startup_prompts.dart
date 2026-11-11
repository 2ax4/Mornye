part of 'main_shell.dart';

extension _MainShellStartupPrompts on _MainShellState {
  Future<void> _checkAppAnnouncement() async {
    if (_hasCheckedAppAnnouncement) return;
    _hasCheckedAppAnnouncement = true;

    // Privacy: the announcement check is the app's only phone-home request.
    // It shares the "Check for Updates" switch and never runs when that is
    // off, so the app starts fully offline unless the user opted in.
    if (!ref.read(settingsProvider).checkForUpdates) return;

    final locale = Localizations.localeOf(context).toLanguageTag();
    final remoteConfigService = AppRemoteConfigService();
    final announcement = await remoteConfigService.fetchActiveAnnouncement(
      locale: locale,
    );
    if (announcement == null || !mounted) return;

    showAppAnnouncementDialog(
      context,
      announcement: announcement,
      onDismiss: () {
        remoteConfigService.markAnnouncementDismissed(announcement.id);
      },
    );
  }
}
