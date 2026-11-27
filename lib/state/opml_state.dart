// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

abstract class OPMLState {}

class OPMLNoneState extends OPMLState {}

class OPMLCompletedState extends OPMLState {}

abstract class OPMLEvent {}

class OPMLExportEvent extends OPMLEvent {}
