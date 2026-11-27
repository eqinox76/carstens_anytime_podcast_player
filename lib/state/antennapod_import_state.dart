// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

abstract class AntennaPodImportState {}

class AntennaPodImportParsingState extends AntennaPodImportState {}

class AntennaPodImportLoadingState extends AntennaPodImportState {
  final int current;
  final int total;
  final String? podcast;

  AntennaPodImportLoadingState({
    required this.current,
    required this.total,
    this.podcast,
  });
}

class AntennaPodImportCompletedState extends AntennaPodImportState {
  final int subscriptionsImported;
  final int subscriptionsMatched;
  final int episodesMarkedPlayed;
  final List<String> failedFeeds;
  final bool cancelled;

  AntennaPodImportCompletedState({
    required this.subscriptionsImported,
    required this.subscriptionsMatched,
    required this.episodesMarkedPlayed,
    required this.failedFeeds,
    this.cancelled = false,
  });
}

class AntennaPodImportErrorState extends AntennaPodImportState {
  final String message;

  AntennaPodImportErrorState({
    required this.message,
  });
}

abstract class AntennaPodImportEvent {}

class AntennaPodStartImportEvent extends AntennaPodImportEvent {
  final String file;

  AntennaPodStartImportEvent({
    required this.file,
  });
}

class AntennaPodCancelImportEvent extends AntennaPodImportEvent {}
