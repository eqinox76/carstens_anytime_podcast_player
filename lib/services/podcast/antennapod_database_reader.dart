// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/services.dart';

/// A played episode record extracted from an AntennaPod database backup.
class AntennaPodPlayedItem {
  final String? guid;
  final String? mediaUrl;

  const AntennaPodPlayedItem({
    this.guid,
    this.mediaUrl,
  });
}

/// A subscribed podcast feed and its played episodes extracted from an AntennaPod database backup.
class AntennaPodFeed {
  final String title;
  final String feedUrl;
  final List<AntennaPodPlayedItem> playedItems;

  const AntennaPodFeed({
    required this.title,
    required this.feedUrl,
    required this.playedItems,
  });
}

/// Exception thrown when an AntennaPod database backup cannot be read or is invalid.
class AntennaPodImportException implements Exception {
  final String message;

  const AntennaPodImportException(this.message);

  @override
  String toString() => 'AntennaPodImportException: $message';
}

/// Abstraction for reading podcast subscriptions and played episode metadata
/// from an exported AntennaPod SQLite database.
abstract class AntennaPodDatabaseReader {
  Future<List<AntennaPodFeed>> readDatabase(String path);
}

/// Reads an AntennaPod SQLite database via the Android platform [MethodChannel].
class MethodChannelAntennaPodDatabaseReader implements AntennaPodDatabaseReader {
  static const String channelName = 'uk.me.amugofjava.anytime_podcast_player/antennapod_import';

  final MethodChannel _channel;

  const MethodChannelAntennaPodDatabaseReader({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  @override
  Future<List<AntennaPodFeed>> readDatabase(String path) async {
    try {
      final rawFeeds = await _channel.invokeMethod<List<dynamic>>(
        'readDatabase',
        <String, dynamic>{'path': path},
      );

      if (rawFeeds == null) {
        return const <AntennaPodFeed>[];
      }

      final feeds = <AntennaPodFeed>[];
      for (final rawFeed in rawFeeds) {
        if (rawFeed is! Map) {
          continue;
        }

        final title = (rawFeed['title'] as String?) ?? '';
        final feedUrl = (rawFeed['feedUrl'] as String?) ?? '';
        if (feedUrl.isEmpty) {
          continue;
        }

        final playedItems = <AntennaPodPlayedItem>[];
        final rawPlayedItems = rawFeed['playedItems'];
        if (rawPlayedItems is List) {
          for (final rawItem in rawPlayedItems) {
            if (rawItem is! Map) {
              continue;
            }
            playedItems.add(
              AntennaPodPlayedItem(
                guid: rawItem['guid'] as String?,
                mediaUrl: rawItem['mediaUrl'] as String?,
              ),
            );
          }
        }

        feeds.add(
          AntennaPodFeed(
            title: title,
            feedUrl: feedUrl,
            playedItems: playedItems,
          ),
        );
      }

      return feeds;
    } on PlatformException catch (e) {
      throw AntennaPodImportException(e.message ?? 'Failed to read AntennaPod database.');
    } on MissingPluginException {
      throw const AntennaPodImportException('AntennaPod database import is not supported on this platform.');
    }
  }
}
