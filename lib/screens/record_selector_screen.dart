import 'package:flutter/material.dart';
import '../services/db_service.dart';
import 'survey_screen.dart';

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
      final tableName =
          widget.questionnaireFilename.toLowerCase().replaceAll('.xml', '');
      final pkFields = await DbService.getPrimaryKeyFields(tableName);
      final records = await DbService.getExistingRecords(tableName);

      return RecordSelectorData(
        tableName: tableName,
        primaryKeyFields: pkFields,
        records: records,
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
        .map((r) => r[fieldName]?.toString() ?? '')
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList();
    values.sort();
    return values;
  }

  /// Filter records based on current selections
  List<Map<String, dynamic>> _getFilteredRecords(
      List<Map<String, dynamic>> allRecords, List<String> pkFields) {
    var filtered = allRecords;

    for (int i = 0; i < pkFields.length; i++) {
      final field = pkFields[i];
      final selectedValue = _selectedValues[field];

      if (selectedValue != null && selectedValue.isNotEmpty) {
        filtered = filtered
            .where((r) => r[field]?.toString() == selectedValue)
            .toList();
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 120,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/branding/gistx.png',
                width: 100,
                height: 100,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Select Record'),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: FilledButton.tonal(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Back'),
            ),
          ),
        ],
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
    if (availableValues.length == 1 && _selectedValues[fieldName] != availableValues.first) {
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
                    child: Text(value),
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

  RecordSelectorData({
    required this.tableName,
    required this.primaryKeyFields,
    required this.records,
  });
}
