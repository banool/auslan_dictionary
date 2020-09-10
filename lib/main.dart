import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'word_page.dart';

const Color MAIN_COLOR = Colors.blue;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Auslan Dictionary',
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
      home: MyHomePage(title: 'Auslan Dictionary'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<String> items = [];
  bool wordsLoaded = false;
  Map<String, dynamic> words;

  final _formSearchKey = GlobalKey<FormState>();

  void search(String value) {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      items = searchKeys(value);
    });
  }

  Future<void> loadWords() async {
    String data = await DefaultAssetBundle.of(context)
        .loadString("assets/data/words.json");
    words = json.decode(data);
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

  List<String> searchKeys(String searchString) {
    List<String> out = [];
    for (String k in words.keys) {
      if (k.contains(searchString)) {
        out.add(k);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: wordsLoaded
          ? Center(
              // Center is a layout widget. It takes a single child and positions it
              // in the middle of the parent.
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 0.0, vertical: 8.0),
                child: Column(
                  // Column is also a layout widget. It takes a list of children and
                  // arranges them vertically. By default, it sizes itself to fit its
                  // children horizontally, and tries to be as tall as its parent.
                  //
                  // Invoke "debug painting" (press "p" in the console, choose the
                  // "Toggle Debug Paint" action from the Flutter Inspector in Android
                  // Studio, or the "Toggle Debug Paint" command in Visual Studio Code)
                  // to see the wireframe for each widget.
                  //
                  // Column has various properties to control how it sizes itself and
                  // how it positions its children. Here we use mainAxisAlignment to
                  // center the children vertically; the main axis here is the vertical
                  // axis because Columns are vertical (the cross axis would be
                  // horizontal).
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
                  children: <Widget>[
                    Padding(
                      padding: EdgeInsets.only(
                          bottom: 10, left: 32, right: 32, top: 0),
                      child: Form(
                          key: _formSearchKey,
                          child: Column(children: <Widget>[
                            TextField(
                                decoration: const InputDecoration(
                                  hintText: 'Search for a word',
                                ),
                                // The validator receives the text that the user has entered.
                                onSubmitted: (String value) {
                                  search(value);
                                },
                                autofocus: true,
                                textInputAction: TextInputAction.search),
                          ])),
                    ),
                    new Expanded(
                      child: listWidget(context, items),
                    ),
                  ],
                ),
              ),
            )
          : new Center(
              child: new CircularProgressIndicator(),
            ),
    );
  }
}

Widget listWidget(BuildContext context, List<String> items) {
  return ListView.builder(
    itemCount: items.length,
    itemBuilder: (context, index) {
      return ListTile(title: listItem(context, items[index]));
    },
  );
}

Widget listItem(BuildContext context, String word) {
  return FlatButton(
    child: Align(alignment: Alignment.topLeft, child: Text('$word')),
    onPressed: () {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => WordPage(word: word)),
      );
    },
    splashColor: MAIN_COLOR,
  );
}
