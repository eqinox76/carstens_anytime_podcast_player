# Carsten's Anytime Podcast Player

This is a **highly customised personal fork** of [Anytime Podcast Player](https://github.com/amugofjava/anytime_podcast_player), tailored specifically for Carsten Rietz's (`eqinox76`) personal preferences on Android.

Because this fork is built for a single user, features and defaults are opinionated and may diverge significantly from upstream Anytime Podcast Player.

## Key Customisations

- **Per-subscription auto-download:** Automatically downloads the oldest unplayed episodes per subscription on Wi-Fi (respecting Android Battery Saver).
- **AntennaPod database import:** Imports subscriptions and played episode history directly from an AntennaPod SQLite `.db` backup (see [docs/features/antennapod-import.md](docs/features/antennapod-import.md)).
- **Automated Android releases:** GitHub Actions builds and publishes signed `arm64` release APKs directly to [GitHub Releases](https://github.com/eqinox76/carstens_anytime_podcast_player/releases) for direct installation or updates via Obtainium.

## Building & Testing

```bash
flutter pub get
flutter test
```

To enable Podcast Index search in local builds, pass your API credentials via `--dart-define`:

```bash
flutter run --dart-define=PINDEX_KEY=mykey --dart-define=PINDEX_SECRET=mysecret
```

## Credits & License

Originally created by Ben Hills as [Anytime Podcast Player](https://github.com/amugofjava/anytime_podcast_player).
Maintained as a personal fork by Carsten Rietz (`eqinox76`).

Licensed under the **BSD-3-Clause** license. See [LICENSE](LICENSE) for details.
