import 'package:flutter/material.dart';
import 'models/question.dart';
import 'services/survey_loader.dart';
import 'widgets/question_views.dart';

void main() {
  runApp(const SurveyApp());
}

class SurveyApp extends StatefulWidget {
  const SurveyApp({super.key});

  @override
  State<SurveyApp> createState() => _SurveyAppState();
}

class _SurveyAppState extends State<SurveyApp> {
  final AnswerMap _answers = {};
  int _index = 0;
  late Future<List<Question>> _futureSurvey;

  @override
  void initState() {
    super.initState();
    _futureSurvey = SurveyLoader.loadFromAsset('assets/surveys/survey.xml');
  }

  void _next(List<Question> qs) {
    if (_index < qs.length - 1) {
      setState(() => _index++);
    }
  }

  void _prev() {
    if (_index > 0) {
      setState(() => _index--);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GiSTX',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        scaffoldBackgroundColor: const Color(0xFFF7F7FA),
        cardTheme: CardThemeData(
          elevation: 2,
          margin: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
        listTileTheme: const ListTileThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          tileColor: Colors.white,
        ),
      ),
      home: FutureBuilder<List<Question>>(
        future: _futureSurvey,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          if (snap.hasError) {
            return Scaffold(body: Center(child: Text('Error: ${snap.error}')));
          }

          final questions = snap.data!;
          final q = questions[_index];
          final isFirst = _index == 0;
          final isLast = _index == questions.length - 1;
          final progress = (_index + 1) / questions.length;

          return Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  Image.asset(
                    'assets/branding/gistx.png',
                    width: 100,
                    height: 100,
                  ),
                  const SizedBox(width: 10),
                  // const Text("Geoff's Dart Questionnaire"), // or your new name
                ],
              ),
            ),
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header with progress
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                        'Step ${_index + 1} of ${questions.length}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    const Spacer(),
                                    Text('${(progress * 100).round()}%',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                      value: progress, minHeight: 8),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Animated question card
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            child: Card(
                              key: ValueKey(q
                                  .fieldName), // forces fresh state per question
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: SingleChildScrollView(
                                  child: QuestionView(
                                    key: ValueKey('view_${q.fieldName}'),
                                    question: q,
                                    answers: _answers,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Nav bar
                        Row(
                          children: [
                            if (!isFirst)
                              OutlinedButton.icon(
                                onPressed: _prev,
                                icon: const Icon(Icons.arrow_back),
                                label: const Text('Previous'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 18, vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            if (!isFirst) const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => isLast
                                    ? _showDone(context)
                                    : _next(questions),
                                icon: Icon(
                                    isLast ? Icons.check : Icons.arrow_forward),
                                label: Text(isLast ? 'Finish' : 'Next'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 18, vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showDone(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('All done!'),
        content: Text('Thanks. Answers:\n${_answers.toString()}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'))
        ],
      ),
    );
  }
}
