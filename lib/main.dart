import 'package:auslan_dictionary/favourites_page.dart';
import 'package:flutter/material.dart';

import 'common.dart';
import 'favourites_page.dart';
import 'search_page.dart';
import 'settings_page.dart';

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await setup();
    runApp(MyApp());
  } catch (error) {
    print("Initial setup failed: $error");
  }
}

Future<void> setup() async {
  // Don't await getting new data, it's too slow.
  getNewData(false).catchError((e, s) {
    print("Failed to check for new data: $e and $s");
  });
  await bootstrapFavourites();
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

  bool wordsLoaded = false;
  int currentNavBarIndex = 0;

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
    List<Widget> tabs = [
      SearchPage(controller: searchPageController),
      FavouritesPage(),
      SettingsPage(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title!),
      ),
      body: tabs[currentNavBarIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: "Dictionary",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.star),
            label: "Favourites",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: "Settings",
          ),
        ],
        currentIndex: currentNavBarIndex,
        selectedItemColor: MAIN_COLOR,
        onTap: onNavBarItemTapped,
      ),
    );
  }
}
