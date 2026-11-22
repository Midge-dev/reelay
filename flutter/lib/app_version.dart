/// The version Reelay reports — in Settings, and to Jellyfin servers, which
/// list it under Dashboard → Devices. The same name the Play Store shows:
/// CI builds it from pubspec.yaml's major.minor and the Play build number
/// (`0.4.124`) and passes it in with `--dart-define=APP_VERSION=…` (see
/// .github/workflows/deploy-play-store.yml). A local build says it's one.
const appVersionName = String.fromEnvironment('APP_VERSION', defaultValue: '0.4-dev');
