// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/bloc/podcast/antennapod_import_bloc.dart';
import 'package:anytime/l10n/L.dart';
import 'package:anytime/state/antennapod_import_state.dart';
import 'package:anytime/ui/widgets/action_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dialogs/flutter_dialogs.dart';
import 'package:provider/provider.dart';

class AntennaPodImportDialog extends StatefulWidget {
  final String file;

  const AntennaPodImportDialog({
    super.key,
    required this.file,
  });

  @override
  State<AntennaPodImportDialog> createState() => _AntennaPodImportDialogState();
}

class _AntennaPodImportDialogState extends State<AntennaPodImportDialog> {
  @override
  void initState() {
    super.initState();

    final bloc = Provider.of<AntennaPodImportBloc>(context, listen: false);
    bloc.importEvent(AntennaPodStartImportEvent(file: widget.file));
  }

  @override
  Widget build(BuildContext context) {
    final bloc = Provider.of<AntennaPodImportBloc>(context, listen: false);

    return StreamBuilder<AntennaPodImportState>(
      initialData: AntennaPodImportParsingState(),
      stream: bloc.importState,
      builder: (context, snapshot) {
        final state = snapshot.data;

        if (state is AntennaPodImportCompletedState) {
          return PopScope(
            canPop: true,
            child: BasicDialogAlert(
              title: Text(
                state.cancelled
                    ? L.of(context)!.label_antennapod_import_cancelled
                    : L.of(context)!.label_antennapod_import_complete,
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('New subscriptions imported: ${state.subscriptionsImported}'),
                  if (state.subscriptionsMatched > 0)
                    Text('Existing subscriptions matched: ${state.subscriptionsMatched}'),
                  Text('Episodes marked as played: ${state.episodesMarkedPlayed}'),
                  if (state.failedFeeds.isNotEmpty) ...[
                    const SizedBox(height: 8.0),
                    Text('Failed feeds (${state.failedFeeds.length}):'),
                    const SizedBox(height: 4.0),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 120.0),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: state.failedFeeds
                              .map(
                                (name) => Text(
                                  '• $name',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              actions: <Widget>[
                BasicDialogAction(
                  title: ActionText(L.of(context)!.ok_button_label),
                  onPressed: () {
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          );
        }

        if (state is AntennaPodImportErrorState) {
          return PopScope(
            canPop: true,
            child: BasicDialogAlert(
              title: Text(L.of(context)!.label_antennapod_import_error),
              content: Text(state.message),
              actions: <Widget>[
                BasicDialogAction(
                  title: ActionText(L.of(context)!.ok_button_label),
                  onPressed: () {
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          );
        }

        final pct = state is AntennaPodImportLoadingState && state.total > 0
            ? (state.current / state.total) * 100
            : 0.0;

        return PopScope(
          canPop: false,
          child: BasicDialogAlert(
            title: Text(L.of(context)!.settings_import_antennapod),
            content: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const CircularProgressIndicator.adaptive(),
                const SizedBox(width: 16.0),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        L.of(context)!.label_antennapod_importing,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (state is AntennaPodImportLoadingState)
                        Text(
                          '${pct.toInt()}% - ${state.podcast ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            actions: <Widget>[
              BasicDialogAction(
                title: ActionText(L.of(context)!.cancel_button_label),
                onPressed: () {
                  bloc.importEvent(AntennaPodCancelImportEvent());
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
