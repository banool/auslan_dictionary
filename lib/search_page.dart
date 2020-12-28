import "dart:collection";
import 'dart:convert';

import 'package:auslan_dictionary/types.dart';
import 'package:edit_distance/edit_distance.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'common.dart';

class SearchPageController {
  bool isMounted = false;

  void onMount() {
    isMounted = true;
  }

  void dispose() {
    isMounted = false;
  }

  void Function() clearSearch;
}

class SearchPage extends StatefulWidget {
  final SearchPageController controller;

  SearchPage({Key key, this.controller}) : super(key: key);

  @override
  _SearchPageState createState() => _SearchPageState(controller);
}

class _SearchPageState extends State<SearchPage> {
  SearchPageController controller;

  // We do this so the parent can call clearSearch
  // https://stackoverflow.com/a/60869283/3846032
  _SearchPageState(SearchPageController _controller) {
    controller = _controller;
    controller.clearSearch = clearSearch;
    controller.onMount();
  }

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

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void search(String searchTerm) {
    setState(() {
      wordsSearched = searchWords(searchTerm);
    });
  }

  void clearSearch() {
    setState(() {
      wordsSearched = [];
      _searchFieldController.clear();
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
                                  clearSearch();
                                },
                                icon: Icon(Icons.clear),
                              ),
                            ),
                            // The validator receives the text that the user has entered.
                            onChanged: (String value) {
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