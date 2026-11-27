# AntennaPod Database Import

## Overview

Imports podcast subscriptions and already-played episode status directly from an AntennaPod SQLite database backup (`.db`) on Android in a single on-device step, without needing a separate OPML file or external conversion script.

## Source Format (AntennaPod `.db`)

Exported from AntennaPod via **Settings → Import/Export → Database export**. It is a standard SQLite database containing:

- **`Feeds`**
  - `id`: Feed primary key.
  - `title`: Podcast title.
  - `download_url`: RSS feed URL.
  - `state` *(AntennaPod 3.x+)*: `0` = subscribed, `1` = not subscribed, `2` = archived.
- **`FeedItems`**
  - `id`: Episode primary key.
  - `feed`: Foreign key to `Feeds.id`.
  - `item_identifier`: RSS `<guid>` for the episode.
  - `read`: `-1` = new, `0` = unplayed, `1` = played.
- **`FeedMedia`**
  - `feeditem`: Foreign key to `FeedItems.id`.
  - `download_url`: Episode enclosure/audio URL (used as a fallback match key when `item_identifier` is absent or differs).

## Behavior & Rules

### Subscription Filtering
- Only import **active, remote subscriptions**:
  - Skip feeds with null/empty `download_url` or local folder feeds (`download_url` starting with `antennapod_local:`).
  - If the `Feeds.state` column exists (checked via `PRAGMA table_info(Feeds)`), only include rows where `state = 0` (`STATE_SUBSCRIBED`). If the column does not exist (older AntennaPod backups), include all remote feeds.

### Subscription & Played-Status Import Flow
For each eligible AntennaPod feed (sequentially, supporting cancellation):
1. **Check existing subscriptions in Anytime:**
   - Match against currently subscribed podcasts by normalized feed URL (ignoring `http://` vs `https://` scheme differences and trailing slashes).
   - If **already subscribed**, reuse the existing stored podcast and its episodes (preserving existing filter, sort, and `autoDownloadCount` settings).
   - If **not yet subscribed**, fetch the RSS feed via `podcastService.loadPodcast(..., ignoreCache: true)` and subscribe via `podcastService.subscribe(result)`.
2. **Apply played status (`FeedItems.read = 1`):**
   - Build lookup sets for that feed's played episodes from AntennaPod:
     - Primary key: non-empty `item_identifier` matched against `episode.guid`.
     - Fallback key: normalized `FeedMedia.download_url` matched against normalized `episode.contentUrl` (ignoring `http`/`https` scheme differences).
   - For every matched episode where `episode.played == false`, set `episode.played = true`.
   - Persist updated episodes in Sembast via `podcastService.saveEpisodes(updatedEpisodes)`.
   - **Idempotent / non-destructive:** Never un-play an episode that is already marked `played = true` in Anytime, and do not modify `episode.position` (played status only, no in-progress playback positions).
3. **Error handling:**
   - Invalid or unreadable `.db` files (e.g., missing `Feeds` or `FeedItems` tables) abort immediately with a clear error message.
   - Individual RSS feeds that fail to load (e.g., dead or unreachable URLs) are skipped and recorded so the rest of the import continues.

### Auto-Download Interaction
- Imported subscriptions keep Anytime's default `autoDownloadCount` (`5`).
- The import flow **does not** trigger `AutoDownloadService` or `refreshFeeds`.
- Because played status is persisted during the import pass, the next normal refresh (manual or hourly background refresh) will only auto-download genuinely unplayed episodes.

## UI

- **Location:** **Settings → Data** (alongside *Export OPML*; *Import OPML* was removed in favor of *Import from AntennaPod*), labeled **Import from AntennaPod**.
- **Flow:**
  1. Opens `file_picker` (`FileType.any`) to select the AntennaPod `.db` backup file.
  2. Displays a progress dialog (matching the existing `OPMLImport` dialog pattern) showing progress (`X% - <Podcast Title>`) and a **Cancel** button.
  3. On completion, displays a brief summary (e.g., subscriptions imported/matched, episodes marked as played, and any feeds that failed to load) and reloads subscriptions via `PodcastEvent.reloadSubscriptions`.

## Architecture & Implementation Notes

- **Android SQLite Reader (`MainActivity.kt` + Dart `MethodChannel`):**
  - Read the exported `.db` file read-only using Android's built-in `android.database.sqlite.SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READONLY)` via a `MethodChannel` (`uk.me.amugofjava.anytime_podcast_player/antennapod_import`).
  - Avoids adding any new dependency to `pubspec.yaml` while keeping APK size minimal.
  - Note: Handle `file_picker` paths cleanly (on Android, `file_picker` copies content URIs to a readable local cache path accessible to `SQLiteDatabase`).
- **Service & BLoC (`lib/services/podcast/`, `lib/bloc/podcast/`):**
  - Abstract the SQLite reader behind a small Dart interface (`AntennaPodDatabaseReader`) returning typed DTOs (`AntennaPodFeed`, `AntennaPodPlayedItem`) so all matching, URL normalization, subscription, and Sembast update logic is pure Dart and unit-testable with `flutter test`.
  - Follow the existing `OPMLService` / `OPMLBloc` / `OPMLState` pattern (stream of parsing, loading, completed-with-summary, and error states, with cancellation support).
- **Risk Checks:**
  - **Sembast persistence:** Uses existing `PodcastService.subscribe` and `PodcastService.saveEpisodes` APIs; no schema changes to `Podcast` or `Episode`.
  - **Android audio focus:** Unaffected.
  - **Dependencies:** Zero new packages added to `pubspec.yaml`.
