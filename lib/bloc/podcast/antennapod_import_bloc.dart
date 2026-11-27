// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:anytime/bloc/bloc.dart';
import 'package:anytime/services/podcast/antennapod_import_service.dart';
import 'package:anytime/state/antennapod_import_state.dart';
import 'package:rxdart/rxdart.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// BLoC coordinating AntennaPod SQLite database imports.
class AntennaPodImportBloc extends Bloc {
  final PublishSubject<AntennaPodImportEvent> _importEvent = PublishSubject<AntennaPodImportEvent>();
  final PublishSubject<AntennaPodImportState> _importState = PublishSubject<AntennaPodImportState>();
  final AntennaPodImportService importService;

  StreamSubscription<AntennaPodImportState>? _importSubscription;

  AntennaPodImportBloc({required this.importService}) {
    _listenImportEvents();
  }

  void _listenImportEvents() {
    _importEvent.listen((event) {
      if (event is AntennaPodStartImportEvent) {
        _importSubscription?.cancel();
        _importSubscription = importService.importDatabase(event.file).listen(
          (state) {
            if (state is AntennaPodImportParsingState) {
              WakelockPlus.enable();
            } else if (state is! AntennaPodImportLoadingState) {
              WakelockPlus.disable();
            }

            if (!_importState.isClosed) {
              _importState.add(state);
            }
          },
          onError: (Object error) {
            WakelockPlus.disable();
            if (!_importState.isClosed) {
              _importState.add(AntennaPodImportErrorState(message: error.toString()));
            }
          },
          onDone: () {
            WakelockPlus.disable();
          },
        );
      } else if (event is AntennaPodCancelImportEvent) {
        WakelockPlus.disable();
        importService.cancel();
      }
    });
  }

  void Function(AntennaPodImportEvent) get importEvent => _importEvent.add;

  Stream<AntennaPodImportState> get importState => _importState.stream;

  @override
  void dispose() {
    WakelockPlus.disable();
    _importSubscription?.cancel();
    _importEvent.close();
    _importState.close();
    super.dispose();
  }
}
