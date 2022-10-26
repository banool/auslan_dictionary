import 'dart:io' show HttpClient, HttpOverrides, Platform, SecurityContext;

import 'package:auslan_dictionary/root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_proxy/system_proxy.dart';

import 'common.dart';
import 'globals.dart';
import 'types.dart';
import 'word_list_logic.dart';

Future<void> setup({Set<Word>? wordsGlobalReplacement}) async {
  var widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // Preserve the splash screen while the app initializes.
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Load shared preferences. We do this first because the later futures,
  // such as loadFavourites and the knobs, depend on it being initialized.
  sharedPreferences = await SharedPreferences.getInstance();

  // Set the HTTP proxy if necessary.
  Map<String, String> proxy = await SystemProxy.getProxySettings() ?? {};
  HttpOverrides.global = new ProxiedHttpOverrides(proxy["host"], proxy["port"]);
  print("Set HTTP proxy overrides to $proxy");

  // Load up the advisory (if there is one) next.
  advisory = await getAdvisory();

  // Build the cache manager.
  String cacheManagerKey = "myVideoCacheManager";
  videoCacheManager = CacheManager(
    Config(
      cacheManagerKey,
      stalePeriod: const Duration(days: NUM_DAYS_TO_CACHE),
      maxNrOfCacheObjects: 500,
    ),
  );

  await Future.wait<void>([
    // Load up the words information once at startup from disk.
    // We do this first because loadFavourites depends on it later.
    (() async {
      if (wordsGlobalReplacement == null) {
        wordsGlobal = await loadWords();
      } else {
        wordsGlobal = wordsGlobalReplacement;
      }
    })(),

    // Get knob values.
    (() async =>
        enableFlashcardsKnob = await readKnob("enable_flashcards", true))(),
    (() async =>
        downloadWordsDataKnob = await readKnob("download_words_data", false))(),
  ]);

  updateKeyedWordsGlobal();

  // Check for new words data if appropriate.
  // We don't wait for this on startup, it's too slow.
  if (downloadWordsDataKnob && wordsGlobalReplacement == null) {
    updateWordsData();
  }

  // Build the word list manager.
  wordListManager = WordListManager.fromStartup();

  // Resolve values based on knobs.
  showFlashcards = getShowFlashcards();

  // Get background color of settings pages.
  if (Platform.isAndroid) {
    settingsBackgroundColor = Color.fromRGBO(240, 240, 240, 1);
  } else if (Platform.isIOS) {
    settingsBackgroundColor = Color.fromRGBO(242, 242, 247, 1);
  } else {
    settingsBackgroundColor = Color.fromRGBO(240, 240, 240, 1);
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
    runApp(RootApp());
  } catch (error, stackTrace) {
    runApp(ErrorFallback(
      error: error,
      stackTrace: stackTrace,
    ));
  }
}

Future<void> updateWordsData() async {
  bool thereWasNewData = await getNewData(false);
  if (thereWasNewData) {
    print("There was new data");
    wordsGlobal = await loadWords();
    updateKeyedWordsGlobal();
    print("Updated wordsGlobal");
  } else {
    print("There was no new words data, not updating wordsGlobal");
  }
}

class ErrorFallback extends StatelessWidget {
  final Object error;
  final StackTrace stackTrace;

  ErrorFallback({required this.error, required this.stackTrace});

  @override
  Widget build(BuildContext context) {
    Widget advisoryWidget;
    if (advisory == null) {
      advisoryWidget = Container();
    } else {
      advisoryWidget = Text(advisory!);
    }
    List<Widget> children = [
      Text(
        "Failed to start the app correctly. First, please confirm you are "
        "using the latest version of the app. If you are, please email "
        "danielporteous1@gmail.com with a screenshot showing this error.",
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      Padding(padding: EdgeInsets.only(top: 20)),
      advisoryWidget,
      Text(
        "$error",
        textAlign: TextAlign.center,
      ),
      Text(
        "$stackTrace",
      ),
    ];
    try {
      String s = "";
      for (String key in sharedPreferences.getKeys()) {
        s += "$key: ${sharedPreferences.get(key).toString()}\n";
      }
      children.add(Text(
        s,
        textAlign: TextAlign.left,
      ));
    } catch (e) {
      children.add(Text("Failed to get shared prefs: $e"));
    }
    return MaterialApp(
        title: APP_NAME,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
            body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: children,
        )));
  }
}

class ProxiedHttpOverrides extends HttpOverrides {
  String? _port;
  String? _host;
  ProxiedHttpOverrides(this._host, this._port);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      // Set proxy
      ..findProxy = (uri) {
        return _host != null ? "PROXY $_host:$_port;" : 'DIRECT';
      };
  }
}
