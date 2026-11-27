// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/l10n/L.dart';
import 'package:anytime/ui/widgets/action_text.dart';
import 'package:flutter/material.dart';

/// Dialog allowing the user to configure the per-subscription auto-download
/// episode count (0 = Off, up to 50).
class AutoDownloadDialog extends StatefulWidget {
  final int initialCount;

  const AutoDownloadDialog({
    super.key,
    required this.initialCount,
  });

  @override
  State<AutoDownloadDialog> createState() => _AutoDownloadDialogState();
}

class _AutoDownloadDialogState extends State<AutoDownloadDialog> {
  static const int _maxCount = 50;

  late int _count;

  @override
  void initState() {
    super.initState();
    _count = widget.initialCount.clamp(0, _maxCount);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(
        l.auto_download_label,
        style: theme.textTheme.titleLarge,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.auto_download_subtitle,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16.0),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: 'Decrease',
                onPressed: _count > 0 ? () => setState(() => _count--) : null,
              ),
              SizedBox(
                width: 64.0,
                child: Text(
                  _count == 0 ? l.auto_download_off_label : '$_count',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Increase',
                onPressed: _count < _maxCount ? () => setState(() => _count++) : null,
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop<int?>(context, null),
          child: ActionText(l.cancel_button_label),
        ),
        TextButton(
          onPressed: () => Navigator.pop<int>(context, _count),
          child: ActionText(l.ok_button_label),
        ),
      ],
    );
  }
}
