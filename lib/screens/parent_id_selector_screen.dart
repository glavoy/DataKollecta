import 'package:flutter/material.dart';
import '../services/db_service.dart';
import 'survey_screen.dart';

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

  const ParentIdSelectorScreen({
    super.key,
    required this.questionnaireFilename,
    required this.linkingField,
    required this.parentTable,
    this.incrementField,
    this.idConfig,
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

      // Get all records from the parent table
      final records = await DbService.getExistingRecords(widget.parentTable);

      // Extract unique linking field values
      final Set<String> ids = {};
      for (final record in records) {
        final id = record[widget.linkingField]?.toString();
        if (id != null && id.isNotEmpty) {
          ids.add(id);
        }
      }

      // Sort the IDs
      _availableIds = ids.toList()..sort();
      _filteredIds = List.from(_availableIds);

      if (_availableIds.isEmpty) {
        setState(() {
          _errorMessage =
              'No ${widget.linkingField} found in ${widget.parentTable} table.\n\nPlease complete a ${widget.parentTable} questionnaire first.';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading IDs: $e';
        _isLoading = false;
      });
    }
  }

  /// Filters the ID list based on search text
  void _filterIds(String searchText) {
    setState(() {
      if (searchText.isEmpty) {
        _filteredIds = List.from(_availableIds);
      } else {
        _filteredIds = _availableIds
            .where((id) => id.toLowerCase().contains(searchText.toLowerCase()))
            .toList();
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

    // If there's an increment field, calculate the next number
    if (widget.incrementField != null) {
      final nextNumber = await _getNextIncrementNumber(selectedId);
      prepopulatedAnswers[widget.incrementField!] = nextNumber;
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
        ),
      ),
    );
  }

  /// Gets the next increment number for a given parent ID
  Future<int> _getNextIncrementNumber(String parentId) async {
    try {
      // Get the table name from the questionnaire filename
      final tableName =
          widget.questionnaireFilename.toLowerCase().replaceAll('.xml', '');

      // Get all records for this parent ID
      final records = await DbService.getExistingRecords(tableName);

      // Find the maximum increment number for this parent ID
      int maxIncrement = 0;

      for (final record in records) {
        if (record[widget.linkingField]?.toString() == parentId) {
          final incrementValue = record[widget.incrementField];
          if (incrementValue != null) {
            final increment = int.tryParse(incrementValue.toString());
            if (increment != null && increment > maxIncrement) {
              maxIncrement = increment;
            }
          }
        }
      }

      return maxIncrement + 1;
    } catch (e) {
      debugPrint('Error getting next increment: $e');
      return 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Select ${widget.linkingField.toUpperCase()}'),
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
                          child: const Text('Go Back'),
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
                        'Select the ${widget.linkingField.toUpperCase()} for this questionnaire:',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      // Search box
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search ${widget.linkingField}...',
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
                        '${_filteredIds.length} ${widget.linkingField}(s) available',
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
                                  'No matching ${widget.linkingField} found',
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
                                      subtitle: widget.incrementField != null
                                          ? FutureBuilder<int>(
                                              future:
                                                  _getNextIncrementNumber(id),
                                              builder: (context, snapshot) {
                                                if (snapshot.hasData) {
                                                  return Text(
                                                    'Next ${widget.incrementField}: ${snapshot.data}',
                                                    style: TextStyle(
                                                      color: Colors.grey[600],
                                                    ),
                                                  );
                                                }
                                                return const SizedBox.shrink();
                                              },
                                            )
                                          : null,
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
