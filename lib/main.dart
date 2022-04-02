import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'common.dart';
import 'flashcards_help_page.dart';
import 'flashcards_landing_page.dart';
import 'globals.dart';
import 'search_page.dart';
import 'settings_help_page.dart';
import 'settings_page.dart';
import 'types.dart';
import 'word_list_logic.dart';
import 'word_list_overview_help_page.dart';
import 'word_list_overview_page.dart';

Future<void> main() async {
  print("Start of main");

  String? advisory;

  try {
    var widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

    // Preserve the splash screen while the app initializes.
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

    // Load shared preferences. We do this first because the later futures,
    // such as loadFavourites and the knobs, depend on it being initialized.
    sharedPreferences = await SharedPreferences.getInstance();

    // Load up the advisory (if there is one) next.
    advisory = await getAdvisory();

    // Build the cache manager.
    String cacheManagerKey = "myVideoCacheManager";
    videoCacheManager = CacheManager(
      Config(
        cacheManagerKey,
        stalePeriod: const Duration(days: 14),
        maxNrOfCacheObjects: 500,
      ),
    );

    await Future.wait<void>([
      // Load up the words information once at startup from disk.
      // We do this first because loadFavourites depends on it later.
      (() async => wordsGlobal = await loadWords())(),

      // Get knob values.
      (() async =>
          enableFlashcardsKnob = await readKnob("enable_flashcards", true))(),
      (() async => downloadWordsDataKnob =
          await readKnob("download_words_data", false))(),
    ]);

    for (Word w in wordsGlobal) {
      keyedWordsGlobal[w.word] = w;
    }

    // Check for new words data if appropriate.
    // We don't wait for this on startup, it's too slow.
    if (downloadWordsDataKnob) {
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
    runApp(MyApp(advisory: advisory));
  } catch (error, stackTrace) {
    runApp(ErrorFallback(
      error: error,
      stackTrace: stackTrace,
      advisory: advisory,
    ));
  }
}

Future<void> updateWordsData() async {
  bool thereWasNewData = await getNewData(false);
  if (thereWasNewData) {
    print("There was new data");
    wordsGlobal = await loadWords();
    print("Updated wordsGlobal");
  } else {
    print("There was no new words data, not updating wordsGlobal");
  }
}

class ErrorFallback extends StatelessWidget {
  final Object error;
  final StackTrace stackTrace;
  final String? advisory;

  ErrorFallback({required this.error, required this.stackTrace, this.advisory});

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

class MyApp extends StatelessWidget {
  final String? advisory;

  MyApp({this.advisory});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: () {
          FocusScopeNode currentFocus = FocusScope.of(context);
          if (!currentFocus.hasPrimaryFocus &&
              currentFocus.focusedChild != null) {
            FocusManager.instance.primaryFocus!.unfocus();
          }
        },
        child: MaterialApp(
          title: APP_NAME,
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
              primarySwatch: MAIN_COLOR as MaterialColor?,
              visualDensity: VisualDensity.adaptivePlatformDensity,
              // Make swiping to pop back the navigation work.
              pageTransitionsTheme: PageTransitionsTheme(builders: {
                TargetPlatform.android: CupertinoPageTransitionsBuilder(),
                TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
              })),
          home: MyHomePage(advisory: advisory),
        ));
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key, this.advisory}) : super(key: key);

  final String? advisory;

  @override
  _MyHomePageState createState() => _MyHomePageState(advisory: advisory);
}

class _MyHomePageState extends State<MyHomePage> {
  final String? advisory;
  bool advisoryShownOnce = false;

  _MyHomePageState({this.advisory});

  final SearchPageController searchPageController = SearchPageController();
  late FlashcardsPageController flashcardsPageController =
      FlashcardsPageController(goToSettings);
  late WordListsOverviewController wordListsOverviewController =
      WordListsOverviewController();
  late SettingsController settingsPageController =
      SettingsController(refresh, toggleFlashcards);

  int currentNavBarIndex = 0;

  void refresh() {
    setState(() {});
  }

  void toggleFlashcards(bool enabled) {
    setState(() {
      showFlashcards = getShowFlashcards();
      if (enabled) {
        currentNavBarIndex -= 1;
      } else {
        currentNavBarIndex += 1;
      }
    });
  }

  void goToSettings() {
    setState(() {
      currentNavBarIndex = 3;
    });
  }

  void onNavBarItemTapped(int index) {
    setState(() {
      currentNavBarIndex = index;
      if (searchPageController.isMounted) {
        searchPageController.clearSearch();
      }
    });
  }

  void showAdvisoryDialog() {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: Text("Developer Message"),
              content: Text(advisory!),
            ));
  }

  @override
  Widget build(BuildContext context) {
    if (advisory != null && !advisoryShownOnce) {
      Future.delayed(Duration(milliseconds: 500), () => showAdvisoryDialog());
      advisoryShownOnce = true;
    }

    List<TabInformation> information = [];

    information.add(TabInformation(
        BottomNavigationBarItem(
          icon: Icon(Icons.search),
          label: "Dictionary",
        ),
        SearchPage(controller: searchPageController),
        "Search"));

    information.add(TabInformation(
        BottomNavigationBarItem(
          icon: Icon(Icons.view_list),
          label: "Lists",
        ),
        WordListsOverviewPage(controller: wordListsOverviewController),
        "Lists"));

    if (showFlashcards) {
      information.add(TabInformation(
          BottomNavigationBarItem(
            icon: Icon(Icons.style),
            label: "Revision",
          ),
          FlashcardsLandingPage(controller: flashcardsPageController),
          "Revision"));
    }

    information.add(TabInformation(
        BottomNavigationBarItem(
          icon: Icon(Icons.settings),
          label: "Settings",
        ),
        SettingsPage(controller: settingsPageController),
        "Settings"));

    Widget body = information[currentNavBarIndex].tabBody;

    Widget? floatingActionButton;

    if (body is WordListsOverviewPage &&
        wordListsOverviewController.inEditMode) {
      floatingActionButton = FloatingActionButton(
          backgroundColor: Colors.green,
          onPressed: () async {
            bool confirmed = await applyCreateListDialog(context);
            if (confirmed) {
              setState(() {
                wordListsOverviewController.inEditMode = false;
              });
            }
          },
          child: Icon(Icons.add));
    }

    List<Widget> actions = [];
    if (body is SearchPage && advisory != null) {
      actions.add(buildActionButton(
        context,
        Icon(Icons.info),
        () async {
          showAdvisoryDialog();
        },
      ));
    }

    if (body is WordListsOverviewPage) {
      actions.add(buildActionButton(
        context,
        wordListsOverviewController.inEditMode
            ? Icon(Icons.edit)
            : Icon(Icons.edit_outlined),
        () async {
          setState(() {
            wordListsOverviewController.toggleEditMode();
          });
        },
      ));
      actions.add(buildActionButton(
        context,
        Icon(Icons.help),
        () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => getWordListOverviewHelpPage()),
          );
        },
      ));
    }

    if (body is FlashcardsLandingPage) {
      actions.add(buildActionButton(
        context,
        Icon(Icons.help),
        () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => getFlashcardsHelpPage()),
          );
        },
      ));
    }

    if (body is SettingsPage) {
      actions.add(buildActionButton(
        context,
        Icon(Icons.help),
        () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => getSettingsHelpPage()),
          );
        },
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(information[currentNavBarIndex].appBarTitle),
        actions: buildActionButtons(actions),
        centerTitle: true,
      ),
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: BottomNavigationBar(
        items: information.map((e) => e.bottomNavBarItem).toList(),
        currentIndex: currentNavBarIndex,
        selectedItemColor: MAIN_COLOR,
        onTap: onNavBarItemTapped,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}

class TabInformation {
  final BottomNavigationBarItem bottomNavBarItem;
  final Widget tabBody;
  final String appBarTitle;

  TabInformation(this.bottomNavBarItem, this.tabBody, this.appBarTitle);
}
