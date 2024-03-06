import 'dart:io' show Platform;

import 'package:dictionarylib/dictionarylib.dart';
import 'package:dictionarylib/force_upgrade_page.dart';
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

  await setupPhaseOne(Uri.parse(
      "https://raw.githubusercontent.com/banool/auslan_dictionary/master/assets/advisories.md"));

  // If the user needs to upgrade, this will run an app telling them to do so
  // and just block forever. It is bad to do this in setup, but it is simpler,
  // so let's just do it this way for now.
  showUpgradePageIfApplicable(
      MyYankedVersionChecker(), IOS_APP_ID, ANDROID_APP_ID);

  MyEntryLoader myEntryLoader = MyEntryLoader();

  await setupPhaseTwo(
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
  } catch (error, stackTrace) {
    runApp(ErrorFallback(
      appName: APP_NAME,
      error: error,
      stackTrace: stackTrace,
    ));
  }
}
