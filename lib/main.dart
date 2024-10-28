import 'dart:io' show Platform;

import 'package:dictionarylib/dictionarylib.dart';
import 'package:dictionarylib/page_force_upgrade.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:video_player_win/video_player_win_plugin.dart';

import 'common.dart';
import 'entries_loader.dart';
import 'root.dart';

const String KNOBS_URL_BASE =
    "https://raw.githubusercontent.com/banool/auslan_dictionary/master/assets/knobs/";

Future<void> setup({Set<Entry>? entriesGlobalReplacement}) async {
  var widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // Preserve the splash screen while the app initializes.
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await setupPhaseOne();

  // It is okay to check for yanked versions and do phase two setup at the same
  // time because phase two setup never throws. We want to do them together
  // because they both make network calls, so we can do them concurrently.
  await Future.wait<void>([
    (() async {
      await setupPhaseTwo(Uri.parse(
          "https://raw.githubusercontent.com/banool/auslan_dictionary/8a2e20acfb7ca49b1bcd459d4eb45862281610cb/assets/advisories.md"));
    })(),
    (() async {
      // If the user needs to upgrade, this will throw a specific error that main()
      // can catch to show the ForceUpgradePage.
      await GitHubYankedVersionChecker(
              "https://raw.githubusercontent.com/banool/auslan_dictionary/master/assets/yanked_versions")
          .throwIfShouldUpgrade();
    })(),
  ]);

  MyEntryLoader myEntryLoader = MyEntryLoader();

  await setupPhaseThree(
      paramEntryLoader: myEntryLoader,
      knobUrlBase: KNOBS_URL_BASE,
      entriesGlobalReplacement: entriesGlobalReplacement);

  // Set up the video player plugin for Windows.
  if (!kIsWeb && Platform.isWindows) {
    WindowsVideoPlayer.registerWith();
  }

  // Remove the splash screen.
  FlutterNativeSplash.remove();

  // Finally run the app.
  printAndLog("Setup complete, running app");
}

Future<void> main() async {
  printAndLog("Start of main");
  try {
    await setup();
    runApp(RootApp(startingLocale: LOCALE_ENGLISH));
  } on YankedVersionError catch (e) {
    runApp(ForceUpgradePage(
        error: e, iOSAppId: IOS_APP_ID, androidAppId: ANDROID_APP_ID));
  } catch (error, stackTrace) {
    runApp(ErrorFallback(
      appName: APP_NAME,
      error: error,
      stackTrace: stackTrace,
    ));
  }
}
