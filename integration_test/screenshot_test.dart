import 'dart:io';
import 'dart:ui';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/revision.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:integration_test/src/channel.dart';

import 'package:auslan_dictionary/main.dart';
import 'package:auslan_dictionary/root.dart';

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

Future<void> takeScreenshot(
    WidgetTester tester,
    IntegrationTestWidgetsFlutterBinding binding,
    ScreenshotNameInfo screenshotNameInfo,
    String name) async {
  name = "${screenshotNameInfo.platformName}/en-AU/"
      "${screenshotNameInfo.deviceName}-${screenshotNameInfo.physicalScreenSize}-"
      "${screenshotNameInfo.getAndIncrementCounter().toString().padLeft(2, '0')}-"
      "$name";
  await tester.pumpAndSettle();
  sleep(const Duration(milliseconds: 250));
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
    Size size = window.physicalSize;
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

    String listName = "Animals";
    String listKey = EntryList.getKeyFromName(listName);
    await entryListManager.createEntryList(listKey);
    await entryListManager.entryLists[listKey]!
        .addEntry(keyedByEnglishEntriesGlobal["kangaroo"]!);
    await entryListManager.entryLists[listKey]!
        .addEntry(keyedByEnglishEntriesGlobal["platypus"]!);
    await entryListManager.entryLists[listKey]!
        .addEntry(keyedByEnglishEntriesGlobal["echidna"]!);
    await entryListManager.entryLists[listKey]!
        .addEntry(keyedByEnglishEntriesGlobal["dog"]!);
    await entryListManager.entryLists[listKey]!
        .addEntry(keyedByEnglishEntriesGlobal["cat"]!);
    await entryListManager.entryLists[listKey]!
        .addEntry(keyedByEnglishEntriesGlobal["bird"]!);

    await sharedPreferences
        .setStringList(KEY_LISTS_TO_REVIEW, [KEY_FAVOURITES_ENTRIES, listKey]);

    await sharedPreferences.setInt(
        KEY_REVISION_STRATEGY, RevisionStrategy.SpacedRepetition.index);

    await tester.pumpWidget(RootApp(startingLocale: LOCALE_ENGLISH));
    await tester.pumpAndSettle(const Duration(seconds: 10));
    var screenshotNameInfo = await ScreenshotNameInfo.buildScreenshotNameInfo();

    await takeScreenshot(tester, binding, screenshotNameInfo, "search");

    final Finder searchField =
        find.byKey(const ValueKey("searchPage.searchForm"));
    await tester.tap(searchField);
    await tester.pumpAndSettle();
    await tester.enterText(searchField, "hey");
    await takeScreenshot(tester, binding, screenshotNameInfo, "searchWithText");

    final Finder listsNavBarButton = find.byIcon(Icons.view_list);
    await tester.tap(listsNavBarButton);
    await tester.pumpAndSettle();
    await takeScreenshot(tester, binding, screenshotNameInfo, "listsOverview");

    final Finder animalsListButton = find.byKey(ValueKey(listName));
    await tester.tap(animalsListButton);
    await tester.pumpAndSettle();
    await takeScreenshot(tester, binding, screenshotNameInfo, "insideList");

    final Finder dogButton = find.byKey(const ValueKey("dog"));
    await tester.tap(dogButton);
    await tester.pumpAndSettle();
    sleep(const Duration(seconds: 2));
    await takeScreenshot(tester, binding, screenshotNameInfo, "wordPage");

    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    final Finder revisionNavBarButton = find.byIcon(Icons.style);
    await tester.tap(revisionNavBarButton);
    await tester.pumpAndSettle();
    await takeScreenshot(
        tester, binding, screenshotNameInfo, "revisionLanding");

    final Finder helpAppBarButton = find.byIcon(Icons.help);
    await tester.tap(helpAppBarButton);
    await tester.pumpAndSettle();
    await takeScreenshot(
        tester, binding, screenshotNameInfo, "revisionHelpPage");

    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    final Finder startAppBarButton = find.byKey(const ValueKey("startButton"));
    await tester.tap(startAppBarButton);
    await tester.pumpAndSettle();
    sleep(const Duration(seconds: 4));
    await takeScreenshot(tester, binding, screenshotNameInfo, "revisionPage");

    sleep(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    final Finder revealTapArea = find.byKey(const ValueKey("revealTapArea"));
    await tester.tap(revealTapArea);
    await tester.pumpAndSettle();
    sleep(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await takeScreenshot(
        tester, binding, screenshotNameInfo, "revisionPageRevealed");

    final Finder exitRevisionAppBarButton = find.byIcon(Icons.close);
    await tester.tap(exitRevisionAppBarButton);
    await tester.pumpAndSettle();

    final Finder settingsNavBarButton = find.byIcon(Icons.settings);
    await tester.tap(settingsNavBarButton);
    await tester.pumpAndSettle();
    await takeScreenshot(tester, binding, screenshotNameInfo, "settingsPage");
  });
}
