import 'package:GiSTX/config/app_config.dart';
import 'package:GiSTX/models/question.dart';
import 'package:GiSTX/services/csv_data_service.dart';
import 'package:GiSTX/widgets/question_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The language is fixed when the app is built, so these expectations follow
/// the build flavor. Run the suite twice to cover both:
///
///     flutter test
///     flutter test --dart-define=GISTX_COUNTRY="Burkina Faso"
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final expectedDontKnow = AppConfig.isFrench ? 'Ne sait pas' : "Don't know";
  final expectedRefuse =
      AppConfig.isFrench ? 'Refuse de répondre' : 'Refuse to answer';
  final unexpectedDontKnow = AppConfig.isFrench ? "Don't know" : 'Ne sait pas';
  final unexpectedRefuse =
      AppConfig.isFrench ? 'Refuse to answer' : 'Refuse de répondre';

  testWidgets('radio special responses use the build language', (tester) async {
    final answers = <String, dynamic>{};

    await tester.pumpQuestionView(
      question: _specialResponseQuestion(QuestionType.radio),
      answers: answers,
    );

    expect(find.text(expectedDontKnow), findsOneWidget);
    expect(find.text(expectedRefuse), findsOneWidget);
    expect(find.text(unexpectedDontKnow), findsNothing);
    expect(find.text(unexpectedRefuse), findsNothing);

    await tester.tap(find.text(expectedDontKnow));
    await tester.pump();

    expect(answers['special_field'], '-7');
  });

  testWidgets('checkbox special responses use the build language',
      (tester) async {
    final answers = <String, dynamic>{};

    await tester.pumpQuestionView(
      question: _specialResponseQuestion(QuestionType.checkbox),
      answers: answers,
    );

    expect(find.text(expectedDontKnow), findsOneWidget);
    expect(find.text(expectedRefuse), findsOneWidget);
    expect(find.text(unexpectedDontKnow), findsNothing);
    expect(find.text(unexpectedRefuse), findsNothing);

    await tester.tap(find.text(expectedRefuse));
    await tester.pump();

    expect(answers['special_field'], ['-8']);
  });

  testWidgets('the regular option keeps its own label', (tester) async {
    await tester.pumpQuestionView(
      question: _specialResponseQuestion(QuestionType.radio),
      answers: <String, dynamic>{},
    );

    // Only the special responses are relabelled; ordinary options are not.
    expect(find.text('Regular response'), findsOneWidget);
  });
}

extension on WidgetTester {
  Future<void> pumpQuestionView({
    required Question question,
    required Map<String, dynamic> answers,
  }) async {
    await pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuestionView(
            question: question,
            answers: answers,
            csvDataService: CsvDataService(),
            surveyId: 'test-survey',
          ),
        ),
      ),
    );
    await pumpAndSettle();
  }
}

Question _specialResponseQuestion(QuestionType type) {
  return Question(
    type: type,
    fieldName: 'special_field',
    fieldType: 'text',
    text: 'Special response question',
    dontKnow: '-7',
    refuse: '-8',
    options: [
      QuestionOption(value: '1', label: 'Regular response'),
      QuestionOption(value: '-7', label: "Don't know"),
      QuestionOption(value: '-8', label: 'Refuse to answer'),
    ],
  );
}
