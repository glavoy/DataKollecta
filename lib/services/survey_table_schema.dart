import 'package:path/path.dart' as p;

import 'database_exception.dart';

/// Turns a `crfs` row into the SQL that creates a survey table.
///
/// Split out of `DbService`, which was 2,004 lines. Everything here is pure:
/// it takes plain maps and strings and returns SQL strings, and touches no
/// `Database`, no open-database registry and no file system. That is the whole
/// reason this is the piece that moved -- it is the half of the schema layer
/// whose behaviour can be pinned by a test that never opens a connection, and
/// `test/services/db_service_test.dart` pins it under the groups
/// `survey table constraints` and `orderByParentFirst`.
///
/// `DbService` still owns everything that resolves a `surveyId` to a
/// `Database`, the `try*`/`*In` seam pairs, and the failure policy around
/// them. This class only says what the SQL should be, never runs it.
///
/// **[quoteIdentifier] is a safety boundary, not a formatting helper.** Table
/// and column names come from a data dictionary and cannot be bound as
/// parameters, so they are interpolated into raw SQL; this is what stands
/// between that and an injected statement. Anything moved into or out of this
/// class must keep every dictionary-sourced identifier going through it.
class SurveyTableSchema {
  /// The child column holding its parent's immutable `uniqueid`.
  ///
  /// Kept here rather than imported from `AutoFields` so the schema layer has
  /// no dependency on the answer layer; the two are asserted equal by test.
  static const String parentUniqueIdColumn = 'parent_uniqueid';

  /// A SQLite identifier, ready to interpolate into a raw statement.
  ///
  /// Table and column names cannot be bound as parameters, so they have to be
  /// interpolated -- and every such name here comes from a data dictionary
  /// rather than from the code. Double-quoting covers every name SurveyGen can
  /// produce (it restricts FieldName to letters, digits and underscores); a
  /// name carrying a double quote is refused rather than escaped, because at
  /// that point the dictionary is wrong and guessing is worse than stopping.
  static String quoteIdentifier(String name) {
    if (name.isEmpty || name.contains('"')) {
      throw DatabaseException('Unusable SQL identifier: "$name".');
    }
    return '"$name"';
  }

  /// Splits a comma-separated `crfs` cell into trimmed, lowercased names.
  static List<String> _splitCrfsList(Object? cell) =>
      (cell?.toString() ?? '')
          .split(',')
          .map((s) => s.trim().toLowerCase())
          .where((s) => s.isNotEmpty)
          .toList();

  /// The statements that create [tableName] with the constraints its `crfs`
  /// row implies: `CREATE TABLE` first, then any indexes.
  ///
  /// Survey tables used to be created with every column as a bare `TEXT` and
  /// no constraint of any kind, so the parent/child relationship the `crfs`
  /// worksheet declares existed only as metadata the app remembered. Nothing
  /// stopped an orphan child, two households sharing an id, or a corrected
  /// parent key leaving its children behind.
  ///
  /// Three constraints, and one index, each with a different job:
  ///
  /// - **`uniqueid TEXT PRIMARY KEY`** on every table. This is the only one
  ///   that can never refuse a record -- it is a fresh v4 UUID -- and it is
  ///   what makes any other collision recoverable after the fact.
  /// - **A `UNIQUE` per column set a child actually references.** A foreign
  ///   key requires its referenced columns to be unique, so uniqueness is
  ///   declared exactly where a foreign key needs it and nowhere
  ///   speculatively. A leaf child gets none: see the index below.
  ///
  ///   Note this is *not* the same as `UNIQUE(primarykey)`. A real dictionary
  ///   links `vaccination_status` to `enrollee` on `barcode` -- a scanned
  ///   physical label -- while `enrollee` is keyed on `subjid`. Keying the
  ///   constraint to the primary key would have left that child with no
  ///   foreign key at all, so [referencedColumnSets] carries the sets the
  ///   children genuinely use.
  /// - **`FOREIGN KEY (linkingfield) REFERENCES parenttable(...) ON UPDATE
  ///   CASCADE`**, so correcting a parent's key carries to its children
  ///   instead of splitting the household across two ids.
  /// - **A plain, non-unique index** on `(<linkingfield>, <incrementfield>)`,
  ///   which serves the child counter's `MAX` query.
  ///
  /// **Why that index is not `UNIQUE`.** A duplicate `linenum` is a counter
  /// bug, not an identity clash: the interviewer never types it. Every row
  /// carries a `uniqueid` and every child its parent's, so parentage does not
  /// depend on the ordinal and a duplicate stays reconcilable. A `UNIQUE`
  /// there would make [saveInterview]'s `ConflictAlgorithm.abort` throw --
  /// turning a recoverable oddity into a lost interview, which in field
  /// research is the worse outcome. Duplicates are found with a report
  /// (`GROUP BY <link>, <inc> HAVING COUNT(*) > 1`), not by refusing a save.
  ///
  /// **When the foreign key cannot be declared.** Only when the linking
  /// columns are missing from either side. A child that names a column its
  /// parent does not have is created without the key and logged; SurveyGen
  /// and the portal both reject that at authoring time, which is where it
  /// belongs.
  ///
  /// [referencedColumnSets] is every distinct `linkingfield` column set that
  /// some child of this table declares, plus this table's own `primarykey`
  /// when it is a parent. Each becomes a `UNIQUE`.
  static List<String> buildSurveyTableStatements({
    required String tableName,
    required List<String> columnNames,
    Map<String, dynamic>? crf,
    Map<String, dynamic>? parentCrf,
    List<List<String>> referencedColumnSets = const [],
    void Function(String)? onSkippedConstraint,
  }) {
    final table = quoteIdentifier(tableName);
    final present = columnNames.map((c) => c.toLowerCase()).toSet();

    final colDefs = <String>[];
    for (final name in columnNames) {
      // uniqueid is declared as a question by every generated survey, so it
      // arrives here as an ordinary column. Promoting it in place keeps the
      // dictionary's column order intact.
      colDefs.add(name.toLowerCase() == 'uniqueid'
          ? '${quoteIdentifier(name)} TEXT PRIMARY KEY'
          : '${quoteIdentifier(name)} TEXT');
    }
    if (!present.contains('uniqueid')) {
      colDefs.add('uniqueid TEXT PRIMARY KEY');
    }
    if (!present.contains('synced_at')) {
      colDefs.add('synced_at DATETIME');
    }

    final linkingCols = _splitCrfsList(crf?['linkingfield']);
    final parentTable = crf?['parenttable']?.toString().trim() ?? '';
    final incrementField = crf?['incrementfield']?.toString().trim() ?? '';

    // The parent-side uniqueness a foreign key needs, and only that. One
    // UNIQUE per distinct column set some child references, deduped so a
    // table referenced on its primary key does not get the same constraint
    // twice.
    final declaredUnique = <String>{};
    for (final columns in referencedColumnSets) {
      final cols = columns.map((c) => c.toLowerCase()).toList();
      if (cols.isEmpty) continue;
      final signature = cols.join(',');
      if (!declaredUnique.add(signature)) continue;

      if (cols.every(present.contains)) {
        colDefs.add('UNIQUE(${cols.map(quoteIdentifier).join(', ')})');
      } else {
        onSkippedConstraint?.call(
            'Table "$tableName" is referenced on ($signature), but does not '
            'have every one of those columns -- no UNIQUE was declared, so '
            'children cannot reference it.');
      }
    }

    if (parentTable.isNotEmpty && linkingCols.isNotEmpty) {
      if (parentCrf == null) {
        onSkippedConstraint?.call(
            'Table "$tableName" declares parenttable "$parentTable", which is '
            'not a form in this survey -- no foreign key declared.');
      } else if (!linkingCols.every(present.contains)) {
        onSkippedConstraint?.call(
            'Table "$tableName" declares linkingfield '
            '(${linkingCols.join(',')}) but does not have every one of those '
            'columns -- no foreign key declared.');
      } else {
        // References the linking columns on the parent, which the parent
        // declares UNIQUE via its own referencedColumnSets. They need not be
        // the parent's primary key: enrollee is keyed on subjid but linked to
        // on barcode.
        final cols = linkingCols.map(quoteIdentifier).join(', ');
        colDefs.add('FOREIGN KEY ($cols) '
            'REFERENCES ${quoteIdentifier(parentTable)} ($cols) '
            'ON UPDATE CASCADE');
      }
    }

    // The second foreign key, and the one that cannot fail. `parent_uniqueid`
    // holds the parent's UUID, so unlike the linking value it can never
    // collide and never needs cascading -- the parent's own uniqueid is its
    // PRIMARY KEY, and a UUID is not something an interviewer can retype.
    //
    // Two keys with two jobs: this one is the structural guarantee that a
    // child belongs to a real parent, while the linkingfield key above exists
    // purely to carry a correction to the human-readable business key.
    //
    // Declared only when SurveyGen actually wrote the column, which it does
    // for exactly the forms that declare a parenttable.
    if (parentTable.isNotEmpty &&
        parentCrf != null &&
        present.contains(parentUniqueIdColumn)) {
      colDefs.add('FOREIGN KEY (${quoteIdentifier(parentUniqueIdColumn)}) '
          'REFERENCES ${quoteIdentifier(parentTable)} (uniqueid)');
    }

    final statements = <String>[
      'CREATE TABLE $table (${colDefs.join(', ')})',
    ];

    if (linkingCols.isNotEmpty &&
        incrementField.isNotEmpty &&
        linkingCols.every(present.contains) &&
        present.contains(incrementField.toLowerCase())) {
      final cols = [...linkingCols, incrementField.toLowerCase()]
          .map(quoteIdentifier)
          .join(', ');
      statements.add(
          'CREATE INDEX IF NOT EXISTS ${quoteIdentifier('idx_${tableName}_sibling')} '
          'ON $table ($cols)');
    }

    // A cascade rewrites child rows *behind the app's back*. It does not go
    // through updateInterview, so nothing clears `synced_at` and nothing
    // writes a formchanges row -- the device would be corrected while the
    // server kept the old key forever. That silent desync is arguably worse
    // than the visible orphaning the cascade fixes, so every cascading column
    // gets a trigger.
    //
    // The trigger, not Dart, is the right home for this precisely because the
    // hazard is that the cascade is invisible to Dart: correctness must not
    // depend on which code path happened to update the parent. An FK cascade
    // does fire an AFTER UPDATE trigger, with recursive_triggers on or off.
    if (colDefs.any((d) => d.startsWith('FOREIGN KEY')) &&
        linkingCols.every(present.contains)) {
      for (final col in linkingCols) {
        statements.add(_cascadeAuditTrigger(tableName: tableName, column: col));
      }
    }

    return statements;
  }

  /// The trigger that records a cascaded change to [column] of [tableName].
  ///
  /// Two writes, each load-bearing:
  ///
  /// - `synced_at = NULL` re-arms the row for upload. Pending is defined as
  ///   `synced_at IS NULL` (see `RecordUploader`), so without this the
  ///   corrected child never re-uploads.
  /// - A `formchanges` row, so the correction is auditable rather than
  ///   appearing out of nowhere on the server.
  ///
  /// `changeuniqueid` must be non-null or the uploader's
  /// `WHERE changeuniqueid IS NOT NULL` filter skips the row entirely. SQLite
  /// has no UUID function, so it is a random 16-byte hex string --
  /// `formchanges.formchanges_uuid` on the server is `text NOT NULL UNIQUE`
  /// with no format validation, so this needs no wire, Edge Function or
  /// Postgres change.
  ///
  /// `surveyor_id` is deliberately left null: `app-sync` derives it from the
  /// session and explicitly ignores whatever the client sends.
  ///
  /// The `WHEN` guard is what stops the inner `UPDATE` re-entering this
  /// trigger on its own `synced_at` write.
  static String _cascadeAuditTrigger({
    required String tableName,
    required String column,
  }) {
    final table = quoteIdentifier(tableName);
    final col = quoteIdentifier(column);
    final name = quoteIdentifier('trg_${tableName}_${column}_cascade');
    // Single-quoted literals carry the table and column names into the
    // formchanges row. Both come from a data dictionary, so they go through
    // the identifier guard above before reaching this point; SurveyGen
    // restricts them to letters, digits and underscores.
    final tableLiteral = "'$tableName'";
    final colLiteral = "'$column'";

    return '''
CREATE TRIGGER IF NOT EXISTS $name
AFTER UPDATE OF $col ON $table
FOR EACH ROW WHEN OLD.$col IS NOT NEW.$col
BEGIN
  UPDATE $table SET synced_at = NULL WHERE rowid = NEW.rowid;
  INSERT INTO formchanges
    (tablename, fieldname, uniqueid, oldvalue, newvalue, changeuniqueid)
  VALUES
    ($tableLiteral, $colLiteral, NEW.uniqueid, OLD.$col, NEW.$col,
     lower(hex(randomblob(16))));
END''';
  }

  /// Every column set that must be `UNIQUE` on [tableName] for its children's
  /// foreign keys to be declarable.
  ///
  /// That is each distinct `linkingfield` set declared by a form naming
  /// [tableName] as its `parenttable`, plus [tableName]'s own `primarykey`
  /// when it has children at all -- the primary key is what `IdGenerator`'s
  /// counter and the duplicate check both assume is unique.
  ///
  /// Keyed on what children *reference* rather than on the primary key
  /// because the two are not always the same: AVERT links
  /// `vaccination_status` to `enrollee` on `barcode`, a scanned physical
  /// label, while `enrollee` is keyed on `subjid`. Declaring uniqueness only
  /// over the primary key would have left that child with no foreign key.
  static List<List<String>> referencedColumnSetsFor(
    String tableName,
    Map<String, Map<String, dynamic>> crfsByTable,
  ) {
    final sets = <String, List<String>>{};

    void add(List<String> cols) {
      if (cols.isEmpty) return;
      sets.putIfAbsent(cols.join(','), () => cols);
    }

    var hasChildren = false;
    for (final other in crfsByTable.values) {
      final parent =
          other['parenttable']?.toString().trim().toLowerCase() ?? '';
      if (parent != tableName.toLowerCase()) continue;
      hasChildren = true;
      add(_splitCrfsList(other['linkingfield']));
    }

    if (hasChildren) {
      add(_splitCrfsList(crfsByTable[tableName.toLowerCase()]?['primarykey']));
    }

    return sets.values.toList();
  }

  /// Orders [xmlFiles] so a form is created after its parent.
  ///
  /// SQLite resolves a foreign key's target lazily, so a child created first
  /// is not itself an error -- but the schema reads better in dependency
  /// order, and a cycle (which SurveyGen rejects) surfaces here as leftovers
  /// rather than as a puzzle at insert time.
  static List<String> orderByParentFirst(
    List<String> xmlFiles,
    Map<String, Map<String, dynamic>> crfsByTable,
  ) {
    String tableOf(String xml) =>
        p.basename(xml).toLowerCase().replaceAll('.xml', '');

    final remaining = List<String>.from(xmlFiles);
    final ordered = <String>[];
    final placed = <String>{};

    while (remaining.isNotEmpty) {
      final ready = remaining.where((xml) {
        final parent = crfsByTable[tableOf(xml)]?['parenttable']
                ?.toString()
                .trim()
                .toLowerCase() ??
            '';
        // Ready when it has no parent, its parent is already placed, or its
        // parent is not a form in this survey at all.
        return parent.isEmpty ||
            placed.contains(parent) ||
            !crfsByTable.containsKey(parent);
      }).toList();

      if (ready.isEmpty) {
        // A cycle. Emit the rest in their original order rather than looping.
        ordered.addAll(remaining);
        break;
      }

      for (final xml in ready) {
        ordered.add(xml);
        placed.add(tableOf(xml));
        remaining.remove(xml);
      }
    }

    return ordered;
  }
}
