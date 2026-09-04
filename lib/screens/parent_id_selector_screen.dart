import 'package:flutter/material.dart';
import '../services/db_service.dart';
import 'survey_screen.dart';
import '../services/survey_config_service.dart';
import '../services/question_cache_service.dart';
import '../config/app_config.dart';
import '../services/app_strings.dart';

/// Screen for selecting a parent ID before starting a linked questionnaire
///
/// This screen is shown when a questionnaire has requireslink = 1 in the crfs table.
/// It displays a list of existing parent IDs that the user can select from,
/// or allows manual entry with validation.
class ParentIdSelectorScreen extends StatefulWidget {
  final String questionnaireFilename;
  final String linkingField;
  final String parentTable;
  final String? incrementField;
  final String? idConfig;
  final String? entryCondition;
  final String? displayFields;

  const ParentIdSelectorScreen({
    super.key,
    required this.questionnaireFilename,
    required this.linkingField,
    required this.parentTable,
    this.incrementField,
    this.idConfig,
    this.entryCondition,
    this.displayFields,
  });

  @override
  State<ParentIdSelectorScreen> createState() => _ParentIdSelectorScreenState();
}

class _ParentIdSelectorScreenState extends State<ParentIdSelectorScreen> {
  List<String> _availableIds = [];
  String? _selectedId;
  bool _isLoading = true;
  String? _errorMessage;
  final TextEditingController _searchController = TextEditingController();
  List<String> _filteredIds = [];
  static const AppStrings _s = AppStrings(AppConfig.isFrench);

  /// Display-field subtitle text per linking value (e.g. participant's name)
  final Map<String, String> _subtitleByLinkingValue = {};

  /// The next increment value per linking value, resolved once in
  /// [_loadAvailableIds]. A parent absent from the map has no children yet.
  ///
  /// Held as state rather than fetched from the subtitle's builder: the
  /// previous `FutureBuilder(future: _getNextIncrementNumber(id))` was
  /// constructed inside `build`, so it launched a fresh full-table read for
  /// every visible row on every rebuild -- including on each keystroke in the
  /// search box.
  final Map<String, int> _nextIncrementByLinkingValue = {};

  /// True when the increment could not be read at all, so the subtitle shows
  /// nothing rather than a number that is really a guess.
  bool _incrementReadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadAvailableIds();
  }


  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Loads available parent IDs from the database
  Future<void> _loadAvailableIds() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      // Get active survey ID
      final surveyConfig = SurveyConfigService();
      final surveyId = await surveyConfig.getActiveSurveyId();
      if (surveyId == null) throw Exception('No active survey found');

      // Get all records from the parent table
      final records =
          await DbService.getExistingRecords(surveyId, widget.parentTable);

      final uniqueIds = <String>{};
      // Keep the (normalized) parent record per linking value so we can show
      // display_fields (e.g. the participant's name) next to each ID.
      final Map<String, Map<String, dynamic>> recordByValue = {};
      _subtitleByLinkingValue.clear();

      // Parse the configured display fields (same format as record selector)
      final displayFields = widget.displayFields
              ?.split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList() ??
          [];

      // Parse entry condition if present
      String? conditionField;
      String? conditionValue;
      if (widget.entryCondition != null &&
          widget.entryCondition!.contains('=')) {
        final parts = widget.entryCondition!.split('=');
        if (parts.length == 2) {
          conditionField = parts[0].trim().toLowerCase();
          conditionValue = parts[1].trim();
        }
      }

      for (final record in records) {
        // Normalize keys to lowercase for case-insensitive lookup
        final normalizedRecord =
            record.map((k, v) => MapEntry(k.toLowerCase(), v));

        // Check entry condition if defined
        if (conditionField != null && conditionValue != null) {
          final recordValue = normalizedRecord[conditionField]?.toString();
          // Simple string comparison
          if (recordValue != conditionValue) {
            continue; // Skip this record if condition not met
          }
        }

        final val = normalizedRecord[widget.linkingField.toLowerCase()];
        if (val != null && val.toString().isNotEmpty) {
          final id = val.toString();
          if (uniqueIds.add(id)) {
            // First record wins for a given linking value
            recordByValue[id] = normalizedRecord;
          }
        }
      }

      // Build the display-field subtitles (resolved against the parent record)
      if (displayFields.isNotEmpty) {
        await QuestionCacheService().ensureLoadedForSurvey(surveyId);
        final questionCache = QuestionCacheService();
        for (final entry in recordByValue.entries) {
          final parts = <String>[];
          for (final field in displayFields) {
            // Skip the linking field itself - it is already shown as the title
            final plainName =
                RegExp(r'^\[\[(.+?)\]\]$').firstMatch(field)?.group(1) ?? field;
            if (plainName.toLowerCase() == widget.linkingField.toLowerCase()) {
              continue;
            }
            final value = questionCache.getDisplayValue(field, entry.value);
            if (value.isNotEmpty) parts.add(value);
          }
          if (parts.isNotEmpty) {
            _subtitleByLinkingValue[entry.key] = parts.join(', ');
          }
        }
      }

      // Resolve every parent's next increment in one grouped query, rather
      // than one query per parent (or, as before, a full-table read per
      // visible row per rebuild).
      _nextIncrementByLinkingValue.clear();
      _incrementReadFailed = false;
      if (widget.incrementField != null && widget.incrementField!.isNotEmpty) {
        final childTable =
            widget.questionnaireFilename.toLowerCase().replaceAll('.xml', '');
        final nextValues = await DbService.tryGetNextIncrementValues(
          surveyId: surveyId,
          tableName: childTable,
          incrementField: widget.incrementField!,
          linkingField: widget.linkingField,
        );
        if (nextValues == null) {
          _incrementReadFailed = true;
        } else {
          _nextIncrementByLinkingValue.addAll(nextValues);
        }
      }

      // Sort the IDs
      _availableIds = uniqueIds.toList()..sort();
      _filteredIds = List.from(_availableIds);

      if (_availableIds.isEmpty) {
        setState(() {
          _errorMessage = _s.noEligibleIds(
            widget.linkingField,
            widget.parentTable,
            widget.entryCondition,
          );
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = _s.errorLoadingIds(e);
        _isLoading = false;
      });
    }
  }

  /// Ensures the question cache is loaded so [[fieldname]] display values
  /// can be resolved to their option labels. Mirrors RecordSelectorScreen.
  /// Filters the ID list based on search text
  void _filterIds(String searchText) {
    setState(() {
      if (searchText.isEmpty) {
        _filteredIds = List.from(_availableIds);
      } else {
        final query = searchText.toLowerCase();
        _filteredIds = _availableIds.where((id) {
          if (id.toLowerCase().contains(query)) return true;
          // Also match the display-field subtitle (e.g. participant's name)
          final subtitle = _subtitleByLinkingValue[id];
          return subtitle != null && subtitle.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  /// Handles ID selection and navigates to the survey
  Future<void> _onIdSelected(String selectedId) async {
    setState(() {
      _selectedId = selectedId;
    });

    // Prepare the pre-populated answers map
    final Map<String, dynamic> prepopulatedAnswers = {
      widget.linkingField: selectedId,
    };

    // If there's an increment field, carry the next number through. Note that
    // `SurveyScreen._calculateLineNum` recomputes and overwrites this for a
    // new record, so this value is advisory; it is passed so the child is not
    // briefly missing a field the questionnaire declares.
    //
    // Stored as a String, matching what `_calculateLineNum` writes. This used
    // to pass an int, so the same column arrived with two different Dart
    // types depending on which screen the interviewer came through.
    if (widget.incrementField != null) {
      final nextNumber = _nextIncrementByLinkingValue[selectedId] ?? 1;
      prepopulatedAnswers[widget.incrementField!] = nextNumber.toString();
    }

    if (!mounted) return;

    // Navigate to the survey screen with pre-populated answers
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => SurveyScreen(
          questionnaireFilename: widget.questionnaireFilename,
          prepopulatedAnswers: prepopulatedAnswers,
          idConfig: widget.idConfig,
          linkingField: widget.linkingField,
          incrementField: widget.incrementField,
        ),
      ),
    );
  }

  /// Builds the list-item subtitle: the configured display_fields text
  /// (e.g. the participant's name) and, for repeating children, the next
  /// increment number. Returns null when there is nothing to show.
  Widget? _buildSubtitle(String id) {
    final displayText = _subtitleByLinkingValue[id];

    final children = <Widget>[
      if (displayText != null && displayText.isNotEmpty)
        Text(
          displayText,
          style: TextStyle(color: Colors.grey[700]),
        ),
      if (widget.incrementField != null && !_incrementReadFailed)
        Text(
          _s.nextIncrement(
              widget.incrementField!, _nextIncrementByLinkingValue[id] ?? 1),
          style: TextStyle(color: Colors.grey[600]),
        ),
    ];

    if (children.isEmpty) return null;
    if (children.length == 1) return children.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_s.selectFieldTitle(widget.linkingField)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 64,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(_s.goBack),
                        ),
                      ],
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _s.selectFieldInstruction(widget.linkingField),
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      // Search box
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: _s.searchField(widget.linkingField),
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    _filterIds('');
                                  },
                                )
                              : null,
                        ),
                        onChanged: _filterIds,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _s.availableCount(_filteredIds.length, widget.linkingField),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // ID list
                      Expanded(
                        child: _filteredIds.isEmpty
                            ? Center(
                                child: Text(
                                  _s.noMatchingField(widget.linkingField),
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 16,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: _filteredIds.length,
                                itemBuilder: (context, index) {
                                  final id = _filteredIds[index];
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      title: Text(
                                        id,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      subtitle: _buildSubtitle(id),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () => _onIdSelected(id),
                                      selected: _selectedId == id,
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
