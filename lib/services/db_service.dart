// lib/services/db_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
// import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xml/xml.dart';

import '../models/question.dart';
import 'survey_loader.dart';

class DbService {
  static Database? _db;

  /// Call once at app start
  static Future<void> init() async {
    // Windows / desktop via FFI
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'gistx.sqlite');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, _) async => _createSchema(db),
    );
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE surveys(
        id TEXT PRIMARY KEY,          -- e.g. filename (or a generated ID)
        filename TEXT NOT NULL UNIQUE,
        title TEXT,
        xml_hash TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE questions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        survey_id TEXT NOT NULL,
        fieldname TEXT NOT NULL,
        qtype TEXT NOT NULL,
        fieldtype TEXT NOT NULL,
        text TEXT,
        position INTEGER NOT NULL,
        UNIQUE(survey_id, fieldname),
        FOREIGN KEY(survey_id) REFERENCES surveys(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE options(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        question_id INTEGER NOT NULL,
        value TEXT NOT NULL,
        label TEXT NOT NULL,
        position INTEGER NOT NULL,
        UNIQUE(question_id, value),
        FOREIGN KEY(question_id) REFERENCES questions(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE interviews(
        id TEXT PRIMARY KEY,          -- your uniqueid GUID
        survey_id TEXT NOT NULL,
        starttime TEXT,
        stoptime TEXT,
        lastmod TEXT NOT NULL,
        FOREIGN KEY(survey_id) REFERENCES surveys(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE answers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        interview_id TEXT NOT NULL,
        question_id INTEGER NOT NULL,
        -- store one of these, depending on type:
        value_text TEXT,    -- text/radio/automatic
        value_json TEXT,    -- checkbox list as JSON
        UNIQUE(interview_id, question_id),
        FOREIGN KEY(interview_id) REFERENCES interviews(id) ON DELETE CASCADE,
        FOREIGN KEY(question_id) REFERENCES questions(id) ON DELETE CASCADE
      )
    ''');
  }

  /// Scan assets/surveys/*.xml, register/refresh surveys+questions+options.
  static Future<List<_ParsedSurvey>> syncSurveysFromAssets() async {
    final manifest = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> files = json.decode(manifest);
    final paths = files.keys
        .where((k) =>
            k.startsWith('assets/surveys/') && k.toLowerCase().endsWith('.xml'))
        .toList()
      ..sort();

    final result = <_ParsedSurvey>[];

    for (final path in paths) {
      final xmlStr = await rootBundle.loadString(path);
      final hash = sha256.convert(utf8.encode(xmlStr)).toString();

      final id = path; // use asset path as survey_id (stable/unique)
      final nowIso = DateTime.now().toIso8601String();

      // Check if survey exists and hash matches
      final existing =
          await _db!.query('surveys', where: 'id=?', whereArgs: [id], limit: 1);
      if (existing.isEmpty) {
        await _db!.insert('surveys', {
          'id': id,
          'filename': p.basename(path),
          'title': _inferTitleFromXml(xmlStr),
          'xml_hash': hash,
          'created_at': nowIso,
          'updated_at': nowIso,
        });
        await _upsertQuestionsAndOptions(id, xmlStr);
      } else {
        final row = existing.first;
        if (row['xml_hash'] != hash) {
          // XML changed → refresh questions/options
          await _db!.update('surveys', {'xml_hash': hash, 'updated_at': nowIso},
              where: 'id=?', whereArgs: [id]);
          await _refreshQuestionsAndOptions(id, xmlStr);
        }
      }

      // Parse with the same loader you already use for UI
      final questions = await SurveyLoader.loadFromAsset(path);
      result.add(_ParsedSurvey(
          id: id, filename: p.basename(path), questions: questions));
    }

    return result;
  }

  static String _inferTitleFromXml(String xmlStr) {
    // Optional: try to read <title>…</title> if present; fallback to empty
    try {
      final doc = XmlDocument.parse(xmlStr);
      final title = doc
          .findAllElements('title')
          .map((e) => e.innerText.trim())
          .firstWhere(
            (t) => t.isNotEmpty,
            orElse: () => '',
          );
      return title;
    } catch (_) {
      return '';
    }
  }

  static Future<void> _upsertQuestionsAndOptions(
      String surveyId, String xmlStr) async {
    final doc = XmlDocument.parse(xmlStr);
    final questions = doc.findAllElements('question').toList();

    int pos = 0;
    for (final q in questions) {
      final fieldname = q.getAttribute('fieldname') ?? '';
      final qtype = (q.getAttribute('type') ?? '').toLowerCase();
      final fieldtype = (q.getAttribute('fieldtype') ?? '').toLowerCase();
      final text = q.getElement('text')?.innerText.trim() ?? '';

      // Upsert question by (survey_id, fieldname)
      final existing = await _db!.query(
        'questions',
        where: 'survey_id=? AND fieldname=?',
        whereArgs: [surveyId, fieldname],
        limit: 1,
      );

      int qid;
      if (existing.isEmpty) {
        qid = await _db!.insert('questions', {
          'survey_id': surveyId,
          'fieldname': fieldname,
          'qtype': qtype,
          'fieldtype': fieldtype,
          'text': text,
          'position': pos,
        });
      } else {
        qid = existing.first['id'] as int;
        await _db!.update(
          'questions',
          {
            'qtype': qtype,
            'fieldtype': fieldtype,
            'text': text,
            'position': pos
          },
          where: 'id=?',
          whereArgs: [qid],
        );
      }

      // Options (if any)
      final responses = q.getElement('responses');
      int optPos = 0;
      if (responses != null) {
        for (final r in responses.findElements('response')) {
          final value = r.getAttribute('value') ?? '';
          final label = r.innerText.trim();

          final optRow = await _db!.query(
            'options',
            where: 'question_id=? AND value=?',
            whereArgs: [qid, value],
            limit: 1,
          );
          if (optRow.isEmpty) {
            await _db!.insert('options', {
              'question_id': qid,
              'value': value,
              'label': label,
              'position': optPos,
            });
          } else {
            await _db!.update(
              'options',
              {'label': label, 'position': optPos},
              where: 'id=?',
              whereArgs: [optRow.first['id']],
            );
          }
          optPos++;
        }
        // Note: we don't delete removed options here; add if you want strict sync.
      }

      pos++;
    }
  }

  static Future<void> _refreshQuestionsAndOptions(
      String surveyId, String xmlStr) async {
    // Simple approach: delete and reinsert everything for that survey’s structure
    await _db!.delete('options',
        where: 'question_id IN (SELECT id FROM questions WHERE survey_id=?)',
        whereArgs: [surveyId]);
    await _db!.delete('questions', where: 'survey_id=?', whereArgs: [surveyId]);
    await _upsertQuestionsAndOptions(surveyId, xmlStr);
  }

  /// Save one completed interview’s answers.
  /// - `surveyId`: the asset path id we stored in `surveys.id`
  /// - `answers`: your in-memory AnswerMap (fieldname -> value)
  /// - `questions`: the parsed questions (to map fieldname -> question_id)
  static Future<void> saveInterview({
    required String surveyId,
    required AnswerMap answers,
    required List<Question> questions,
  }) async {
    final db = _db!;
    final batch = db.batch();

    // Interview row
    final uniqueId = (answers['uniqueid'] ?? '').toString();
    if (uniqueId.isEmpty) {
      throw StateError('uniqueid (GUID) is required for interview saving.');
    }

    // Optional convenience: extract automatic timestamps if present in answers
    final starttime = answers['starttime']?.toString();
    final stoptime = answers['stoptime']?.toString();
    final lastmod = DateTime.now().toIso8601String();

    // upsert interview
    batch.insert(
      'interviews',
      {
        'id': uniqueId,
        'survey_id': surveyId,
        'starttime': starttime,
        'stoptime': stoptime,
        'lastmod': lastmod,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Build a map fieldname -> question_id
    final rows = await db.query('questions',
        columns: ['id', 'fieldname'],
        where: 'survey_id=?',
        whereArgs: [surveyId]);
    final qidByField = {
      for (final r in rows) r['fieldname'] as String: r['id'] as int
    };

    // One answer row per question that has an answer
    for (final q in questions) {
      final val = answers[q.fieldName];
      if (val == null) continue;

      final qid = qidByField[q.fieldName];
      if (qid == null) continue; // should not happen if sync ran

      String? valueText;
      String? valueJson;

      switch (q.type) {
        case QuestionType.checkbox:
          // store as JSON array
          final list = (val is List)
              ? val.map((e) => e.toString()).toList()
              : <String>[];
          valueJson = jsonEncode(list);
          break;
        default:
          valueText = val.toString();
          break;
      }

      batch.insert(
        'answers',
        {
          'interview_id': uniqueId,
          'question_id': qid,
          'value_text': valueText,
          'value_json': valueJson,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  /// Convenience: return the first survey id (useful if you have a single survey)
  static Future<String?> firstSurveyId() async {
    final rows = await _db!.query('surveys', orderBy: 'filename ASC', limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['id'] as String;
  }
}

class _ParsedSurvey {
  final String id; // surveys.id (asset path)
  final String filename;
  final List<Question> questions;
  _ParsedSurvey(
      {required this.id, required this.filename, required this.questions});
}
