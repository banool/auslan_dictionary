import 'package:auslan_dictionary/favourites_page.dart';
import 'package:auslan_dictionary/types.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'common.dart';
import 'favourites_page.dart';
import 'flashcards_page.dart';
import 'search_page.dart';
import 'settings_page.dart';

late List<Word> wordsGlobal;
late SharedPreferences sharedPreferences;

Future<void> main() async {
  print("Start of main");
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // Get favourites stuff ready if this is the first app launch.
    await bootstrapFavourites();

    // Load up the words information once at startup from disk.
    wordsGlobal = await loadWords();

    // Check for new words data if appropriate.
    // We don't wait for this on startup, it's too slow.
    updateWordsData();

    // Load shared preferences.
    sharedPreferences = await SharedPreferences.getInstance();

    // Finally run the app.
    runApp(MyApp());
  } catch (error) {
    print("Initial setup failed: $error");
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

class MyApp extends StatelessWidget {
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
          home: MyHomePage(title: APP_NAME),
        ));
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key, this.title}) : super(key: key);

  final String? title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final SearchPageController searchPageController = SearchPageController();
  late FavouritesPageController favouritesPageController =
      FavouritesPageController(refresh);
  late FlashcardsPageController flashcardsPageController =
      FlashcardsPageController(goToSettings);
  late SettingsController settingsPageController =
      SettingsController(refresh, toggleFlashcards);

  bool wordsLoaded = false;
  int currentNavBarIndex = 0;

  void refresh() {
    setState(() {});
  }

  void toggleFlashcards(bool enabled) {
    setState(() {
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

  @override
  Widget build(BuildContext context) {
    List<BottomNavigationBarItem> items = [];
    List<Widget> tabs = [];

    items.add(BottomNavigationBarItem(
      icon: Icon(Icons.search),
      label: "Dictionary",
    ));
    tabs.add(SearchPage(controller: searchPageController));

    items.add(BottomNavigationBarItem(
      icon: Icon(Icons.star),
      label: "Favourites",
    ));
    tabs.add(FavouritesPage(controller: favouritesPageController));

    if (useFlashcards()) {
      items.add(BottomNavigationBarItem(
        icon: Icon(Icons.style),
        label: "Flashcards",
      ));
      tabs.add(FlashcardsLandingPage(controller: flashcardsPageController));
    }

    items.add(BottomNavigationBarItem(
      icon: Icon(Icons.settings),
      label: "Settings",
    ));
    tabs.add(SettingsPage(controller: settingsPageController));

    Widget body = tabs[currentNavBarIndex];
    Widget? floatingActionButton;
    if (body is FavouritesPage) {
      floatingActionButton = FloatingActionButton(
          backgroundColor:
              favouritesPageController.getFloatingActionButtonColor(),
          onPressed: () {
            if (!favouritesPageController.enableSortButton) {
              return;
            }
            favouritesPageController.toggleSort();
          },
          child: Icon(Icons.sort));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title!),
      ),
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: BottomNavigationBar(
        items: items,
        currentIndex: currentNavBarIndex,
        selectedItemColor: MAIN_COLOR,
        onTap: onNavBarItemTapped,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
