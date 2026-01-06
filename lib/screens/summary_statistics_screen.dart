import 'package:flutter/material.dart';
import '../services/db_service.dart';
import '../services/survey_config_service.dart';

class SummaryStatisticsScreen extends StatefulWidget {
  final String surveyId;

  const SummaryStatisticsScreen({super.key, required this.surveyId});

  @override
  State<SummaryStatisticsScreen> createState() =>
      _SummaryStatisticsScreenState();
}

class _SummaryStatisticsScreenState extends State<SummaryStatisticsScreen> {
  late Future<List<Map<String, dynamic>>> _statsFuture;
  String? _resolvedSurveyId;

  @override
  void initState() {
    super.initState();
    _statsFuture = _loadStatistics();
  }

  Future<List<Map<String, dynamic>>> _loadStatistics() async {
    final configService = SurveyConfigService();
    String? actualId = await configService.getSurveyId(widget.surveyId);

    if (actualId == null) {
      actualId = widget.surveyId;
    }

    _resolvedSurveyId = actualId;
    final stats = <Map<String, dynamic>>[];

    try {
      final db = await DbService.getDatabaseForQueries(actualId);

      // Get all surveys from the crfs table
      final surveys = await db.query('crfs', orderBy: 'display_order ASC');

      for (final survey in surveys) {
        final tableName = survey['tablename'] as String?;
        final displayName =
            survey['displayname'] as String? ?? tableName ?? 'Unknown';

        if (tableName == null) continue;

        int totalCount = 0;
        int todayCount = 0;

        try {
          // Count total records
          final totalResult =
              await db.rawQuery('SELECT COUNT(*) as count FROM $tableName');
          if (totalResult.isNotEmpty) {
            totalCount = totalResult.first['count'] as int? ?? 0;
          }

          // Count records completed today
          // starttime is ISO8601 string, e.g., "2023-10-27T10:00:00.000"
          final todayResult = await db.rawQuery('''
            SELECT COUNT(*) as count FROM $tableName 
            WHERE date(substr(starttime, 1, 10)) = date('now', 'localtime')
          ''');
          if (todayResult.isNotEmpty) {
            todayCount = todayResult.first['count'] as int? ?? 0;
          }
        } catch (e) {
          debugPrint('Error counting records for $tableName: $e');
          // If table doesn't exist or doesn't have starttime, we just show 0 or error state
        }

        stats.add({
          'displayName': displayName,
          'tableName': tableName,
          'totalCount': totalCount,
          'todayCount': todayCount,
        });
      }
    } catch (e) {
      debugPrint('Error loading statistics: $e');
      rethrow;
    }

    return stats;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Summary Statistics'),
            if (_resolvedSurveyId != null)
              Text(
                _resolvedSurveyId!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                ),
              ),
          ],
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _statsFuture = _loadStatistics();
            });
          },
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _statsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading statistics',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                );
              }

              final stats = snapshot.data ?? [];

              if (stats.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.analytics_outlined,
                        size: 64,
                        color: theme.colorScheme.secondary.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No surveys found in this configuration.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.secondary.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16.0),
                itemCount: stats.length,
                itemBuilder: (context, index) {
                  final item = stats[index];
                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 12.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color:
                            theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.description_outlined,
                                color: theme.colorScheme.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item['displayName'],
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _buildStatItem(
                                theme,
                                'Completed Today',
                                item['todayCount'].toString(),
                                Icons.today_outlined,
                                theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 16),
                              _buildStatItem(
                                theme,
                                'Total Completed',
                                item['totalCount'].toString(),
                                Icons.summarize_outlined,
                                theme.colorScheme.secondary,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(
    ThemeData theme,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
