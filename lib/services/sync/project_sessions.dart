// lib/services/sync/project_sessions.dart
/// Per-project login sessions and survey associations for the DataKollecta
/// product, replacing the old single-session model (one global project
/// code/username/password/token in SettingsService).
///
/// Two things live together in one document rather than in separate
/// SettingsService keys:
///   - `sessions`: every configured project's credentials and bearer token.
///   - `associations`: which project each locally-known survey came from.
///
/// They are kept in one document, not N flat keys, because they must stay
/// mutually consistent (removing a project should be able to see every
/// survey it owns) and because the existing per-survey pattern in
/// SettingsService (`survey_${id}_username`) offers neither enumeration nor
/// deletion -- both of which this needs.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../settings_service.dart';

/// One project's stored credentials and (if still valid) bearer token.
@immutable
class ProjectSession {
  final String projectCode;
  final String? projectName;
  final String username;
  final String password;
  final String? token;
  final DateTime? expiresAt;

  const ProjectSession({
    required this.projectCode,
    this.projectName,
    required this.username,
    required this.password,
    this.token,
    this.expiresAt,
  });

  /// True with at least [skew] of validity remaining. A zero-margin
  /// `isAfter(now)` check would let an upload run start with a token about
  /// to expire mid-run; refreshing a few minutes early avoids that.
  bool isValid({DateTime? now, Duration skew = const Duration(minutes: 5)}) {
    if (token == null || expiresAt == null) return false;
    return expiresAt!.isAfter((now ?? DateTime.now()).add(skew));
  }

  Map<String, dynamic> toJson() => {
        'projectCode': projectCode,
        if (projectName != null) 'projectName': projectName,
        'username': username,
        'password': password,
        if (token != null) 'token': token,
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
      };

  /// Returns null (rather than throwing) for a malformed entry, so one
  /// corrupt session in the document never breaks every other project.
  static ProjectSession? tryFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final projectCode = raw['projectCode'];
    final username = raw['username'];
    final password = raw['password'];
    if (projectCode is! String || username is! String || password is! String) {
      return null;
    }
    final expiresAtStr = raw['expiresAt'];
    return ProjectSession(
      projectCode: projectCode,
      projectName: raw['projectName'] as String?,
      username: username,
      password: password,
      token: raw['token'] as String?,
      expiresAt:
          expiresAtStr is String ? DateTime.tryParse(expiresAtStr) : null,
    );
  }
}

/// Raised when a `surveyId` (or the manifest's `databaseName`) that is
/// already bound to one project is about to be bound to a different one.
///
/// `surveyId` is a device-global key -- it names the extraction folder, the
/// open-database map entry, and (via `databaseName`) the SQLite file
/// itself. Two projects sharing either would silently collapse into one
/// on-device folder/database, so this is refused outright rather than
/// allowed and routed "best effort".
class ProjectAssociationConflict implements Exception {
  final String surveyId;
  final String existingProjectCode;
  final String incomingProjectCode;

  const ProjectAssociationConflict({
    required this.surveyId,
    required this.existingProjectCode,
    required this.incomingProjectCode,
  });

  @override
  String toString() =>
      'Survey "$surveyId" is already linked to project "$existingProjectCode"; '
      'cannot also link it to "$incomingProjectCode".';
}

/// The full per-device document.
@immutable
class ProjectSessionsDocument {
  final Map<String, ProjectSession> sessions; // keyed by projectCode
  final Map<String, String> associations; // surveyId -> projectCode

  const ProjectSessionsDocument({
    this.sessions = const {},
    this.associations = const {},
  });

  static const empty = ProjectSessionsDocument();

  ProjectSession? sessionFor(String projectCode) => sessions[projectCode];

  String? projectFor(String surveyId) => associations[surveyId];

  /// Every surveyId currently associated with [projectCode] -- what a
  /// "remove this project" confirmation needs to show.
  List<String> surveysFor(String projectCode) => [
        for (final entry in associations.entries)
          if (entry.value == projectCode) entry.key,
      ];

  ProjectSessionsDocument withSession(ProjectSession session) {
    return ProjectSessionsDocument(
      sessions: {...sessions, session.projectCode: session},
      associations: associations,
    );
  }

  ProjectSessionsDocument withoutSession(String projectCode) {
    final nextSessions = {...sessions}..remove(projectCode);
    // Associations are deliberately left in place: re-adding the same
    // project code repairs every survey that pointed at it with no other
    // action needed, and a survey whose project is missing fails routing
    // cleanly (RoutingFailure) rather than silently adopting another one.
    return ProjectSessionsDocument(
        sessions: nextSessions, associations: associations);
  }

  /// Binds [surveyId] to [projectCode]. Returns the unchanged document if
  /// the binding already matches; throws [ProjectAssociationConflict] if it
  /// collides with a different project already bound to that surveyId.
  ProjectSessionsDocument withAssociation(String surveyId, String projectCode) {
    final existing = associations[surveyId];
    if (existing == projectCode) return this;
    if (existing != null) {
      throw ProjectAssociationConflict(
        surveyId: surveyId,
        existingProjectCode: existing,
        incomingProjectCode: projectCode,
      );
    }
    return ProjectSessionsDocument(
      sessions: sessions,
      associations: {...associations, surveyId: projectCode},
    );
  }

  ProjectSessionsDocument withoutAssociation(String surveyId) {
    final next = {...associations}..remove(surveyId);
    return ProjectSessionsDocument(sessions: sessions, associations: next);
  }

  Map<String, dynamic> toJson() => {
        'sessions': sessions.map((code, s) => MapEntry(code, s.toJson())),
        'associations': associations,
      };

  String encode() => json.encode(toJson());

  /// Never throws -- corrupt or missing JSON decodes to [empty] rather than
  /// bricking login, and a malformed individual session/association entry
  /// is skipped rather than failing the whole document.
  static ProjectSessionsDocument decode(String? raw) {
    if (raw == null || raw.isEmpty) return empty;
    try {
      final map = json.decode(raw);
      if (map is! Map) return empty;

      final sessions = <String, ProjectSession>{};
      final sessionsRaw = map['sessions'];
      if (sessionsRaw is Map) {
        for (final entry in sessionsRaw.entries) {
          final session = ProjectSession.tryFromJson(entry.value);
          if (session != null && entry.key is String) {
            sessions[entry.key as String] = session;
          }
        }
      }

      final associations = <String, String>{};
      final associationsRaw = map['associations'];
      if (associationsRaw is Map) {
        for (final entry in associationsRaw.entries) {
          final value = entry.value;
          if (entry.key is String && value is String) {
            associations[entry.key as String] = value;
          }
        }
      }

      return ProjectSessionsDocument(
          sessions: sessions, associations: associations);
    } catch (e) {
      debugPrint('[ProjectSessions] Ignoring corrupt document: $e');
      return empty;
    }
  }
}

/// Storage-agnostic repository: reads/writes the document through injected
/// closures (defaulting to [SettingsService]), and serializes writes with a
/// single-flight chain -- the underlying storage is not atomically
/// read-modify-written, and the document is written from independent call
/// sites (a Settings save, a silent re-login mid-upload, an association
/// write during download) that must not interleave and drop each other's
/// change.
class ProjectSessionsRepository {
  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;
  Future<void> _writeChain = Future.value();

  ProjectSessionsRepository({
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
  })  : _read = read ?? (() => SettingsService().projectSessionsRaw),
        _write = write ?? ((v) => SettingsService().setProjectSessionsRaw(v));

  /// The single instance production code should use, so writes from
  /// independent call sites actually serialize against each other. Tests
  /// construct their own instance with injected closures instead.
  static final ProjectSessionsRepository shared = ProjectSessionsRepository();

  Future<ProjectSessionsDocument> load() async {
    return ProjectSessionsDocument.decode(await _read());
  }

  /// Applies [apply] to the current document and persists the result,
  /// chained after any other in-flight update. If [apply] throws (e.g. a
  /// [ProjectAssociationConflict]), nothing is written and the exception
  /// propagates to this call's caller without disturbing the queue for
  /// anyone else waiting on it.
  Future<ProjectSessionsDocument> update(
      ProjectSessionsDocument Function(ProjectSessionsDocument current) apply) {
    final previous = _writeChain;
    final result = previous.then((_) async {
      final current = await load();
      final next = apply(current);
      await _write(next.encode());
      return next;
    });
    _writeChain = result.then((_) {}, onError: (_) {});
    return result;
  }
}
