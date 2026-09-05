import 'package:flutter_test/flutter_test.dart';

import 'package:datakollecta/models/question.dart';
import 'package:datakollecta/services/survey_navigation_service.dart';

/// A base form whose `linkingfield` names its own generated primary key.
///
/// PRISM CSS declares `hh_info` with `primarykey = hhid`, `linkingfield =
/// hhid`, and an idconfig that builds `hhid` from four typed answers. That is
/// correct authoring: the SurveyGen README documents `linkingfield` on a base
/// form as the key *other* forms link on, and PRISM's three children do link
/// on `hhid`.
///
/// `isGeneratedIdField` excludes the linking field so a child's inherited
/// value is never overwritten by a generated one. On a base form nothing
/// supplies that value, so the exclusion refused to generate the very field
/// the idconfig existed to build: `AutoFields` then fell through to
/// `_defaultValueFor`, which returns `'-9'` for a text field. Every household
/// got the same id, and once `hh_info.hhid` carried a UNIQUE constraint the
/// second household's insert failed outright and the interview was lost.
///
/// The predicate itself is right and is unchanged. What was wrong was the
/// caller: `QuestionnaireSelectorScreen` passed `linkingField` for every form,
/// including ones with no parent to inherit anything from.
void main() {
  final hhid = Question(
    type: QuestionType.automatic,
    fieldName: 'hhid',
    fieldType: 'text',
  );

  test('a generated key is generated when no parent supplies it', () {
    expect(
      SurveyNavigationService.isGeneratedIdField(
        hhid,
        hasRegistryEntry: false,
        linkingField: null,
      ),
      isTrue,
    );
  });

  test('a linking value inherited from a parent is left alone', () {
    expect(
      SurveyNavigationService.isGeneratedIdField(
        hhid,
        hasRegistryEntry: false,
        linkingField: 'hhid',
      ),
      isFalse,
      reason: 'a child must keep the value its parent gave it',
    );
  });

  test('the exclusion is case-insensitive, as a hand-typed cell requires', () {
    expect(
      SurveyNavigationService.isGeneratedIdField(
        hhid,
        hasRegistryEntry: false,
        linkingField: 'HHID',
      ),
      isFalse,
    );
  });
}
