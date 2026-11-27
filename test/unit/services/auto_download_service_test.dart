// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/entities/downloadable.dart';
import 'package:anytime/entities/episode.dart';
import 'package:anytime/entities/podcast.dart';
import 'package:anytime/repository/repository.dart';
import 'package:anytime/services/download/auto_download_service.dart';
import 'package:anytime/services/download/download_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepository implements Repository {
  final List<Podcast> _subscriptions;
  final Map<String, List<Episode>> _episodesByPodcast;
  final List<Episode> deletedEpisodes = <Episode>[];

  _FakeRepository({
    List<Podcast>? subscriptions,
    Map<String, List<Episode>>? episodesByPodcast,
  })  : _subscriptions = subscriptions ?? <Podcast>[],
        _episodesByPodcast = episodesByPodcast ?? <String, List<Episode>>{};

  @override
  Future<List<Podcast>> subscriptions() async => _subscriptions;

  @override
  Future<List<Episode>> findEpisodesByPodcastGuid(
    String pguid, {
    PodcastEpisodeFilter filter = PodcastEpisodeFilter.none,
    PodcastEpisodeSort sort = PodcastEpisodeSort.none,
  }) async {
    return List<Episode>.from(_episodesByPodcast[pguid] ?? const <Episode>[]);
  }

  @override
  Future<void> deleteEpisode(Episode episode) async {
    deletedEpisodes.add(episode);
  }

  @override
  Future<void> deleteEpisodes(List<Episode> episodes) async {
    deletedEpisodes.addAll(episodes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDownloadService implements DownloadService {
  final List<Episode> downloaded = <Episode>[];
  final Set<String> failingGuids;

  _FakeDownloadService({this.failingGuids = const <String>{}});

  @override
  Future<bool> downloadEpisode(Episode episode) async {
    if (failingGuids.contains(episode.guid)) {
      throw Exception('download failed');
    }
    downloaded.add(episode);
    return true;
  }

  @override
  Future<Episode?> findEpisodeByTaskId(String taskId) async => null;

  @override
  void dispose() {}
}

Podcast _makePodcast(String guid, {int autoDownloadCount = Podcast.defaultAutoDownloadCount}) {
  return Podcast(
    guid: guid,
    url: 'https://example.com/$guid.rss',
    link: 'https://example.com/$guid',
    title: 'Podcast $guid',
    autoDownloadCount: autoDownloadCount,
  );
}

Episode _makeEpisode(
  String guid,
  String pguid, {
  DateTime? publicationDate,
  bool played = false,
  int position = 0,
  DownloadState downloadState = DownloadState.none,
  String? contentUrl = 'https://example.com/audio.mp3',
}) {
  return Episode(
    guid: guid,
    pguid: pguid,
    podcast: 'Podcast $pguid',
    title: 'Episode $guid',
    publicationDate: publicationDate,
    played: played,
    position: position,
    downloadState: downloadState,
    contentUrl: contentUrl,
  );
}

void main() {
  group('AutoDownloadService', () {
    test('skips when not on Wi-Fi', () async {
      final repo = _FakeRepository(
        subscriptions: [_makePodcast('p1', autoDownloadCount: 3)],
        episodesByPodcast: {
          'p1': [
            _makeEpisode('e1', 'p1', publicationDate: DateTime(2024, 1, 1)),
          ],
        },
      );
      final downloads = _FakeDownloadService();
      final service = AutoDownloadService(
        repository: repo,
        downloadService: downloads,
        isOnWifi: () async => false,
        isPowerSaveMode: () async => false,
      );

      final count = await service.run();

      expect(count, 0);
      expect(downloads.downloaded, isEmpty);
    });

    test('skips when in Battery Saver mode', () async {
      final repo = _FakeRepository(
        subscriptions: [_makePodcast('p1', autoDownloadCount: 3)],
        episodesByPodcast: {
          'p1': [
            _makeEpisode('e1', 'p1', publicationDate: DateTime(2024, 1, 1)),
          ],
        },
      );
      final downloads = _FakeDownloadService();
      final service = AutoDownloadService(
        repository: repo,
        downloadService: downloads,
        isOnWifi: () async => true,
        isPowerSaveMode: () async => true,
      );

      final count = await service.run();

      expect(count, 0);
      expect(downloads.downloaded, isEmpty);
    });

    test('skips subscriptions with autoDownloadCount == 0', () async {
      final repo = _FakeRepository(
        subscriptions: [_makePodcast('p1', autoDownloadCount: 0)],
        episodesByPodcast: {
          'p1': [
            _makeEpisode('e1', 'p1', publicationDate: DateTime(2024, 1, 1)),
            _makeEpisode('e2', 'p1', publicationDate: DateTime(2024, 1, 2)),
          ],
        },
      );
      final downloads = _FakeDownloadService();
      final service = AutoDownloadService(
        repository: repo,
        downloadService: downloads,
        isOnWifi: () async => true,
        isPowerSaveMode: () async => false,
      );

      final count = await service.run();

      expect(count, 0);
      expect(downloads.downloaded, isEmpty);
    });

    test('downloads oldest X unplayed, unstarted episodes', () async {
      final repo = _FakeRepository(
        subscriptions: [_makePodcast('p1', autoDownloadCount: 2)],
        episodesByPodcast: {
          'p1': [
            // Intentionally unsorted, including a played episode and a null publicationDate
            _makeEpisode('e4', 'p1', publicationDate: DateTime(2024, 1, 4)),
            _makeEpisode('e_null', 'p1', publicationDate: null),
            _makeEpisode('e1_played', 'p1', publicationDate: DateTime(2024, 1, 1), played: true),
            _makeEpisode('e3', 'p1', publicationDate: DateTime(2024, 1, 3)),
            _makeEpisode('e2', 'p1', publicationDate: DateTime(2024, 1, 2)),
          ],
        },
      );
      final downloads = _FakeDownloadService();
      final service = AutoDownloadService(
        repository: repo,
        downloadService: downloads,
        isOnWifi: () async => true,
        isPowerSaveMode: () async => false,
      );

      final count = await service.run();

      expect(count, 2);
      expect(downloads.downloaded.map((e) => e.guid).toList(), ['e2', 'e3']);
    });

    test('partially played episodes (position > 0) do not count toward X and are not downloaded', () async {
      final repo = _FakeRepository(
        subscriptions: [_makePodcast('p1', autoDownloadCount: 2)],
        episodesByPodcast: {
          'p1': [
            _makeEpisode('e1_partial', 'p1', publicationDate: DateTime(2024, 1, 1), position: 15000),
            _makeEpisode('e2', 'p1', publicationDate: DateTime(2024, 1, 2)),
            _makeEpisode('e3_partial', 'p1', publicationDate: DateTime(2024, 1, 3), position: 500),
            _makeEpisode('e4', 'p1', publicationDate: DateTime(2024, 1, 4)),
            _makeEpisode('e5', 'p1', publicationDate: DateTime(2024, 1, 5)),
          ],
        },
      );
      final downloads = _FakeDownloadService();
      final service = AutoDownloadService(
        repository: repo,
        downloadService: downloads,
        isOnWifi: () async => true,
        isPowerSaveMode: () async => false,
      );

      final count = await service.run();

      expect(count, 2);
      expect(downloads.downloaded.map((e) => e.guid).toList(), ['e2', 'e4']);
    });

    test('already downloaded, downloading, and queued episodes count toward X and are not re-enqueued', () async {
      final repo = _FakeRepository(
        subscriptions: [_makePodcast('p1', autoDownloadCount: 4)],
        episodesByPodcast: {
          'p1': [
            _makeEpisode('e1', 'p1', publicationDate: DateTime(2024, 1, 1), downloadState: DownloadState.downloaded),
            _makeEpisode('e2', 'p1', publicationDate: DateTime(2024, 1, 2), downloadState: DownloadState.downloading),
            _makeEpisode('e3', 'p1', publicationDate: DateTime(2024, 1, 3), downloadState: DownloadState.queued),
            _makeEpisode('e4', 'p1', publicationDate: DateTime(2024, 1, 4), downloadState: DownloadState.none),
            _makeEpisode('e5', 'p1', publicationDate: DateTime(2024, 1, 5), downloadState: DownloadState.none),
          ],
        },
      );
      final downloads = _FakeDownloadService();
      final service = AutoDownloadService(
        repository: repo,
        downloadService: downloads,
        isOnWifi: () async => true,
        isPowerSaveMode: () async => false,
      );

      final count = await service.run();

      expect(count, 1);
      expect(downloads.downloaded.map((e) => e.guid).toList(), ['e4']);
    });

    test('respects different autoDownloadCount per subscription', () async {
      final repo = _FakeRepository(
        subscriptions: [
          _makePodcast('p1', autoDownloadCount: 3),
          _makePodcast('p2', autoDownloadCount: 5),
        ],
        episodesByPodcast: {
          'p1': List.generate(
            6,
            (i) => _makeEpisode('p1_e${i + 1}', 'p1', publicationDate: DateTime(2024, 1, i + 1)),
          ),
          'p2': List.generate(
            7,
            (i) => _makeEpisode('p2_e${i + 1}', 'p2', publicationDate: DateTime(2024, 2, i + 1)),
          ),
        },
      );
      final downloads = _FakeDownloadService();
      final service = AutoDownloadService(
        repository: repo,
        downloadService: downloads,
        isOnWifi: () async => true,
        isPowerSaveMode: () async => false,
      );

      final count = await service.run();

      expect(count, 8);
      expect(
        downloads.downloaded.map((e) => e.guid).toList(),
        ['p1_e1', 'p1_e2', 'p1_e3', 'p2_e1', 'p2_e2', 'p2_e3', 'p2_e4', 'p2_e5'],
      );
    });

    test('does not delete excess downloaded episodes when count is lowered', () async {
      final repo = _FakeRepository(
        subscriptions: [_makePodcast('p1', autoDownloadCount: 2)],
        episodesByPodcast: {
          'p1': List.generate(
            5,
            (i) => _makeEpisode(
              'e${i + 1}',
              'p1',
              publicationDate: DateTime(2024, 1, i + 1),
              downloadState: DownloadState.downloaded,
            ),
          ),
        },
      );
      final downloads = _FakeDownloadService();
      final service = AutoDownloadService(
        repository: repo,
        downloadService: downloads,
        isOnWifi: () async => true,
        isPowerSaveMode: () async => false,
      );

      final count = await service.run();

      expect(count, 0);
      expect(downloads.downloaded, isEmpty);
      expect(repo.deletedEpisodes, isEmpty);
    });

    test('skips episodes without contentUrl and continues after download errors', () async {
      final repo = _FakeRepository(
        subscriptions: [_makePodcast('p1', autoDownloadCount: 3)],
        episodesByPodcast: {
          'p1': [
            _makeEpisode('e1_no_url', 'p1', publicationDate: DateTime(2024, 1, 1), contentUrl: ''),
            _makeEpisode('e2_fails', 'p1', publicationDate: DateTime(2024, 1, 2)),
            _makeEpisode('e3_ok', 'p1', publicationDate: DateTime(2024, 1, 3)),
          ],
        },
      );
      final downloads = _FakeDownloadService(failingGuids: {'e2_fails'});
      final service = AutoDownloadService(
        repository: repo,
        downloadService: downloads,
        isOnWifi: () async => true,
        isPowerSaveMode: () async => false,
      );

      final count = await service.run();

      expect(count, 1);
      expect(downloads.downloaded.map((e) => e.guid).toList(), ['e3_ok']);
    });
  });
}
