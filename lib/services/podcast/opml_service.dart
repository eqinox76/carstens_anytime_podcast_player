// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/state/opml_state.dart';

/// This service handles the export of Podcasts via the OPML format.
abstract class OPMLService {
  Stream<OPMLState> saveOPMLFile();
}
