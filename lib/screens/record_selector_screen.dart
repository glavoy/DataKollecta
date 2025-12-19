import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../services/db_service.dart';
import 'survey_screen.dart';
import '../services/survey_config_service.dart';
import '../services/question_cache_service.dart';

/// Screen for selecting an existing record to view/modify
class RecordSelectorScreen extends StatefulWidget {
  final String questionnaireFilename;

  const RecordSelectorScreen({
    super.key,
    required this.questionnaireFilename,
  });

  @override
  State<RecordSelectorScreen> createState() => _RecordSelectorScreenState();
}

class _RecordSelectorScreenState extends State<RecordSelectorScreen> {
  late Future<RecordSelectorData> _dataFuture;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String?> _selectedValues = {};
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<RecordSelectorData> _loadData() async {
    try {
      await DbService.init();

      final surveyConfig = SurveyConfigService();
      final surveyId = await surveyConfig.getActiveSurveyId();
      if (surveyId == null) throw Exception('No active survey found');

      final tableName =
          widget.questionnaireFilename.toLowerCase().replaceAll('.xml', '');

      final pkFields = await DbService.getPrimaryKeyFields(surveyId, tableName);
      final records = await DbService.getExistingRecords(surveyId, tableName);

      // Get display fields configuration from CRFs table
      final crfConfig = await DbService.getCrfConfig(surveyId, tableName);
      final displayFieldsStr = crfConfig?['display_fields']?.toString();
      final displayFields =
          displayFieldsStr?.split(',').map((s) => s.trim()).toList() ?? [];

      // Load question cache for label lookups
      final questionCache = QuestionCacheService();
      if (!questionCache.isLoadedForSurvey(surveyId)) {
        final manifest = await surveyConfig.getActiveSurveyManifest();
        if (manifest != null) {
          final xmlFiles =
              (manifest['xmlFiles'] as List?)?.cast<String>() ?? [];

          // Find the survey directory
          final surveysDir = await surveyConfig.getSurveysDirectory();
          final entities = await surveysDir.list().toList();
          for (final entity in entities) {
            if (entity is Directory) {
              final manifestPath = p.join(entity.path, 'survey_manifest.gistx');
              final manifestFile = File(manifestPath);
              if (await manifestFile.exists()) {
                // Check if this is the right survey directory
                final dirManifest =
                    jsonDecode(await manifestFile.readAsString());
                if (dirManifest['surveyId'] == surveyId) {
                  await questionCache.loadQuestionsForSurvey(
                    surveyId: surveyId,
                    surveyDirectory: entity.path,
                    xmlFiles: xmlFiles,
                  );
                  break;
                }
              }
            }
          }
        }
      }

      final idConfig = crfConfig?['idconfig']?.toString();

      return RecordSelectorData(
        tableName: tableName,
        primaryKeyFields: pkFields,
        records: records,
        displayFields: displayFields,
        idConfig: idConfig,
      );
    } catch (e) {
      debugPrint('Error loading data: $e');
      rethrow;
    }
  }

  /// Build unique options for a primary key field from all records
  List<String> _getUniqueValuesForField(
      List<Map<String, dynamic>> records, String fieldName) {
    final values = records
        .map((r) {
          final normalized = r.map((k, v) => MapEntry(k.toLowerCase(), v));
          return normalized[fieldName.toLowerCase()]?.toString() ?? '';
        })
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList();
    values.sort();
    return values;
  }

  /// Build display text for a dropdown item
  /// Format: "value - displayField1, displayField2" or just "value" if no display fields
  /// For composite keys (2+ fields): Only show display fields on non-first fields (e.g., linenum, not hhid)
  /// For single-field keys: Always show display fields if configured
  String _buildDisplayText({
    required String value,
    required String fieldName,
    required List<Map<String, dynamic>> records,
    required List<String> displayFields,
    required List<String> primaryKeyFields,
  }) {
    if (displayFields.isEmpty) {
      return value;
    }

    // For composite primary keys (2+ fields), only show display fields on non-first fields
    // e.g., show name for linenum (2nd field), but not for hhid (1st field)
    // For single-field primary keys, always show display fields
    final isFirstPrimaryKey =
        primaryKeyFields.isNotEmpty && fieldName == primaryKeyFields.first;
    final hasMultiplePrimaryKeys = primaryKeyFields.length > 1;

    if (isFirstPrimaryKey && hasMultiplePrimaryKeys) {
      return value;
    }

    // Find the record with this value for the current field
    final record = records.firstWhere(
      (r) {
        final normalized = r.map((k, v) => MapEntry(k.toLowerCase(), v));
        return normalized[fieldName.toLowerCase()]?.toString() == value;
      },
      orElse: () => {},
    );

    if (record.isEmpty) {
      return value;
    }

    // Build display text from display fields
    final displayParts = <String>[];
    final questionCache = QuestionCacheService();

    for (final displayField in displayFields) {
      // Use question cache to get label if using [[fieldname]] syntax
      final displayValue = questionCache.getDisplayValue(displayField, record);
      if (displayValue.isNotEmpty) {
        displayParts.add(displayValue);
      }
    }

    if (displayParts.isEmpty) {
      return value;
    }

    return '$value - ${displayParts.join(", ")}';
  }

  /// Filter records based on current selections
  List<Map<String, dynamic>> _getFilteredRecords(
      List<Map<String, dynamic>> allRecords, List<String> pkFields) {
    var filtered = allRecords;

    for (int i = 0; i < pkFields.length; i++) {
      final field = pkFields[i];
      final selectedValue = _selectedValues[field];

      if (selectedValue != null && selectedValue.isNotEmpty) {
        filtered = filtered.where((r) {
          // Normalize record keys
          final normalized = r.map((k, v) => MapEntry(k.toLowerCase(), v));
          return normalized[field.toLowerCase()]?.toString() == selectedValue;
        }).toList();
      }
    }

    return filtered;
  }

  /// Load the selected record into the survey screen
  Future<void> _loadRecord(RecordSelectorData data) async {
    setState(() {
      _errorMessage = null;
    });

    // STRICT CHECK: Ensure ALL primary key fields have a selection
    for (final field in data.primaryKeyFields) {
      if (_selectedValues[field] == null || _selectedValues[field]!.isEmpty) {
        setState(() {
          _errorMessage = 'Please select a value for ${field.toUpperCase()}.';
        });
        return;
      }
    }

    // Get the filtered records based on selections
    final filtered = _getFilteredRecords(data.records, data.primaryKeyFields);

    if (filtered.isEmpty) {
      setState(() {
        _errorMessage = 'No record found matching the selected criteria.';
      });
      return;
    }

    if (filtered.length > 1) {
      setState(() {
        _errorMessage =
            'Multiple records found. Please select values for all primary key fields.';
      });
      return;
    }

    // Exactly one record found - load it
    final record = filtered.first;
    final uniqueId = record['uniqueid']?.toString();

    if (uniqueId == null) {
      setState(() {
        _errorMessage = 'Record does not have a uniqueid field.';
      });
      return;
    }

    if (!mounted) return;

    // Navigate to survey screen with the loaded record
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SurveyScreen(
          questionnaireFilename: widget.questionnaireFilename,
          existingAnswers: record,
          uniqueId: uniqueId,
          primaryKeyFields: data.primaryKeyFields,
          idConfig: data.idConfig,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Record'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: FutureBuilder<RecordSelectorData>(
              future: _dataFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline,
                              size: 64, color: Colors.red),
                          const SizedBox(height: 16),
                          Text(
                            'Error loading records',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            snapshot.error.toString(),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final data = snapshot.data!;

                if (data.records.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.inbox_outlined,
                              size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          Text(
                            'No records found',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'There are no existing surveys to modify.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (data.primaryKeyFields.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.warning_outlined,
                              size: 64, color: Colors.orange),
                          const SizedBox(height: 16),
                          Text(
                            'Configuration Error',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No primary key defined in CRFs table for "${data.tableName}".',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Select Record to Modify',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Found ${data.records.length} existing records',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Primary key field selectors
                      ...data.primaryKeyFields.map((fieldName) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _buildFieldSelector(data, fieldName),
                        );
                      }),

                      const SizedBox(height: 16),

                      // Error message
                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Card(
                            color: Colors.red.shade50,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline,
                                      color: Colors.red),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: const TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // Load button
                      FilledButton.icon(
                        onPressed: () => _loadRecord(data),
                        icon: const Icon(Icons.edit_note),
                        label: const Text('View/Modify Survey'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFieldSelector(RecordSelectorData data, String fieldName) {
    // Get available values for this field based on previous selections
    final filteredRecords = _getFilteredRecords(
      data.records,
      data.primaryKeyFields
          .sublist(0, data.primaryKeyFields.indexOf(fieldName)),
    );
    final availableValues =
        _getUniqueValuesForField(filteredRecords, fieldName);

    // Auto-select if only one option exists and it's not already selected
    if (availableValues.length == 1 &&
        _selectedValues[fieldName] != availableValues.first) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _selectedValues[fieldName] = availableValues.first;
            // Clear subsequent fields to trigger their rebuild/auto-select if needed
            final currentIndex = data.primaryKeyFields.indexOf(fieldName);
            for (int i = currentIndex + 1;
                i < data.primaryKeyFields.length;
                i++) {
              _selectedValues[data.primaryKeyFields[i]] = null;
            }
          });
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          fieldName.toUpperCase(),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('dropdown_$fieldName${_selectedValues[fieldName]}'),
          decoration: InputDecoration(
            hintText: 'Select $fieldName',
            border: const OutlineInputBorder(),
          ),
          initialValue: _selectedValues[fieldName],
          items: availableValues
              .map((value) => DropdownMenuItem(
                    value: value,
                    child: Text(_buildDisplayText(
                      value: value,
                      fieldName: fieldName,
                      records: filteredRecords,
                      displayFields: data.displayFields,
                      primaryKeyFields: data.primaryKeyFields,
                    )),
                  ))
              .toList(),
          onChanged: (value) {
            setState(() {
              _selectedValues[fieldName] = value;
              _errorMessage = null;

              // Clear selections for fields after this one
              final currentIndex = data.primaryKeyFields.indexOf(fieldName);
              for (int i = currentIndex + 1;
                  i < data.primaryKeyFields.length;
                  i++) {
                _selectedValues[data.primaryKeyFields[i]] = null;
              }
            });
          },
        ),
      ],
    );
  }
}

/// Data container for record selector
class RecordSelectorData {
  final String tableName;
  final List<String> primaryKeyFields;
  final List<Map<String, dynamic>> records;
  final List<String> displayFields;
  final String? idConfig;

  RecordSelectorData({
    required this.tableName,
    required this.primaryKeyFields,
    required this.records,
    this.displayFields = const [],
    this.idConfig,
  });
}
