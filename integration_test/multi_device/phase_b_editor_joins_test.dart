// Multi-device e2e, phase B — runs on DEVICE B (the editor's phone).
//
// The editor signs in, pastes the invite link from phase A into the real
// subscribe-via-link dialog, accepts it (becoming an editor), then adds a
// word to the shared list through the word page's save sheet — the exact
// path a human takes. The phase ends only once the edit is visible in the
// SERVER list, proving the queued op flushed end to end.
//
// Requires --dart-define=MD_INVITE_URL=… (run.sh wires it from phase A).

import 'package:dictionarylib/globals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../helpers.dart';
import 'md_common.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('editor accepts the invite and edits the shared list',
      (WidgetTester tester) async {
    expect(mdInviteUrl, isNotEmpty,
        reason: 'phase B needs --dart-define=MD_INVITE_URL from phase A');
    final listId = Uri.parse(mdInviteUrl).pathSegments.last;

    await mdRequireServer();
    await mdSetup();
    await mdSignInAs(mdEditorUserId, mdEditorName);
    await mdPumpApp(tester);

    // Lists tab → Shared with me → Subscribe via link.
    await mdOpenListsTab(tester);
    await mdOpenOverviewTab(tester, mdL10n.listSharedWithMeTab);
    await tester.tap(find.text(mdL10n.listSubscribeViaLink));
    await settle(tester);

    // Paste the invite link. The dialog recognises it as an editor invite
    // (preview round-trip) and offers to accept.
    await tester.enterText(find.byType(TextField), mdInviteUrl);
    await tester.tap(find.text(mdL10n.subscribeDialogSubscribeButton));
    await mdWaitForUi(
        tester,
        () =>
            find.text(mdL10n.subscribeInviteAcceptButton).evaluate().isNotEmpty,
        reason: 'invite link should switch the dialog to accept-invite mode');
    await tester.tap(find.text(mdL10n.subscribeInviteAcceptButton));

    // Accepting round-trips the server, closes the dialog, and pushes the
    // list page over the tab shell.
    await mdWaitForUi(tester,
        () => find.text(mdL10n.subscribeInviteAcceptButton).evaluate().isEmpty,
        reason: 'accept-invite dialog should close after accepting');
    await mdWaitForUi(tester, () => find.text(mdListName).evaluate().isNotEmpty,
        reason: 'accepted list page should open, titled $mdListName');

    // The editor mirror is installed with editor role.
    final mirror = sharing.lists.editableLists
        .where((l) => l.meta.listId == listId)
        .toList();
    expect(mirror, hasLength(1),
        reason: 'accepting the invite should install an editable mirror');
    expect(mirror.single.meta.role.name, 'editor');

    // Add a third word through the real save flow: search it, open the
    // word page, tap the bookmark, pick the shared list.
    final existing = await mdServerEntryKeys(listId);
    final third = mdEntryWithVideo(exclude: existing.toSet());

    // The list page is pushed over the tab shell (no bottom nav there) —
    // pop back before switching to the search tab.
    await tester.pageBack();
    await settle(tester);
    await mdTapWhenVisible(tester, mdNavIcon(Icons.search),
        reason: 'search tab icon in the bottom navigation');
    final searchField = find.descendant(
        of: find.byKey(const ValueKey('searchPage.searchForm')),
        matching: find.byType(TextField));
    await mdWaitForUi(tester, () => searchField.evaluate().isNotEmpty,
        reason: 'global search field should be on screen');
    await tester.enterText(searchField, third.getKey());
    // NB: find.text(key) would also match the query inside the TextField,
    // so target the tappable result row (an InkWell) specifically.
    final resultRow = find.widgetWithText(InkWell, third.getKey());
    await mdWaitForUi(tester, () => resultRow.evaluate().isNotEmpty,
        reason: 'search results should include ${third.getKey()}');
    await tester.tap(resultRow.first);
    await settle(tester);

    await mdWaitForUi(
        tester,
        () => find
            .byKey(const ValueKey('wordPage.saveButton'))
            .evaluate()
            .isNotEmpty,
        reason: 'word page save button should appear');
    await tester.tap(find.byKey(const ValueKey('wordPage.saveButton')));
    await settle(tester);

    // The save sheet rows are keyed by local list key; tapping the shared
    // list's row toggles membership on.
    final sheetRow =
        find.byKey(ValueKey('saveVideoSheet.row.${mirror.single.key}'));
    await mdWaitForUi(tester, () => sheetRow.evaluate().isNotEmpty,
        reason: 'save sheet should list the shared list');
    await tester.tap(sheetRow);
    await settle(tester);

    // Server truth: the editor's add must reach the worker.
    await mdWaitFor(tester, () async {
      final keys = await mdServerEntryKeys(listId);
      return keys.contains(third.getKey());
    },
        reason: 'the edit should flush to the server list',
        timeout: const Duration(seconds: 45));

    mdEmit('EDITOR_ADDED_KEY', third.getKey());
  });
}
