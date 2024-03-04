import 'dart:io' show Platform;

import 'package:dictionarylib/dictionarylib.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:video_player_win/video_player_win_plugin.dart';

import 'common.dart';
import 'entries_loader.dart';
import 'globals.dart';
import 'root.dart';

const String KNOBS_URL_BASE =
    "https://raw.githubusercontent.com/banool/auslan_dictionary/master/assets/knobs/";

Future<void> setup({Set<Entry>? entriesGlobalReplacement}) async {
  var widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // Preserve the splash screen while the app initializes.
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await setupPhaseOne(Uri.parse(
      "https://raw.githubusercontent.com/banool/auslan_dictionary/master/assets/advisories.md"));

  MyEntryLoader myEntryLoader = MyEntryLoader();

  await setupPhaseTwo(
      paramEntryLoader: myEntryLoader,
      downloadWordsData: true,
      knobUrlBase: KNOBS_URL_BASE,
      entriesGlobalReplacement: entriesGlobalReplacement);

  // Set up the video player plugin for Windows.
  if (!kIsWeb && Platform.isWindows) {
    WindowsVideoPlayer.registerWith();
  }

  // Remove the splash screen.
  FlutterNativeSplash.remove();

  // Finally run the app.
  print("Setup complete, running app");
}

Future<void> main() async {
  print("Start of main");
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
