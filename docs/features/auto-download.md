# Per-Subscription Auto-Download

## Overview

Automatically downloads the oldest unplayed, unstarted `X` episodes for each subscribed podcast so episodes are ready for offline listening without manual intervention.

## Behavior & Rules

### Per-Subscription Count (`X`)
- **Default:** `5` episodes for every subscribed podcast (existing and newly subscribed).
- **Override:** Can be set per subscription to `0` (off) or any positive number (e.g., `3` for one podcast, `5` for another).
- **No global setting:** There is no global auto-download toggle or global default UI in Settings.

### Episode Selection
For each subscribed podcast with `autoDownloadCount > 0`:
1. Filter episodes to **unplayed and unstarted** only (`!episode.played && episode.position == 0`).
   - Partially played episodes (`position > 0`) do **not** count toward `X`.
2. Sort eligible episodes **oldest first** (`publicationDate` ascending).
3. Take the first `X` episodes.
4. For each of those `X` episodes:
   - Skip if already downloaded (`DownloadState.downloaded`), currently downloading (`DownloadState.downloading`), or queued (`DownloadState.queued`).
   - Otherwise, enqueue for download via `DownloadService.downloadEpisode`.

### Deleted Episodes & Cleanup
- **Deleted episodes:** Marked as played so they are not re-downloaded on subsequent runs (`markDeletedEpisodesAsPlayed` defaults to `true`, and deleting an episode from a subscription with auto-download enabled marks it as played).
- **No cleanup:** This feature only tops up missing downloads up to `X`. It does not delete excess downloads (e.g., if `X` is lowered from `5` to `3`). Automatic deletion of played episodes remains handled by the existing *Delete played episodes* setting.

### Scheduling & Constraints
- **Combined with feed refresh:** Runs as part of the normal refresh flow (`MobilePodcastService.refreshFeeds`), both on the **hourly** background refresh (`BackgroundFetchConfig`, keeping the current `stopOnTerminate: true` and `enableHeadless: false` behavior) and on **manual** refresh.
- **Wi-Fi only:** Auto-download strictly requires an active Wi-Fi connection (`ConnectivityResult.wifi`). If *Background refresh on mobile data* is enabled, RSS feeds may still refresh over mobile data, but auto-download is skipped until on Wi-Fi.
- **Battery & Battery Saver:**
  - Uses Android's standard `requiresBatteryNotLow: true` constraint on background fetch.
  - Checks Android Battery Saver mode (`PowerManager.isPowerSaveMode`) before enqueuing downloads; skips auto-download when Battery Saver is active.

## UI

- **Location:** 3-dot overflow menu (`PodcastContextMenu`) on the `PodcastDetails` screen (enabled only when subscribed).
- **Control:** Opens a simple dialog/bottom sheet showing the current value (default `5`, `0` = Off) with a `+/-` stepper to adjust `X` for that subscription.

## Architecture & Implementation Notes

- **Entity & Persistence (`lib/entities/podcast.dart`, Sembast):**
  - Add `int autoDownloadCount` to `Podcast` (default `5`).
  - Persist `autoDownloadCount` in `Podcast.toMap()` and read it in `Podcast.fromMap()` with a fallback to `5` when absent so existing Sembast records remain backwards-compatible.
- **BLoC (`lib/bloc/podcast/podcast_bloc.dart`):**
  - Add an event/method to update `podcast.autoDownloadCount` and persist via `podcastService.save(podcast, withEpisodes: false)`.
- **Refresh & Download Integration (`lib/services/podcast/mobile_podcast_service.dart`, `lib/services/download/mobile_download_service.dart`):**
  - After refreshing feeds in `refreshFeeds`, check Wi-Fi connectivity and Battery Saver state, then enqueue missing episodes for each subscription.
  - Enqueueing via `flutter_downloader` is asynchronous, so the background refresh task only needs time to enqueue tasks rather than wait for downloads to finish.
- **Risk Checks:**
  - **Sembast persistence:** Additive field with default fallback (`5`); no destructive migration required.
  - **Android audio focus:** Unaffected.
  - **Dependencies:** Checking Android Battery Saver mode can be done via a small platform `MethodChannel` to `PowerManager.isPowerSaveMode` (avoids adding a new dependency).
