// Multi-device e2e, phase C — runs on DEVICE A again (the owner).
//
// `flutter test integration_test` reinstalls the app per run, so this
// phase exercises the real "owner gets a new phone" story rather than a
// warm relaunch: sign in as the same account on a fresh install, recover
// the shared list from the server, observe the editor's phase-B edit,
// then rename the list through the lists-overview UI and prove the
// rename reaches the server.
//
// Requires --dart-define=MD_LIST_ID and MD_EDITOR_KEY (run.sh wires them).

import 'package:dictionarylib/dictionarylib.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../helpers.dart';
import 'md_common.dart';

const String mdListId = String.fromEnvironment('MD_LIST_ID');
const String mdEditorKey = String.fromEnvironment('MD_EDITOR_KEY');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'owner recovers the list on a fresh install, sees the edit, '
      'and renames', (WidgetTester tester) async {
    expect(mdListId, isNotEmpty,
        reason: 'phase C needs --dart-define=MD_LIST_ID from phase A');
    expect(mdEditorKey, isNotEmpty,
        reason: 'phase C needs --dart-define=MD_EDITOR_KEY from phase B');

    await mdRequireServer();
    await mdSetup();
    await mdSignInAs(mdOwnerUserId, mdOwnerName);

    // Fresh install: nothing local yet. Recover from the server the way
    // the post-sign-in import flow does.
    final result = await listsService.importEditableLists();
    expect(result.imported, greaterThanOrEqualTo(1),
        reason: 'the owner should recover at least the shared list');
    final mirror = sharing.lists.editableLists
        .where((l) => l.meta.listId == mdListId)
        .toList();
    expect(mirror, hasLength(1),
        reason: 'the import should reinstall the owner mirror');

    // The imported snapshot must already contain the editor's edit.
    expect(mirror.single.uniqueEntries.map((e) => e.getKey()),
        contains(mdEditorKey),
        reason: "the editor's entry should be in the recovered list");

    await mdPumpApp(tester);

    // The UI agrees: list on My Lists, editor's word on the list page.
    await mdOpenListsTab(tester);
    await mdOpenOverviewTab(tester, mdL10n.listMyLists);
    await mdTapWhenVisible(tester, find.text(mdListName),
        reason: 'recovered list on the My Lists tab');
    await mdWaitForUi(
        tester, () => find.text(mdEditorKey).evaluate().isNotEmpty,
        reason: "the editor's word should be visible on the list page");

    // Rename through the overview's edit mode (the only rename surface).
    await tester.pageBack();
    await settle(tester);
    await mdTapWhenVisible(tester, find.byIcon(Icons.edit_outlined),
        reason: 'overview edit-mode pencil');
    await tester.tap(find.text(mdListName));
    await settle(tester);
    expect(find.text(mdL10n.listRenameList), findsOneWidget,
        reason: 'tapping the list in edit mode should open the rename dialog');
    await tester.enterText(find.byType(TextField), mdRenamedListName);
    await tester.tap(find.text(mdL10n.alertConfirm));
    await settle(tester);

    // Server truth: the rename must reach the worker.
    await mdWaitFor(tester, () async {
      final state = await mdServerState(mdListId);
      return state.displayName == mdRenamedListName;
    },
        reason: 'the rename should flush to the server',
        timeout: const Duration(seconds: 45));

    // The editor's membership is visible server-side.
    final state = await mdServerState(mdListId);
    expect(state.ownerUserId, mdOwnerUserId,
        reason: 'the owner should be the member-block owner');
    expect(state.editorUserIds, contains(mdEditorUserId),
        reason: 'the editor should appear in the member list');
  });
}
