import 'package:flutter_test/flutter_test.dart';

import 'package:datakollecta/services/repeat_plan_service.dart';

/// Which child forms auto-repeat after a parent is saved, and how many times.
///
/// Extracted from `SurveyScreen._checkAndStartAutoRepeat`, where every one of
/// these decisions was a silent `continue` inside a loop that also drove
/// dialogs and pushed screens. The silence is deliberate -- a form with no
/// declared count is simply not auto-repeated, and the interviewer starts it by
/// hand -- but it means a mis-authored dictionary produces no repeat and no
/// message, so these are the cases most worth having written down.

Map<String, dynamic> crf({
  String? tablename = 'hh_members',
  String? parenttable = 'hh_info',
  Object? autoStartRepeat = 2,
  String? repeatCountField = 'nmembers',
  String? linkingfield = 'hhid',
  String? displayname = 'Household Members',
  int displayOrder = 1,
}) =>
    {
      'tablename': tablename,
      'parenttable': parenttable,
      'auto_start_repeat': autoStartRepeat,
      'repeat_count_field': repeatCountField,
      'linkingfield': linkingfield,
      'displayname': displayname,
      'display_order': displayOrder,
    };

List<RepeatPlanItem> planFor(
  List<Map<String, dynamic>> crfs, {
  Map<String, dynamic>? answers,
}) =>
    RepeatPlanService.plan(
      crfs: crfs,
      parentTableName: 'hh_info',
      answers: answers ?? {'hhid': '1010001', 'nmembers': '5'},
    );

void main() {
  group('the ordinary path', () {
    test('a declared child is planned with its count and linking value', () {
      final plan = planFor([crf()]);

      expect(plan, hasLength(1));
      expect(plan.single.childTableName, 'hh_members');
      expect(plan.single.displayName, 'Household Members');
      expect(plan.single.linkingField, 'hhid');
      expect(plan.single.linkingValue, '1010001');
      expect(plan.single.repeatCount, 5);
      expect(plan.single.autoStartRepeat, 2);
    });

    test('the whole crfs row is carried through', () {
      // The repeat loop reads repeat_enforce_count and the entity names off it.
      final row = crf();

      expect(planFor([row]).single.crf, same(row));
    });

    test('falls back to the table name when there is no display name', () {
      final plan = planFor([crf(displayname: null)]);

      expect(plan.single.displayName, 'hh_members');
    });

    test('accepts auto_start_repeat as a string as well as an int', () {
      // SQLite hands back an int; a manifest that quoted it gives a String.
      expect(planFor([crf(autoStartRepeat: '2')]).single.autoStartRepeat, 2);
      expect(planFor([crf(autoStartRepeat: 1)]).single.autoStartRepeat, 1);
    });
  });

  group('ordering', () {
    test('children are planned in display_order, not crfs order', () {
      final plan = planFor([
        crf(tablename: 'nets', repeatCountField: 'nnets', displayOrder: 3),
        crf(tablename: 'hh_members', displayOrder: 1),
        crf(
            tablename: 'sleeping_structure',
            repeatCountField: 'nstructures',
            displayOrder: 2),
      ], answers: {
        'hhid': '1010001',
        'nmembers': '5',
        'nnets': '2',
        'nstructures': '3',
      });

      expect(
        plan.map((i) => i.childTableName),
        ['hh_members', 'sleeping_structure', 'nets'],
      );
    });

    test('a missing display_order sorts as 0', () {
      final withOrder = crf(tablename: 'nets', repeatCountField: 'nnets');
      final withoutOrder = crf(tablename: 'hh_members')..remove('display_order');

      final plan = planFor([withOrder, withoutOrder],
          answers: {'hhid': '1010001', 'nmembers': '5', 'nnets': '2'});

      expect(plan.first.childTableName, 'hh_members');
    });
  });

  group('the four ways a child drops out, silently', () {
    test('no repeat count field declared', () {
      expect(planFor([crf(repeatCountField: null)]), isEmpty);
      expect(planFor([crf(repeatCountField: '')]), isEmpty);
    });

    test('the count field has no answer', () {
      expect(
        planFor([crf()], answers: {'hhid': '1010001'}),
        isEmpty,
      );
    });

    test('the count is zero, negative or not a number', () {
      for (final count in ['0', '-1', 'lots', '']) {
        expect(
          planFor([crf()], answers: {'hhid': '1010001', 'nmembers': count}),
          isEmpty,
          reason: 'count "$count" should not produce a repeat',
        );
      }
    });

    test('no linking field, or no value for it', () {
      expect(planFor([crf(linkingfield: null)]), isEmpty);
      expect(
        planFor([crf()], answers: {'nmembers': '5'}),
        isEmpty,
      );
    });
  });

  group('what is not a child of this form', () {
    test('a form belonging to a different parent', () {
      expect(planFor([crf(parenttable: 'somewhere_else')]), isEmpty);
    });

    test('a base form, with no parent at all', () {
      expect(planFor([crf(parenttable: null)]), isEmpty);
    });

    test('a child that does not auto-start', () {
      expect(planFor([crf(autoStartRepeat: 0)]), isEmpty);
      expect(planFor([crf(autoStartRepeat: null)]), isEmpty);
      expect(planFor([crf(autoStartRepeat: 'not a number')]), isEmpty);
    });

    test('a row with no table name', () {
      expect(planFor([crf(tablename: null)]), isEmpty);
    });

    test('an empty crfs table', () {
      expect(planFor([]), isEmpty);
    });
  });

  group('several children', () {
    test('only the ones that qualify are planned', () {
      final plan = planFor([
        crf(tablename: 'hh_members', displayOrder: 1),
        // No count answered.
        crf(tablename: 'nets', repeatCountField: 'nnets', displayOrder: 2),
        crf(
            tablename: 'sleeping_structure',
            repeatCountField: 'nstructures',
            displayOrder: 3),
      ], answers: {
        'hhid': '1010001',
        'nmembers': '5',
        'nstructures': '3',
      });

      expect(
        plan.map((i) => i.childTableName),
        ['hh_members', 'sleeping_structure'],
      );
    });
  });
}
