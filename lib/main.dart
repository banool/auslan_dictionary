import "dart:collection";
import 'dart:convert';

import 'package:auslan_dictionary/types.dart';
import 'package:edit_distance/edit_distance.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'common.dart';

const Color MAIN_COLOR = Colors.blue;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: () {
          FocusScopeNode currentFocus = FocusScope.of(context);

          if (!currentFocus.hasPrimaryFocus &&
              currentFocus.focusedChild != null) {
            FocusManager.instance.primaryFocus.unfocus();
          }
        },
        child: MaterialApp(
          title: 'Auslan Dictionary',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
              // This is the theme of your application.
              //
              // Try running your application with "flutter run". You'll see the
              // application has a blue toolbar. Then, without quitting the app, try
              // changing the primarySwatch below to Colors.green and then invoke
              // "hot reload" (press "r" in the console where you ran "flutter run",
              // or simply save your changes to "hot reload" in a Flutter IDE).
              // Notice that the counter didn't reset back to zero; the application
              // is not restarted.
              primarySwatch: MAIN_COLOR,
              // This makes the visual density adapt to the platform that you run
              // the app on. For desktop platforms, the controls will be smaller and
              // closer together (more dense) than on mobile platforms.
              visualDensity: VisualDensity.adaptivePlatformDensity,
              // Make swiping to pop back the navigation work.
              pageTransitionsTheme: PageTransitionsTheme(builders: {
                TargetPlatform.android: CupertinoPageTransitionsBuilder(),
                TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
              })),
          home: MyHomePage(title: "Auslan Dictionary"),
        ));
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool wordsLoaded = false;
  int currentNavBarIndex = 0;

  void onNavBarItemTapped(int index) {
    setState(() {
      currentNavBarIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> tabs = [
      SearchPage(),
      SettingsPage(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: tabs[currentNavBarIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: "Dictionary",
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

class SearchPage extends StatefulWidget {
  SearchPage({Key key}) : super(key: key);

  @override
  _SearchPageState createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  bool wordsLoaded = false;
  List<Word> words = [];
  List<Word> wordsSearched = [];
  int currentNavBarIndex = 0;

  final _formSearchKey = GlobalKey<FormState>();

  final _searchFieldController = TextEditingController();

  Future<void> loadWords() async {
    String data = await DefaultAssetBundle.of(context)
        .loadString("assets/data/words.json");
    dynamic wordsJson = json.decode(data);
    for (MapEntry e in wordsJson.entries) {
      words.add(Word.fromJson(e.key, e.value));
    }
    setState(() {
      wordsLoaded = true;
    });
    print("Loaded ${words.length} words");
  }

  @override
  void initState() {
    loadWords();
    super.initState();
  }

  void search(String searchTerm) {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      wordsSearched = searchWords(searchTerm);
    });
  }

  void clearSearch() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      wordsSearched = [];
    });
  }

  List<Word> searchWords(String searchTerm) {
    final SplayTreeMap<double, List<Word>> st =
        SplayTreeMap<double, List<Word>>();
    if (searchTerm == "") {
      return [];
    }
    searchTerm = searchTerm.toLowerCase();
    JaroWinkler d = new JaroWinkler();
    RegExp noParenthesesRegExp = new RegExp(
      r"^[^ (]*",
      caseSensitive: false,
      multiLine: false,
    );
    for (Word w in words) {
      String noPunctuation = w.word.replaceAll(" ", "").replaceAll(",", "");
      String lowerCase = noPunctuation.toLowerCase();
      String noParenthesesContent = noParenthesesRegExp.stringMatch(lowerCase);
      String normalisedWord = noParenthesesContent;
      double difference = d.normalizedDistance(normalisedWord, searchTerm);
      st.putIfAbsent(difference, () => []).add(w);
    }
    List<Word> out = [];
    for (List<Word> words in st.values) {
      out.addAll(words);
      if (out.length > 10) {
        break;
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return wordsLoaded
        ? Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 0.0, vertical: 8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.max,
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                        bottom: 10, left: 32, right: 32, top: 0),
                    child: Form(
                        key: _formSearchKey,
                        child: Column(children: <Widget>[
                          TextField(
                            controller: _searchFieldController,
                            decoration: InputDecoration(
                              hintText: 'Search for a word',
                              suffixIcon: IconButton(
                                onPressed: () {
                                  _searchFieldController.clear();
                                  clearSearch();
                                },
                                icon: Icon(Icons.clear),
                              ),
                            ),
                            // The validator receives the text that the user has entered.
                            onSubmitted: (String value) {
                              search(value);
                            },
                            autofocus: true,
                            textInputAction: TextInputAction.search,
                            keyboardType: TextInputType.visiblePassword,
                            autocorrect: false,
                          ),
                        ])),
                  ),
                  new Expanded(
                    child: listWidget(context, wordsSearched, words),
                  ),
                ],
              ),
            ),
          )
        : new Center(
            child: new CircularProgressIndicator(),
          );
  }
}

Widget listWidget(
    BuildContext context, List<Word> wordsSearched, List<Word> allWords) {
  return ListView.builder(
    itemCount: wordsSearched.length,
    itemBuilder: (context, index) {
      return ListTile(title: listItem(context, wordsSearched[index], allWords));
    },
  );
}

Widget listItem(BuildContext context, Word word, List<Word> allWords) {
  return FlatButton(
    child: Align(alignment: Alignment.topLeft, child: Text("${word.word}")),
    onPressed: () => navigateToWordPage(context, word, allWords),
    splashColor: MAIN_COLOR,
  );
}

class SettingsPage extends StatefulWidget {
  SettingsPage({Key key}) : super(key: key);

  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  Future<void> initStateAsyncFuture;

  SharedPreferences prefs;

  @override
  void initState() {
    initStateAsyncFuture = initStateAsync();
    super.initState();
  }

  Future<void> initStateAsync() async {
    prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(KEY_SHOULD_CACHE) == null) {
      prefs.setBool(KEY_SHOULD_CACHE, true);
    }
  }

  void onChangeShouldCache(bool newValue) {
    setState(() {
      prefs.setBool(KEY_SHOULD_CACHE, newValue);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: EdgeInsets.only(bottom: 10, left: 20, right: 32, top: 20),
        child: FutureBuilder(
            future: initStateAsyncFuture,
            builder: (context, snapshot) {
              var waitingWidget = Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [CircularProgressIndicator()],
                  ));
              if (snapshot.connectionState != ConnectionState.done) {
                return waitingWidget;
              }
              return Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Text("Cache videos:"),
                          Switch(
                            value: prefs.getBool(KEY_SHOULD_CACHE),
                            onChanged: onChangeShouldCache,
                          )
                        ]),
                    FlatButton(
                        child: Text("Drop cache"),
                        onPressed: () async {
                          await DefaultCacheManager().emptyCache();
                          Scaffold.of(context).showSnackBar(SnackBar(
                              content: Text("Cache dropped"),
                              backgroundColor: MAIN_COLOR));
                        },
                        color: MAIN_COLOR),
                  ]);
            }));
  }
}
