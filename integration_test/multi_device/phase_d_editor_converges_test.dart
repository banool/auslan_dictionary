// Multi-device e2e, phase D — runs on DEVICE B again (the editor).
//
// Like phase C, this models the "editor gets a new phone" story (the
// test runner reinstalls the app per run): the editor signs back in on a
// fresh install, recovers their editor membership from the server (the
// single-use invite is long consumed — recovery must not need it), and
// sees the owner's phase-C rename plus the fully converged list.
//
// Requires --dart-define=MD_LIST_ID and MD_EDITOR_KEY (run.sh wires them).

import 'package:dictionarylib/dictionarylib.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'md_common.dart';

const String mdListId = String.fromEnvironment('MD_LIST_ID');
const String mdEditorKey = String.fromEnvironment('MD_EDITOR_KEY');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'editor recovers the list on a fresh install and sees the '
      'rename', (WidgetTester tester) async {
    expect(mdListId, isNotEmpty,
        reason: 'phase D needs --dart-define=MD_LIST_ID');
    expect(mdEditorKey, isNotEmpty,
        reason: 'phase D needs --dart-define=MD_EDITOR_KEY');

    await mdRequireServer();
    await mdSetup();
    await mdSignInAs(mdEditorUserId, mdEditorName);

    // Fresh install: recover the editor membership from the server. This
    // must work without the (already consumed) invite token.
    final result = await listsService.importEditableLists();
    expect(result.imported, greaterThanOrEqualTo(1),
        reason: 'the editor should recover their editable list');
    final mirror = sharing.lists.editableLists
        .where((l) => l.meta.listId == mdListId)
        .toList();
    expect(mirror, hasLength(1),
        reason: 'the import should reinstall the editor mirror');
    expect(mirror.single.meta.role.name, 'editor',
        reason: 'the recovered list should come back in editor mode');

    // The owner's rename is in the recovered snapshot.
    expect(mirror.single.meta.displayName, mdRenamedListName,
        reason: "the owner's rename should reach the editor");

    await mdPumpApp(tester);

    // UI agrees: renamed title on the Shared with me tab, all three
    // entries on the list page.
    await mdOpenListsTab(tester);
    await mdOpenOverviewTab(tester, mdL10n.listSharedWithMeTab);
    await mdTapWhenVisible(tester, find.text(mdRenamedListName),
        reason: 'renamed list on the Shared with me tab');
    await mdWaitForUi(
        tester, () => find.text(mdEditorKey).evaluate().isNotEmpty,
        reason: "the editor's own word should be on the list page");

    // Server and local mirror agree on the final entry set.
    final serverKeys = await mdServerEntryKeys(mdListId);
    final localKeys =
        mirror.single.uniqueEntries.map((e) => e.getKey()).toList();
    expect(localKeys, unorderedEquals(serverKeys),
        reason: 'editor mirror and server should have converged');
    expect(serverKeys, hasLength(3));
    expect(serverKeys, contains(mdEditorKey));
  });
}
