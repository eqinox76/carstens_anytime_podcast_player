// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/entities/episode.dart';
import 'package:anytime/entities/podcast.dart';
import 'package:anytime/repository/repository.dart';
import 'package:anytime/services/podcast/antennapod_database_reader.dart';
import 'package:anytime/services/podcast/antennapod_import_service.dart';
import 'package:anytime/services/podcast/podcast_service.dart';
import 'package:anytime/state/antennapod_import_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDatabaseReader implements AntennaPodDatabaseReader {
  final Future<List<AntennaPodFeed>> Function(String path) _handler;
  final List<String> requestedPaths = <String>[];

  _FakeDatabaseReader({
    List<AntennaPodFeed>? feeds,
    Future<List<AntennaPodFeed>> Function(String path)? onRead,
  }) : _handler = onRead ?? ((_) async => feeds ?? const <AntennaPodFeed>[]);

  @override
  Future<List<AntennaPodFeed>> readDatabase(String path) {
    requestedPaths.add(path);
    return _handler(path);
  }
}

class _LoadPodcastCall {
  final Podcast podcast;
  final bool ignoreCache;

  const _LoadPodcastCall({
    required this.podcast,
    required this.ignoreCache,
  });
}

class _FakePodcastService implements PodcastService {
  final List<Podcast> _subscriptions;
  final Future<Podcast?> Function(Podcast podcast, bool ignoreCache)? _onLoadPodcast;
  final Future<Podcast?> Function(Podcast podcast)? _onSubscribe;

  bool subscriptionsCalled = false;
  final List<_LoadPodcastCall> loadPodcastCalls = <_LoadPodcastCall>[];
  final List<Podcast> subscribeCalls = <Podcast>[];
  final List<List<Episode>> savedEpisodeBatches = <List<Episode>>[];

  _FakePodcastService({
    List<Podcast>? subscriptions,
    Future<Podcast?> Function(Podcast podcast, bool ignoreCache)? onLoadPodcast,
    Future<Podcast?> Function(Podcast podcast)? onSubscribe,
  })  : _subscriptions = subscriptions ?? <Podcast>[],
        _onLoadPodcast = onLoadPodcast,
        _onSubscribe = onSubscribe;

  @override
  Future<List<Podcast>> subscriptions() async {
    subscriptionsCalled = true;
    return List<Podcast>.from(_subscriptions);
  }

  @override
  Future<Podcast?> loadPodcast({
    required Podcast podcast,
    bool highlightNewEpisodes = false,
    bool ignoreCache = false,
  }) async {
    loadPodcastCalls.add(_LoadPodcastCall(podcast: podcast, ignoreCache: ignoreCache));
    if (_onLoadPodcast != null) {
      return _onLoadPodcast(podcast, ignoreCache);
    }
    return null;
  }

  @override
  Future<Podcast?> subscribe(Podcast podcast) async {
    subscribeCalls.add(podcast);
    if (_onSubscribe != null) {
      return _onSubscribe(podcast);
    }
    return podcast;
  }

  @override
  Future<List<Episode>> saveEpisodes(List<Episode> episodes) async {
    savedEpisodeBatches.add(List<Episode>.from(episodes));
    return episodes;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRepository implements Repository {
  final Map<String, List<Episode>> _episodesByPodcast;
  final List<String> queriedPodcastGuids = <String>[];

  _FakeRepository({
    Map<String, List<Episode>>? episodesByPodcast,
  }) : _episodesByPodcast = episodesByPodcast ?? <String, List<Episode>>{};

  @override
  Future<List<Episode>> findEpisodesByPodcastGuid(
    String pguid, {
    PodcastEpisodeFilter filter = PodcastEpisodeFilter.none,
    PodcastEpisodeSort sort = PodcastEpisodeSort.none,
  }) async {
    queriedPodcastGuids.add(pguid);
    return List<Episode>.from(_episodesByPodcast[pguid] ?? const <Episode>[]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Podcast _makePodcast(
  String guid, {
  required String url,
  String? title,
  List<Episode>? episodes,
}) {
  return Podcast(
    guid: guid,
    url: url,
    link: 'https://example.com/$guid',
    title: title ?? 'Podcast $guid',
    episodes: episodes ?? <Episode>[],
  );
}

Episode _makeEpisode(
  String guid,
  String pguid, {
  bool played = false,
  int position = 0,
  String? contentUrl = 'https://cdn.example.com/audio.mp3',
}) {
  return Episode(
    guid: guid,
    pguid: pguid,
    podcast: 'Podcast $pguid',
    title: 'Episode $guid',
    played: played,
    position: position,
    contentUrl: contentUrl,
  );
}

void main() {
  group('normalizePodcastUrl', () {
    test('strips http:// and https:// case-insensitively', () {
      expect(normalizePodcastUrl('http://example.com/feed.xml'), 'example.com/feed.xml');
      expect(normalizePodcastUrl('https://example.com/feed.xml'), 'example.com/feed.xml');
      expect(normalizePodcastUrl('HTTP://example.com/feed.xml'), 'example.com/feed.xml');
      expect(normalizePodcastUrl('HtTpS://example.com/feed.xml'), 'example.com/feed.xml');
    });

    test('lowercases host while preserving path case', () {
      expect(
        normalizePodcastUrl('https://Feeds.Example.COM/MyShow/Feed.XML'),
        'feeds.example.com/MyShow/Feed.XML',
      );
      expect(
        normalizePodcastUrl('https://EXAMPLE.COM'),
        'example.com',
      );
      expect(
        normalizePodcastUrl('https://EXAMPLE.COM?Feed=AbC'),
        'example.com?Feed=AbC',
      );
    });

    test('strips trailing slashes and trims whitespace', () {
      expect(normalizePodcastUrl('  https://example.com/feed/  '), 'example.com/feed');
      expect(normalizePodcastUrl('\thttp://example.com/feed///\n'), 'example.com/feed');
      expect(normalizePodcastUrl('https://example.com/'), 'example.com');
    });
  });

  group('MobileAntennaPodImportService', () {
    test('imports new subscriptions, marks played episodes by guid and normalized contentUrl, and emits progress',
        () async {
      final epByGuid = _makeEpisode(
        'ep-guid-1',
        'p1',
        position: 12000,
        contentUrl: 'https://cdn.example.com/ep1.mp3',
      );
      final epByMediaUrl = _makeEpisode(
        'ep-guid-different',
        'p1',
        position: 5000,
        contentUrl: 'https://CDN.Example.com/Shows/Ep2.mp3/',
      );
      final epUnplayed = _makeEpisode(
        'ep-guid-3',
        'p1',
        position: 3400,
        contentUrl: 'https://cdn.example.com/ep3.mp3',
      );
      final feed2Ep = _makeEpisode(
        'ep-feed2-1',
        'p2',
        contentUrl: 'https://cdn.example.com/f2e1.mp3',
      );

      final reader = _FakeDatabaseReader(
        feeds: [
          const AntennaPodFeed(
            title: 'Show One',
            feedUrl: 'https://feeds.example.com/show1.xml',
            playedItems: [
              AntennaPodPlayedItem(guid: 'ep-guid-1', mediaUrl: 'https://other.example.com/unused.mp3'),
              AntennaPodPlayedItem(guid: 'non-matching-guid', mediaUrl: 'http://cdn.example.com/Shows/Ep2.mp3'),
            ],
          ),
          const AntennaPodFeed(
            title: 'Show Two',
            feedUrl: 'https://feeds.example.com/show2.xml',
            playedItems: [],
          ),
        ],
      );

      final loadedByUrl = <String, Podcast>{
        'https://feeds.example.com/show1.xml': _makePodcast(
          'p1',
          url: 'https://feeds.example.com/show1.xml',
          title: 'Show One',
          episodes: [epByGuid, epByMediaUrl, epUnplayed],
        ),
        'https://feeds.example.com/show2.xml': _makePodcast(
          'p2',
          url: 'https://feeds.example.com/show2.xml',
          title: 'Show Two',
          episodes: [feed2Ep],
        ),
      };

      final podcastService = _FakePodcastService(
        onLoadPodcast: (podcast, ignoreCache) async => loadedByUrl[podcast.url],
      );
      final repository = _FakeRepository();

      final service = MobileAntennaPodImportService(
        databaseReader: reader,
        podcastService: podcastService,
        repository: repository,
      );

      final states = await service.importDatabase('/tmp/antennapod.db').toList();

      expect(reader.requestedPaths, ['/tmp/antennapod.db']);
      expect(podcastService.loadPodcastCalls.length, 2);
      expect(podcastService.loadPodcastCalls.every((c) => c.ignoreCache), isTrue);
      expect(podcastService.subscribeCalls.map((p) => p.guid).toList(), ['p1', 'p2']);

      expect(epByGuid.played, isTrue);
      expect(epByGuid.position, 12000);
      expect(epByMediaUrl.played, isTrue);
      expect(epByMediaUrl.position, 5000);
      expect(epUnplayed.played, isFalse);
      expect(epUnplayed.position, 3400);
      expect(feed2Ep.played, isFalse);

      expect(podcastService.savedEpisodeBatches.length, 1);
      expect(
        podcastService.savedEpisodeBatches.single.map((e) => e.guid).toList(),
        ['ep-guid-1', 'ep-guid-different'],
      );

      expect(states.length, 4);
      expect(states[0], isA<AntennaPodImportParsingState>());

      final loading1 = states[1] as AntennaPodImportLoadingState;
      expect(loading1.current, 1);
      expect(loading1.total, 2);
      expect(loading1.podcast, 'Show One');

      final loading2 = states[2] as AntennaPodImportLoadingState;
      expect(loading2.current, 2);
      expect(loading2.total, 2);
      expect(loading2.podcast, 'Show Two');

      final completed = states[3] as AntennaPodImportCompletedState;
      expect(completed.subscriptionsImported, 2);
      expect(completed.subscriptionsMatched, 0);
      expect(completed.episodesMarkedPlayed, 2);
      expect(completed.failedFeeds, isEmpty);
      expect(completed.cancelled, isFalse);
    });

    test('reuses existing subscriptions by normalized URL without reloading or un-playing episodes', () async {
      final alreadyPlayedInAnytime = _makeEpisode('ep-already-played', 'p1', played: true, position: 999);
      final alreadyPlayedAlsoInBackup = _makeEpisode('ep-both-played', 'p1', played: true);
      final newlyPlayed = _makeEpisode('ep-newly-played', 'p1', played: false);
      final stillUnplayed = _makeEpisode('ep-unplayed', 'p1', played: false);

      final existingPodcast = _makePodcast(
        'p1',
        url: 'https://Feeds.Example.com/show1.xml/',
        title: 'Show One',
      );

      final reader = _FakeDatabaseReader(
        feeds: const [
          AntennaPodFeed(
            title: 'Show One',
            feedUrl: 'http://feeds.example.com/show1.xml',
            playedItems: [
              AntennaPodPlayedItem(guid: 'ep-both-played'),
              AntennaPodPlayedItem(guid: 'ep-newly-played'),
            ],
          ),
        ],
      );

      final podcastService = _FakePodcastService(subscriptions: [existingPodcast]);
      final repository = _FakeRepository(
        episodesByPodcast: {
          'p1': [alreadyPlayedInAnytime, alreadyPlayedAlsoInBackup, newlyPlayed, stillUnplayed],
        },
      );

      final service = MobileAntennaPodImportService(
        databaseReader: reader,
        podcastService: podcastService,
        repository: repository,
      );

      final states = await service.importDatabase('/tmp/antennapod.db').toList();

      expect(podcastService.loadPodcastCalls, isEmpty);
      expect(podcastService.subscribeCalls, isEmpty);
      expect(repository.queriedPodcastGuids, ['p1']);

      expect(alreadyPlayedInAnytime.played, isTrue);
      expect(alreadyPlayedInAnytime.position, 999);
      expect(alreadyPlayedAlsoInBackup.played, isTrue);
      expect(newlyPlayed.played, isTrue);
      expect(stillUnplayed.played, isFalse);

      expect(podcastService.savedEpisodeBatches.length, 1);
      expect(podcastService.savedEpisodeBatches.single.map((e) => e.guid).toList(), ['ep-newly-played']);

      final completed = states.last as AntennaPodImportCompletedState;
      expect(completed.subscriptionsImported, 0);
      expect(completed.subscriptionsMatched, 1);
      expect(completed.episodesMarkedPlayed, 1);
      expect(completed.failedFeeds, isEmpty);
      expect(completed.cancelled, isFalse);
    });

    test('does not call saveEpisodes when all matched episodes are already played', () async {
      final alreadyPlayed = _makeEpisode('ep-1', 'p1', played: true);
      final existingPodcast = _makePodcast('p1', url: 'https://example.com/feed.xml');

      final reader = _FakeDatabaseReader(
        feeds: const [
          AntennaPodFeed(
            title: 'Show One',
            feedUrl: 'https://example.com/feed.xml',
            playedItems: [
              AntennaPodPlayedItem(guid: 'ep-1'),
            ],
          ),
        ],
      );

      final podcastService = _FakePodcastService(subscriptions: [existingPodcast]);
      final repository = _FakeRepository(
        episodesByPodcast: {
          'p1': [alreadyPlayed],
        },
      );

      final service = MobileAntennaPodImportService(
        databaseReader: reader,
        podcastService: podcastService,
        repository: repository,
      );

      final states = await service.importDatabase('/tmp/antennapod.db').toList();

      expect(podcastService.savedEpisodeBatches, isEmpty);
      final completed = states.last as AntennaPodImportCompletedState;
      expect(completed.subscriptionsMatched, 1);
      expect(completed.episodesMarkedPlayed, 0);
    });

    test('emits Error state on AntennaPodImportException without touching podcastService', () async {
      final reader = _FakeDatabaseReader(
        onRead: (_) async => throw const AntennaPodImportException('Invalid AntennaPod database'),
      );
      final podcastService = _FakePodcastService();
      final repository = _FakeRepository();

      final service = MobileAntennaPodImportService(
        databaseReader: reader,
        podcastService: podcastService,
        repository: repository,
      );

      final states = await service.importDatabase('/tmp/corrupt.db').toList();

      expect(states.length, 2);
      expect(states[0], isA<AntennaPodImportParsingState>());
      final error = states[1] as AntennaPodImportErrorState;
      expect(error.message, 'Invalid AntennaPod database');

      expect(podcastService.subscriptionsCalled, isFalse);
      expect(podcastService.loadPodcastCalls, isEmpty);
      expect(podcastService.subscribeCalls, isEmpty);
      expect(podcastService.savedEpisodeBatches, isEmpty);
    });

    test('records failed feeds when loadPodcast returns null or throws and continues remaining feeds', () async {
      final goodEpisode = _makeEpisode('ep-good', 'p-good');
      final reader = _FakeDatabaseReader(
        feeds: const [
          AntennaPodFeed(
            title: 'Null Feed',
            feedUrl: 'https://example.com/null.xml',
            playedItems: [],
          ),
          AntennaPodFeed(
            title: '',
            feedUrl: 'https://example.com/throws.xml',
            playedItems: [],
          ),
          AntennaPodFeed(
            title: 'Good Feed',
            feedUrl: 'https://example.com/good.xml',
            playedItems: [AntennaPodPlayedItem(guid: 'ep-good')],
          ),
        ],
      );

      final podcastService = _FakePodcastService(
        onLoadPodcast: (podcast, _) async {
          if (podcast.url == 'https://example.com/null.xml') {
            return null;
          }
          if (podcast.url == 'https://example.com/throws.xml') {
            throw Exception('network error');
          }
          return _makePodcast('p-good', url: podcast.url, title: podcast.title, episodes: [goodEpisode]);
        },
      );
      final repository = _FakeRepository();

      final service = MobileAntennaPodImportService(
        databaseReader: reader,
        podcastService: podcastService,
        repository: repository,
      );

      final states = await service.importDatabase('/tmp/antennapod.db').toList();
      final completed = states.last as AntennaPodImportCompletedState;

      expect(completed.subscriptionsImported, 1);
      expect(completed.subscriptionsMatched, 0);
      expect(completed.episodesMarkedPlayed, 1);
      expect(completed.failedFeeds, ['Null Feed', 'https://example.com/throws.xml']);
      expect(completed.cancelled, isFalse);
      expect(goodEpisode.played, isTrue);
    });

    test('stops processing remaining feeds and marks cancelled when cancel() is called mid-import', () async {
      final reader = _FakeDatabaseReader(
        feeds: const [
          AntennaPodFeed(title: 'Feed 1', feedUrl: 'https://example.com/1.xml', playedItems: []),
          AntennaPodFeed(title: 'Feed 2', feedUrl: 'https://example.com/2.xml', playedItems: []),
          AntennaPodFeed(title: 'Feed 3', feedUrl: 'https://example.com/3.xml', playedItems: []),
        ],
      );

      late MobileAntennaPodImportService service;
      final podcastService = _FakePodcastService(
        onLoadPodcast: (podcast, _) async {
          if (podcast.url == 'https://example.com/1.xml') {
            service.cancel();
          }
          return _makePodcast(podcast.url, url: podcast.url, title: podcast.title);
        },
      );
      final repository = _FakeRepository();

      service = MobileAntennaPodImportService(
        databaseReader: reader,
        podcastService: podcastService,
        repository: repository,
      );

      final states = await service.importDatabase('/tmp/antennapod.db').toList();

      expect(podcastService.loadPodcastCalls.map((c) => c.podcast.url).toList(), ['https://example.com/1.xml']);
      expect(podcastService.subscribeCalls.length, 1);

      expect(states.length, 3);
      expect(states[0], isA<AntennaPodImportParsingState>());
      final loading = states[1] as AntennaPodImportLoadingState;
      expect(loading.current, 1);
      expect(loading.total, 3);
      expect(loading.podcast, 'Feed 1');

      final completed = states[2] as AntennaPodImportCompletedState;
      expect(completed.subscriptionsImported, 1);
      expect(completed.subscriptionsMatched, 0);
      expect(completed.episodesMarkedPlayed, 0);
      expect(completed.failedFeeds, isEmpty);
      expect(completed.cancelled, isTrue);
    });
  });

  group('MethodChannelAntennaPodDatabaseReader', () {
    const channel = MethodChannel(MethodChannelAntennaPodDatabaseReader.channelName);
    late MethodChannelAntennaPodDatabaseReader reader;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      reader = const MethodChannelAntennaPodDatabaseReader();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    test('parses valid channel response into List<AntennaPodFeed>', () async {
      MethodCall? capturedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          capturedCall = call;
          return <dynamic>[
            <String, dynamic>{
              'title': 'Show One',
              'feedUrl': 'https://example.com/show1.xml',
              'playedItems': <dynamic>[
                <String, dynamic>{
                  'guid': 'g1',
                  'mediaUrl': 'https://example.com/ep1.mp3',
                },
                <String, dynamic>{
                  'guid': null,
                  'mediaUrl': 'https://example.com/ep2.mp3',
                },
                'malformed-item',
              ],
            },
            <String, dynamic>{
              'title': 'Missing URL',
              'feedUrl': '',
              'playedItems': <dynamic>[],
            },
            'malformed-feed',
          ];
        },
      );

      final feeds = await reader.readDatabase('/storage/antennapod.db');

      expect(capturedCall?.method, 'readDatabase');
      expect(capturedCall?.arguments, <String, dynamic>{'path': '/storage/antennapod.db'});
      expect(feeds.length, 1);
      expect(feeds.single.title, 'Show One');
      expect(feeds.single.feedUrl, 'https://example.com/show1.xml');
      expect(feeds.single.playedItems.length, 2);
      expect(feeds.single.playedItems[0].guid, 'g1');
      expect(feeds.single.playedItems[0].mediaUrl, 'https://example.com/ep1.mp3');
      expect(feeds.single.playedItems[1].guid, isNull);
      expect(feeds.single.playedItems[1].mediaUrl, 'https://example.com/ep2.mp3');
    });

    test('wraps PlatformException in AntennaPodImportException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          throw PlatformException(code: 'INVALID_DB', message: 'Not a valid AntennaPod backup');
        },
      );

      await expectLater(
        () => reader.readDatabase('/storage/bad.db'),
        throwsA(
          isA<AntennaPodImportException>().having(
            (e) => e.message,
            'message',
            'Not a valid AntennaPod backup',
          ),
        ),
      );
    });
  });
}
