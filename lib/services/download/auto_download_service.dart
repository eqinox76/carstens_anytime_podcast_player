// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/entities/downloadable.dart';
import 'package:anytime/entities/podcast.dart';
import 'package:anytime/repository/repository.dart';
import 'package:anytime/services/download/download_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

/// Service that automatically enqueues downloads for the oldest unplayed,
/// unstarted episodes of each subscribed podcast according to its
/// [Podcast.autoDownloadCount].
class AutoDownloadService {
  static const MethodChannel _powerChannel = MethodChannel('uk.me.amugofjava.anytime_podcast_player/power');

  final _log = Logger('AutoDownloadService');
  final Repository repository;
  final DownloadService downloadService;
  final Future<bool> Function() _isOnWifi;
  final Future<bool> Function() _isPowerSaveMode;

  AutoDownloadService({
    required this.repository,
    required this.downloadService,
    Future<bool> Function()? isOnWifi,
    Future<bool> Function()? isPowerSaveMode,
  })  : _isOnWifi = isOnWifi ?? _defaultIsOnWifi,
        _isPowerSaveMode = isPowerSaveMode ?? _defaultIsPowerSaveMode;

  static Future<bool> _defaultIsOnWifi() async {
    final results = await Connectivity().checkConnectivity();
    return results.contains(ConnectivityResult.wifi);
  }

  static Future<bool> _defaultIsPowerSaveMode() async {
    try {
      return await _powerChannel.invokeMethod<bool>('isPowerSaveMode') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Checks Wi-Fi and Battery Saver constraints, then enqueues missing
  /// auto-downloads for each subscribed podcast.
  ///
  /// Returns the number of episodes newly enqueued for download.
  Future<int> run() async {
    if (!(await _isOnWifi())) {
      _log.fine('Skipping auto-download: not connected to Wi-Fi');
      return 0;
    }

    if (await _isPowerSaveMode()) {
      _log.fine('Skipping auto-download: battery saver mode is active');
      return 0;
    }

    final subs = await repository.subscriptions();
    var enqueued = 0;

    for (final sub in subs) {
      final guid = sub.guid;
      if (sub.autoDownloadCount <= 0 || guid == null || guid.isEmpty) {
        continue;
      }

      final episodes = await repository.findEpisodesByPodcastGuid(
        guid,
        filter: PodcastEpisodeFilter.none,
        sort: PodcastEpisodeSort.earliestFirst,
      );

      final eligible = episodes.where((e) => !e.played && e.position == 0).toList();

      eligible.sort((a, b) {
        final aDate = a.publicationDate;
        final bDate = b.publicationDate;
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return aDate.compareTo(bDate);
      });

      final targets = eligible.take(sub.autoDownloadCount);

      for (final episode in targets) {
        if (episode.downloadState == DownloadState.downloaded ||
            episode.downloadState == DownloadState.downloading ||
            episode.downloadState == DownloadState.queued) {
          continue;
        }

        final contentUrl = episode.contentUrl;
        if (contentUrl == null || contentUrl.isEmpty) {
          continue;
        }

        try {
          final ok = await downloadService.downloadEpisode(episode);
          if (ok) {
            enqueued++;
          }
        } catch (e, s) {
          _log.warning('Failed to enqueue auto-download for episode ${episode.guid}', e, s);
        }
      }
    }

    return enqueued;
  }
}
