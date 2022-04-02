import 'package:flutter/material.dart';

import 'common.dart';
import 'flashcards_landing_page.dart';
import 'search_page.dart';
import 'settings_page.dart';
import 'word_list_overview_page.dart';

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key, this.advisory}) : super(key: key);

  final String? advisory;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class TabInformation {
  final BottomNavigationBarItem bottomNavBarItem;
  final Widget tabBody;

  TabInformation(this.bottomNavBarItem, this.tabBody);
}

// This class contains information that only makes sense to be stored
// above each tab. This includes stuff that needs to remembered between
// each tab, since they lose their state when tabbing between each.
//
// See this stackoverflow answer for an explanation as to why the
// variables in this class are defined as late:
// https://stackoverflow.com/questions/68717452/why-cant-non-nullable-fields-be-initialized-in-a-constructor-body-in-dart
class MyHomePageController {
  late int currentNavBarIndex;
  late List<TabInformation> tabs;
  late void Function() refresh;
  bool advisoryShownOnce = false;

  void onNavBarItemTapped(int index) {
    currentNavBarIndex = index;
    refresh();
  }

  void goToSettings() {
    currentNavBarIndex = 3;
    refresh();
  }

  void toggleFlashcards(bool enabled) {
    if (enabled) {
      currentNavBarIndex -= 1;
    } else {
      currentNavBarIndex += 1;
    }
    tabs = getTabs();
    refresh();
  }

  List<TabInformation> getTabs() {
    List<TabInformation> items = [
      TabInformation(
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: "Search",
          ),
          SearchPage(myHomePageController: this)),
      TabInformation(
          BottomNavigationBarItem(
            icon: Icon(Icons.view_list),
            label: "Lists",
          ),
          WordListsOverviewPage(myHomePageController: this)),
    ];

    if (getShowFlashcards()) {
      items.add(TabInformation(
        BottomNavigationBarItem(
          icon: Icon(Icons.style),
          label: "Revision",
        ),
        FlashcardsLandingPage(myHomePageController: this),
      ));
    }

    items.add(TabInformation(
        BottomNavigationBarItem(
          icon: Icon(Icons.settings),
          label: "Settings",
        ),
        SettingsPage(myHomePageController: this)));

    return items;
  }

  List<BottomNavigationBarItem> getBottomNavBarItems() {
    return tabs.map((e) => e.bottomNavBarItem).toList();
  }

  Widget getCurrentScaffold() {
    return tabs[currentNavBarIndex].tabBody;
  }

  MyHomePageController.fromInit(void Function() r) {
    currentNavBarIndex = 0;
    tabs = getTabs();
    refresh = r;
  }

  MyHomePageController(
      {required this.currentNavBarIndex,
      required this.tabs,
      required this.refresh});
}

class _MyHomePageState extends State<MyHomePage> {
  bool advisoryShownOnce = false;

  late MyHomePageController controller;

  @override
  void initState() {
    super.initState();
    controller = MyHomePageController.fromInit(refresh);
  }

  void refresh() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return controller.getCurrentScaffold();
  }
}

Scaffold buildTopLevelScaffold(
    {required MyHomePageController myHomePageController,
    required Widget body,
    required String title,
    List<Widget>? actions,
    Widget? floatingActionButton}) {
  actions = actions ?? [];
  return Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: buildActionButtons(actions),
      centerTitle: true,
    ),
    body: body,
    floatingActionButton: floatingActionButton,
    bottomNavigationBar: BottomNavigationBar(
      items: myHomePageController.getBottomNavBarItems(),
      currentIndex: myHomePageController.currentNavBarIndex,
      selectedItemColor: MAIN_COLOR,
      onTap: myHomePageController.onNavBarItemTapped,
      type: BottomNavigationBarType.fixed,
    ),
  );
}
