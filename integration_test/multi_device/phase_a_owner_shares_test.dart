// Multi-device e2e, phase A — runs on DEVICE A (the owner's phone).
//
// The owner signs in, shares a local list through the real share-dialog
// UI, and mints an editor invite. The invite link is emitted on stdout
// (`MD_OUT INVITE_URL=…`) for run.sh to hand to phase B on device B.
//
// Server truth is asserted at the end so a UI that lies (says "shared"
// without a server list) can't pass.

import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../helpers.dart';
import 'md_common.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('owner shares a list and mints an editor invite',
      (WidgetTester tester) async {
    await mdRequireServer();
    await mdSetup();

    // Idempotency across reruns on a device that wasn't reset: drop any
    // leftover local lists from a previous run.
    for (final key in [mdListKey, '${mdRenamedListName}_words']) {
      if (userEntryListManager.getEntryLists().containsKey(key)) {
        await userEntryListManager.deleteEntryList(key);
      }
    }

    await mdSignInAs(mdOwnerUserId, mdOwnerName);

    // Seed the local list with two real dictionary entries (with videos).
    final first = mdEntryWithVideo();
    final second = mdEntryWithVideo(exclude: {first.getKey()});
    await userEntryListManager.createEntryList(mdListKey);
    final localList = userEntryListManager.getEntryLists()[mdListKey]!;
    for (final entry in [first, second]) {
      await localList.addVideo(SavedVideo(
        entryKey: entry.getKey(),
        mediaPath: entry
            .getSubEntries()
            .firstWhere((s) => s.getMedia().isNotEmpty)
            .getMedia()
            .first,
      ));
    }

    await mdPumpApp(tester);

    // Lists tab → My Lists → open the seeded list.
    await mdOpenListsTab(tester);
    await mdOpenOverviewTab(tester, mdL10n.listMyLists);
    expect(find.text(mdListName), findsOneWidget,
        reason: 'the seeded list should be visible on My Lists');
    await tester.tap(find.text(mdListName));
    await settle(tester);

    // Share it: share icon → share dialog → Share.
    await tester.tap(find.byIcon(Icons.share));
    await settle(tester);
    expect(find.text(mdL10n.shareDialogShareButton), findsOneWidget,
        reason: 'the share dialog should be open');
    await tester.tap(find.text(mdL10n.shareDialogShareButton));

    // Sharing does a real network round-trip; wait for the share-link
    // dialog that follows it.
    await mdWaitForUi(tester,
        () => find.text(mdL10n.shareLinkDoneButton).evaluate().isNotEmpty,
        reason: 'share-link dialog after sharing');
    await tester.tap(find.text(mdL10n.shareLinkDoneButton));
    await settle(tester);

    // The owner mirror must exist locally now.
    final owned = sharing.lists.editableLists
        .where((l) => l.meta.displayName == mdListName)
        .toList();
    expect(owned, hasLength(1),
        reason: 'sharing should install exactly one owned synced list');
    final listId = owned.single.meta.listId;

    // Server truth: the list exists with both entries.
    final serverKeys = await mdServerEntryKeys(listId);
    expect(serverKeys, unorderedEquals([first.getKey(), second.getKey()]),
        reason: 'server list should contain exactly the two seeded entries');

    // Mint the invite the way the members page does.
    final session = sharing.auth.store.current!;
    final invite = await sharing.api
        .createInvite(listId: listId, sessionToken: session.sessionToken);
    final inviteUrl = sharing.config.inviteUrlFor(listId, invite.token);

    mdEmit('LIST_ID', listId);
    mdEmit('INVITE_URL', inviteUrl);
  });
}
