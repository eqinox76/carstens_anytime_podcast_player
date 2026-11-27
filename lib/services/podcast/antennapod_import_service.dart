// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/entities/episode.dart';
import 'package:anytime/entities/podcast.dart';
import 'package:anytime/repository/repository.dart';
import 'package:anytime/services/podcast/antennapod_database_reader.dart';
import 'package:anytime/services/podcast/podcast_service.dart';
import 'package:anytime/state/antennapod_import_state.dart';
import 'package:logging/logging.dart';

/// Normalizes a podcast feed or media URL for comparison by trimming whitespace,
/// stripping `http://` or `https://` case-insensitively, lowercasing the host,
/// and removing trailing slashes.
String normalizePodcastUrl(String url) {
  var normalized = url.trim().replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
  final separatorIndex = normalized.indexOf(RegExp(r'[/?#]'));
  if (separatorIndex == -1) {
    normalized = normalized.toLowerCase();
  } else {
    normalized = normalized.substring(0, separatorIndex).toLowerCase() + normalized.substring(separatorIndex);
  }
  return normalized.replaceFirst(RegExp(r'/+$'), '');
}

/// Handles importing podcast subscriptions and played episode state from
/// an AntennaPod SQLite database backup.
abstract class AntennaPodImportService {
  Stream<AntennaPodImportState> importDatabase(String file);

  void cancel();
}

class MobileAntennaPodImportService extends AntennaPodImportService {
  final log = Logger('MobileAntennaPodImportService');
  var _process = false;

  final AntennaPodDatabaseReader databaseReader;
  final PodcastService podcastService;
  final Repository repository;

  MobileAntennaPodImportService({
    required this.databaseReader,
    required this.podcastService,
    required this.repository,
  });

  @override
  Stream<AntennaPodImportState> importDatabase(String file) async* {
    yield AntennaPodImportParsingState();

    _process = true;

    final List<AntennaPodFeed> feeds;
    try {
      feeds = await databaseReader.readDatabase(file);
    } on AntennaPodImportException catch (e) {
      yield AntennaPodImportErrorState(message: e.message);
      return;
    } catch (e) {
      log.warning('Failed to read AntennaPod database', e);
      yield AntennaPodImportErrorState(message: e.toString());
      return;
    }

    if (!_process) {
      yield AntennaPodImportCompletedState(
        subscriptionsImported: 0,
        subscriptionsMatched: 0,
        episodesMarkedPlayed: 0,
        failedFeeds: const <String>[],
        cancelled: true,
      );
      return;
    }

    final existingSubscriptions = await podcastService.subscriptions();
    final subscriptionsByUrl = <String, Podcast>{
      for (final sub in existingSubscriptions) normalizePodcastUrl(sub.url): sub,
    };

    var subscriptionsImported = 0;
    var subscriptionsMatched = 0;
    var episodesMarkedPlayed = 0;
    final failedFeeds = <String>[];
    final total = feeds.length;
    var current = 0;

    for (final feed in feeds) {
      if (!_process) {
        break;
      }

      yield AntennaPodImportLoadingState(
        current: ++current,
        total: total,
        podcast: feed.title,
      );

      final normalizedFeedUrl = normalizePodcastUrl(feed.feedUrl);
      final existing = subscriptionsByUrl[normalizedFeedUrl];
      List<Episode> episodes;

      if (existing != null) {
        subscriptionsMatched++;
        if (existing.guid != null && existing.guid!.isNotEmpty) {
          episodes = await repository.findEpisodesByPodcastGuid(existing.guid!);
        } else {
          episodes = existing.episodes;
        }
      } else {
        try {
          log.fine('Importing podcast ${feed.feedUrl}');

          final loaded = await podcastService.loadPodcast(
            podcast: Podcast(
              guid: '',
              link: '',
              title: feed.title,
              url: feed.feedUrl,
            ),
            ignoreCache: true,
          );

          if (loaded == null) {
            failedFeeds.add(feed.title.isNotEmpty ? feed.title : feed.feedUrl);
            continue;
          }

          final subscribed = await podcastService.subscribe(loaded);
          if (subscribed == null) {
            failedFeeds.add(feed.title.isNotEmpty ? feed.title : feed.feedUrl);
            continue;
          }

          subscriptionsImported++;
          subscriptionsByUrl[normalizedFeedUrl] = subscribed;
          episodes = subscribed.episodes;
        } catch (e) {
          log.fine('Failed to load podcast ${feed.feedUrl}', e);
          failedFeeds.add(feed.title.isNotEmpty ? feed.title : feed.feedUrl);
          continue;
        }
      }

      if (feed.playedItems.isEmpty || episodes.isEmpty) {
        continue;
      }

      final playedGuids = <String>{};
      final playedMediaUrls = <String>{};

      for (final item in feed.playedItems) {
        final guid = item.guid;
        if (guid != null && guid.isNotEmpty) {
          playedGuids.add(guid);
        }
        final mediaUrl = item.mediaUrl;
        if (mediaUrl != null && mediaUrl.isNotEmpty) {
          playedMediaUrls.add(normalizePodcastUrl(mediaUrl));
        }
      }

      final updatedEpisodes = <Episode>[];
      for (final episode in episodes) {
        if (!episode.played) {
          final matchedByGuid = playedGuids.contains(episode.guid);
          final matchedByMediaUrl = episode.contentUrl != null &&
              episode.contentUrl!.isNotEmpty &&
              playedMediaUrls.contains(normalizePodcastUrl(episode.contentUrl!));

          if (matchedByGuid || matchedByMediaUrl) {
            episode.played = true;
            updatedEpisodes.add(episode);
          }
        }
      }

      if (updatedEpisodes.isNotEmpty) {
        await podcastService.saveEpisodes(updatedEpisodes);
        episodesMarkedPlayed += updatedEpisodes.length;
      }
    }

    yield AntennaPodImportCompletedState(
      subscriptionsImported: subscriptionsImported,
      subscriptionsMatched: subscriptionsMatched,
      episodesMarkedPlayed: episodesMarkedPlayed,
      failedFeeds: failedFeeds,
      cancelled: !_process,
    );
  }

  @override
  void cancel() {
    _process = false;
  }
}
