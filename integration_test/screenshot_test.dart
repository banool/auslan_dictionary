import 'dart:io';
import 'dart:ui';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/page_entry_list_overview.dart'
    show KEY_LISTS_OVERVIEW_TAB_INDEX;
import 'package:dictionarylib/revision.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:integration_test/src/channel.dart';

import 'package:auslan_dictionary/common.dart' as app;
import 'package:auslan_dictionary/entries_types.dart' as et;
import 'package:auslan_dictionary/main.dart';
import 'package:auslan_dictionary/root.dart';

import 'helpers.dart';

// Drives the app through its marketable screens and captures a screenshot of
// each. Run it (and actually save the PNGs) via:
//
//   flutter drive \
//     --driver=test_driver/integration_driver.dart \
//     --target=integration_test/screenshot_test.dart \
//     -d <device>
//
// (see screenshots/take_screenshots.py, which fans this out across the device
// matrix). Under `flutter drive` the integration_driver's onScreenshot callback
// writes each capture to screenshots/<name>.png. This is the current official
// Flutter screenshot approach — `integration_test` + IntegrationTestWidgets-
// FlutterBinding.takeScreenshot — driven by flutter_driver.
//
// Note, sometimes the test will crash at the end, but the screenshots do
// actually still get taken.

Future<void> takeScreenshotForAndroid(
    IntegrationTestWidgetsFlutterBinding binding, String name) async {
  await integrationTestChannel.invokeMethod<void>(
    'convertFlutterSurfaceToImage',
    null,
  );
  binding.reportData ??= <String, dynamic>{};
  binding.reportData!['screenshots'] ??= <dynamic>[];
  integrationTestChannel.setMethodCallHandler((MethodCall call) async {
    switch (call.method) {
      case 'scheduleFrame':
        PlatformDispatcher.instance.scheduleFrame();
        break;
    }
    return null;
  });
  final List<int>? rawBytes =
      await integrationTestChannel.invokeMethod<List<int>>(
    'captureScreenshot',
    <String, dynamic>{'name': name},
  );
  if (rawBytes == null) {
    throw StateError(
        'Expected a list of bytes, but instead captureScreenshot returned null');
  }
  final Map<String, dynamic> data = {
    'screenshotName': name,
    'bytes': rawBytes,
  };
  assert(data.containsKey('bytes'));
  (binding.reportData!['screenshots'] as List<dynamic>).add(data);

  await integrationTestChannel.invokeMethod<void>(
    'revertFlutterImage',
    null,
  );
}

/// Give an on-screen video a few seconds of real frames to fetch and paint a
/// first frame before we capture, so video-bearing screens aren't shot mid-load.
Future<void> letVideoLoad(WidgetTester tester) async {
  for (var i = 0; i < 22; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Future<void> takeScreenshot(
    WidgetTester tester,
    IntegrationTestWidgetsFlutterBinding binding,
    ScreenshotNameInfo screenshotNameInfo,
    String name) async {
  name = "${screenshotNameInfo.platformName}/en-AU/"
      "${screenshotNameInfo.deviceName}-${screenshotNameInfo.physicalScreenSize}-"
      "${screenshotNameInfo.getAndIncrementCounter().toString().padLeft(2, '0')}-"
      "$name";
  await settle(tester);
  if (Platform.isAndroid) {
    await takeScreenshotForAndroid(binding, name);
  } else {
    await binding.takeScreenshot(name);
  }
  print("Took screenshot: $name");
}

class ScreenshotNameInfo {
  String platformName;
  String deviceName;
  String physicalScreenSize;
  int counter = 1;

  ScreenshotNameInfo(
      {required this.platformName,
      required this.deviceName,
      required this.physicalScreenSize});

  int getAndIncrementCounter() {
    int out = counter;
    counter += 1;
    return out;
  }

  static Future<ScreenshotNameInfo> buildScreenshotNameInfo() async {
    // Use the modern single-view accessor rather than the deprecated top-level
    // `window`.
    Size size = PlatformDispatcher.instance.implicitView!.physicalSize;
    String physicalScreenSize = "${size.width.toInt()}x${size.height.toInt()}";

    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

    String platformName;
    String deviceName;
    if (Platform.isAndroid) {
      platformName = "android";
      AndroidDeviceInfo info = await deviceInfo.androidInfo;
      deviceName = info.product;
    } else if (Platform.isIOS) {
      platformName = "ios";
      IosDeviceInfo info = await deviceInfo.iosInfo;
      deviceName = info.name;
    } else {
      throw "Unsupported platform";
    }

    return ScreenshotNameInfo(
        platformName: platformName,
        deviceName: deviceName,
        physicalScreenSize: physicalScreenSize);
  }
}

void main() async {
  // ignore: unnecessary_cast
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
      as IntegrationTestWidgetsFlutterBinding;
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("takeScreenshots", (WidgetTester tester) async {
    await setup();

    // --- Seed data so the captured screens are populated. ---
    const String listName = "Animals";
    final String listKey = EntryList.getKeyFromName(listName);
    // Idempotent: the screenshot run may target a simulator that already holds
    // this list from a previous run, and createEntryList throws on a duplicate.
    if (!userEntryListManager.getEntryLists().containsKey(listKey)) {
      await userEntryListManager.createEntryList(listKey);
    }
    final animalList = userEntryListManager.getEntryLists()[listKey]!;
    for (final word in const [
      "kangaroo",
      "platypus",
      "echidna",
      "dog",
      "cat",
      "bird"
    ]) {
      final entry = keyedByEnglishEntriesGlobal[word];
      if (entry != null) await animalList.addAllVideosOfEntry(entry);
    }

    // Revise the Animals list with spaced repetition, allowing every region so
    // the session always has cards.
    await sharedPreferences.setStringList(KEY_LISTS_TO_REVIEW, [listKey]);
    await sharedPreferences.setInt(
        KEY_REVISION_STRATEGY, RevisionStrategy.SpacedRepetition.index);
    await sharedPreferences.setStringList(KEY_FLASHCARD_REGIONS,
        [for (var i = 0; i < et.Region.values.length; i++) '$i']);
    await sharedPreferences.setBool(KEY_USE_UNKNOWN_REGION_SIGNS, true);

    // Open the lists overview on the My Lists tab, and don't let the advisories
    // interstitial pop over the search screen.
    await sharedPreferences.setInt(KEY_LISTS_OVERVIEW_TAB_INDEX, 0);
    advisoryShownOnce = true;

    await tester.pumpWidget(RootApp(startingLocale: LOCALE_ENGLISH));
    await tester.pumpAndSettle(const Duration(seconds: 5));
    final info = await ScreenshotNameInfo.buildScreenshotNameInfo();

    // Pin the theme. The app follows the OS by default, and emulators can
    // boot with dark mode active (battery-saver forces it), which would
    // silently flip the entire light-mode set. Shot 11 switches to dark
    // explicitly and back.
    themeNotifier.value = ThemeMode.light;
    await settle(tester);

    // 1. Search screen — the productive empty state (sign of the day, recents).
    await takeScreenshot(tester, binding, info, "search");

    // 2. Search results for a query.
    final searchField = find.byKey(const ValueKey("searchPage.searchForm"));
    await tester.tap(searchField);
    await settle(tester);
    await tester.enterText(searchField, "dog");
    await takeScreenshot(tester, binding, info, "searchResults");
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);

    // 3. A word page (opened in all-lists picker mode, so the save button opens
    // the sheet). Pushed on the root navigator, the same way search results do.
    final dog = keyedByEnglishEntriesGlobal["dog"]!;
    app.navigateToEntryPage(rootNavigatorKey.currentContext!, dog, true);
    await letVideoLoad(tester);
    await takeScreenshot(tester, binding, info, "wordPage");

    // 4. The per-video "save to list" sheet — the recent per-video-saves feature.
    await tester.tap(find.byKey(const ValueKey("wordPage.saveButton")).first);
    await settle(tester);
    await takeScreenshot(tester, binding, info, "saveToList");
    rootNavigatorKey.currentState!.pop(); // close the sheet
    await settle(tester);
    rootNavigatorKey.currentState!.pop(); // close the word page
    await settle(tester);

    // 5. Lists overview (My Lists tab).
    await tester.tap(find.byIcon(Icons.view_list));
    await settle(tester);
    await takeScreenshot(tester, binding, info, "lists");

    // 6. Inside a list.
    await tester.tap(find.byKey(ValueKey(listKey)));
    await letVideoLoad(tester);
    await takeScreenshot(tester, binding, info, "insideList");
    await tester.pageBack();
    await settle(tester);

    // 7. Revision landing — the flashcard session setup.
    await tester.tap(find.byIcon(Icons.style));
    await settle(tester);
    await takeScreenshot(tester, binding, info, "revisionLanding");

    // 8. A flashcard, front side.
    await tester.tap(find.byKey(const ValueKey("startButton")));
    await letVideoLoad(tester);
    await takeScreenshot(tester, binding, info, "flashcardFront");

    // 9. The same flashcard revealed, with the rating buttons.
    await tester.tap(find.byKey(const ValueKey("revealButton")));
    await letVideoLoad(tester);
    await takeScreenshot(tester, binding, info, "flashcardRevealed");

    // Leave the session via the app-bar close button. Tapping × mid-session
    // ends it early and shows the revision summary first (revealing a card adds
    // a default answer, so there's something to summarise), then a second × pops
    // the summary back to the revision landing page. Both writes happen on that
    // first close. Target the IconButton specifically — the "Forgot" rating
    // button also uses an Icons.close glyph.
    await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
    await settle(tester);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
    await settle(tester);

    // 10. Settings.
    await tester.tap(find.byIcon(Icons.settings));
    await settle(tester);
    await takeScreenshot(tester, binding, info, "settings");

    // --- The home screen in Hearth dark mode. ---
    await tester.tap(find.byIcon(Icons.search));
    await settle(tester);

    // 11. Dark mode (Hearth).
    themeNotifier.value = ThemeMode.dark;
    await settle(tester);
    await takeScreenshot(tester, binding, info, "searchDark");

    // Restore the default light mode.
    themeNotifier.value = ThemeMode.light;
    await settle(tester);

    // --- Landscape captures. The word page and the flashcards page have
    // dedicated horizontal layouts that have historically broken without
    // anyone noticing (no test or screenshot covered them), so capture
    // them explicitly — but only where rotating actually changes anything.
    // On landscape-natural panels (the touch-TV target) the app is already
    // landscape, and on multitasking iPads iOS ignores
    // setPreferredOrientations, so shots 12-14 would just duplicate 03/08/09
    // as dead repo bytes — skip them there. The phone captures are the
    // authoritative landscape record.
    final logicalSize = tester.view.physicalSize / tester.view.devicePixelRatio;
    final rotationIsNoOp = logicalSize.width > logicalSize.height ||
        (Platform.isIOS && logicalSize.shortestSide >= 600);
    if (rotationIsNoOp) {
      print("Skipping landscape captures: rotation is a no-op here");
    } else {
      await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft]);
      // Give the OS rotation animation time to settle (real frames).
      await letVideoLoad(tester);

      // 12. Word page in landscape: video left, definitions right.
      app.navigateToEntryPage(rootNavigatorKey.currentContext!, dog, true);
      await letVideoLoad(tester);
      await takeScreenshot(tester, binding, info, "wordPageLandscape");
      rootNavigatorKey.currentState!.pop();
      await settle(tester);

      // 13/14. Flashcard front + revealed in landscape. Skipped on Android:
      // rotating the flashcard re-creates its media_kit video player, which
      // needs a GL context the emulator can't provide (eglCreateContext fails
      // with EGL_BAD_ATTRIBUTE) — the very mpv/GL limitation the poster
      // workaround exists for, except this rotation path bypasses the poster
      // and crashes the capture instead of rendering it. These shots are
      // local-only (neither store publishes them) and the iOS phone is the
      // authoritative landscape record for the flashcard, so dropping them on
      // Android costs nothing. Shot 12 above (the landscape word page, which
      // keeps using the poster) still covers the landscape layout on Android.
      if (!Platform.isAndroid) {
        // 13. Flashcard front in landscape (the "what does this sign mean"
        // prompt next to the controls).
        await tester.tap(find.byIcon(Icons.style));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey("startButton")));
        await letVideoLoad(tester);
        await takeScreenshot(tester, binding, info, "flashcardFrontLandscape");

        // 14. The same flashcard revealed: video left, word + rating buttons
        // right.
        await tester.tap(find.byKey(const ValueKey("revealButton")));
        await letVideoLoad(tester);
        await takeScreenshot(
            tester, binding, info, "flashcardRevealedLandscape");
        await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
        await settle(tester);
      }

      // Restore portrait, then hand orientation control back to the OS.
      await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.portraitUp]);
      await settle(tester);
      await SystemChrome.setPreferredOrientations([]);
    }

    // Machine-readable completion marker for take_screenshots.py: it
    // verifies this many files with this prefix actually landed on disk,
    // so a drive that dies partway can't pass silently.
    print("SCREENSHOTS_COMPLETE count=${info.counter - 1} "
        "prefix=${info.platformName}/en-AU/"
        "${info.deviceName}-${info.physicalScreenSize}");
  });
}
