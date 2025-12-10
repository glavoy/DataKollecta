import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
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
  late Future<Map<String, dynamic>> _statsFuture;
  String? _resolvedSurveyId;

  @override
  void initState() {
    super.initState();
    debugPrint(
        'SummaryStatisticsScreen initialized with surveyId: "${widget.surveyId}"');
    _statsFuture = _loadStatistics();
  }

  Future<Map<String, dynamic>> _loadStatistics() async {
    // Resolve the actual survey ID from the name (which is what widget.surveyId likely is)
    final configService = SurveyConfigService();
    String? actualId = await configService.getSurveyId(widget.surveyId);

    // If not found by name, maybe it IS the ID?
    if (actualId == null) {
      // Check if the widget.surveyId is actually a valid ID (folder exists)
      // For now, assume if getSurveyId returns null, we try using the widget.surveyId as is
      actualId = widget.surveyId;
    }

    _resolvedSurveyId = actualId;
    debugPrint('Resolved Survey ID: "$actualId"');

    // Case-insensitive check
    if (!actualId.toLowerCase().startsWith('prism_css')) {
      debugPrint('Survey ID "$actualId" does not start with "prism_css"');
      return {};
    }

    try {
      final db = await DbService.getDatabaseForQueries(actualId);

      // 1. Number of households completed today
      // SQLite: strftime('%Y-%m-%d', starttime) = strftime('%Y-%m-%d', 'now', 'localtime')
      // Assuming starttime is ISO8601 string
      final countResult = await db.rawQuery('''
        SELECT count(*) as numhh 
        FROM hh_info 
        WHERE date(substr(starttime, 1, 10)) = date('now', 'localtime')
      ''');
      // Note: substr(starttime, 1, 10) extracts YYYY-MM-DD from ISO string if needed,
      // or just date(starttime) if it parses correctly.
      // Let's try date(starttime) first, but ISO string usually works with date().
      // Actually, to be safe with ISO strings like "2023-10-27T10:00:00.000", date() works.

      final numHouseholdsToday = Sqflite.firstIntValue(countResult) ?? 0;

      // 2. List of households completed today
      final hhListResult = await db.rawQuery('''
        SELECT 
            hh_info.hhid as hhid,
            (SELECT COUNT(*) FROM sleeping_structure WHERE hhid = hh_info.hhid) AS NumSleepingStructures,
            (SELECT COUNT(*) FROM hh_members WHERE hhid = hh_info.hhid) AS NumHHMembers,
            (SELECT COUNT(*) FROM nets WHERE hhid = hh_info.hhid) AS NumNets,
            CASE WHEN hh_info.enrolled = 1 THEN 'Enrolled' ELSE 'Not enrolled' END as EnrollmentStatus
        FROM hh_info
        WHERE date(substr(starttime, 1, 10)) = date('now', 'localtime')
        ORDER BY starttime DESC
      ''');

      // 3. Households with children between 2 and 10
      final childrenStatsResult = await db.rawQuery('''
        SELECT
          sub.mrcname,
          COUNT(sub.hhid) AS num_households
         FROM
           (
          SELECT DISTINCT mrcvillage.mrcname, hh_members.hhid
          FROM
              hh_members
          INNER JOIN
              mrcvillage
              ON CAST(hh_members.mrccode AS TEXT) = CAST(mrcvillage.mrccode AS TEXT)
          WHERE
              hh_members.hhid IN (
                  SELECT hhid
                  FROM hh_members
                  GROUP BY hhid
                  HAVING
                      SUM(CASE WHEN CAST(consent AS INTEGER) = 1 THEN 1 ELSE 0 END) > 0
                      AND
                      SUM(CASE WHEN CAST(age AS INTEGER) BETWEEN 2 AND 10 THEN 1 ELSE 0 END) > 0)
           ) AS sub
      GROUP BY
          sub.mrcname
      ''');
      // Note: Added CAST for join on mrccode just in case types differ (text vs int)

      return {
        'numHouseholdsToday': numHouseholdsToday,
        'recentHouseholds': hhListResult,
        'childrenStats': childrenStatsResult,
      };
    } catch (e) {
      debugPrint('Error loading statistics: $e');
      // Return empty or error state
      return {
        'error': e.toString(),
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Summary Statistics'),
            Text(
              _resolvedSurveyId ?? widget.surveyId,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _statsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            // Check if we should show placeholder based on resolved ID
            if (_resolvedSurveyId != null &&
                !_resolvedSurveyId!.toLowerCase().startsWith('prism_css')) {
              return _buildPlaceholder();
            }

            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Error loading statistics:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              );
            }

            final data = snapshot.data ?? {};
            if (data.containsKey('error')) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Error calculating statistics. Please ensure the survey database is initialized and contains the required tables (hh_info, sleeping_structure, hh_members, nets, mrcvillage).\n\nDetails: ${data['error']}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              );
            }

            return _buildStatisticsContent(data);
          },
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.analytics_outlined,
            size: 64,
            color:
                Theme.of(context).colorScheme.secondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Summary statistics will go here...',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsContent(Map<String, dynamic> data) {
    final int numHouseholds = data['numHouseholdsToday'] as int? ?? 0;
    final List<Map<String, dynamic>> recentHouseholds =
        (data['recentHouseholds'] as List<Map<String, dynamic>>?) ?? [];
    final List<Map<String, dynamic>> childrenStats =
        (data['childrenStats'] as List<Map<String, dynamic>>?) ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader('Households completed today: $numHouseholds'),
          if (recentHouseholds.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('No households completed today yet.'),
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: 350, // Increased height to show approx 5 items
                child: ListView.separated(
                  itemCount: recentHouseholds.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final hh = recentHouseholds[index];
                    return ListTile(
                      title: Text(
                        'HHID: ${hh['hhid']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'Structures: ${hh['NumSleepingStructures']} | Members: ${hh['NumHHMembers']} | Nets: ${hh['NumNets']}',
                      ),
                      trailing: Chip(
                        label: Text(
                          hh['EnrollmentStatus']?.toString() ?? 'Unknown',
                          style: const TextStyle(fontSize: 10),
                        ),
                        backgroundColor: hh['EnrollmentStatus'] == 'Enrolled'
                            ? Colors.green.withValues(alpha: 0.2)
                            : Colors.grey.withValues(alpha: 0.2),
                      ),
                    );
                  },
                ),
              ),
            ),
          const SizedBox(height: 24),
          _buildSectionHeader('Households with Children (2 - 10yr)'),
          if (childrenStats.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('No matching households found.'),
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: 350,
                child: ListView.separated(
                  itemCount: childrenStats.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final stat = childrenStats[index];
                    return ListTile(
                      leading: const Icon(Icons.location_on_outlined),
                      title: Text(stat['mrcname']?.toString() ?? 'Unknown'),
                      trailing: CircleAvatar(
                        child: Text('${stat['num_households']}'),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const Divider(),
        ],
      ),
    );
  }
}
