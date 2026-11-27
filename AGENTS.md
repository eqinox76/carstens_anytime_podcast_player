# AGENTS.md

## Project & Architecture
- **Base:** Public fork of Anytime Podcast Player (Dart/Flutter, **BSD-3-Clause** license) targeting Android.
- **Stack:** Strictly follow the existing architecture—**BLoC** for state management, **Sembast** for local NoSQL persistence, `audio_service` for background playback, and `podcast_search` for **Podcast Index** and **iTunes** search.

## Core Priorities
- **Minimalism:** Keep code and features minimalistic.
- **Single User:** Specialised for one user.
- **Search & Stability:** Prioritize Android playback stability and fast search across remote directories and local feeds.

## Cloud VM & Build Rules
- **Testing:** Write idiomatic Dart and verify changes with `flutter analyze` and `flutter test`.
- **No APK Builds in VM:** Do **not** install the Android SDK/Gradle or run `flutter build apk` in this Remote Agent environment. GitHub Actions handles APK builds using `PINDEX_KEY` and `PINDEX_SECRET` via `--dart-define`.

## Guardrails
- **Dependencies:** Before adding any package to `pubspec.yaml`, verify it is actively maintained and BSD-3-Clause compatible.
- **Risk Checks:** Explicitly flag any changes that could affect Sembast database persistence or Android audio focus.

## Git & Commits
- **Commit Messages:** Keep commit titles short and put details in the commit description.
- **Scope:** One commit per feature or fix.
- **Pre-Push Review:** Before pushing changes, start a `hydrogen medium` subagent to review the commit, focusing on code style, minimalism, and whether `README.md` needs updating. If significant changes are made as a result of the review, start another review. Always wait for user confirmation after the review before pushing.
