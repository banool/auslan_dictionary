import 'package:auslan_dictionary/main.dart';
import 'package:auslan_dictionary/types.dart';
import 'package:flutter/material.dart';

import 'common.dart';

class SearchPageController {
  bool isMounted = false;

  void onMount() {
    isMounted = true;
  }

  void dispose() {
    isMounted = false;
  }

  late void Function() clearSearch;
}

class SearchPage extends StatefulWidget {
  final SearchPageController? controller;

  SearchPage({Key? key, this.controller}) : super(key: key);

  @override
  _SearchPageState createState() => _SearchPageState(controller);
}

class _SearchPageState extends State<SearchPage> {
  SearchPageController? controller;

  // We do this so the parent can call clearSearch
  // https://stackoverflow.com/a/60869283/3846032
  _SearchPageState(SearchPageController? _controller) {
    controller = _controller;
    controller!.clearSearch = clearSearch;
    controller!.onMount();
  }

  bool wordsLoaded = false;
  List<Word?> wordsSearched = [];
  int currentNavBarIndex = 0;

  final _formSearchKey = GlobalKey<FormState>();

  final _searchFieldController = TextEditingController();

  @override
  void initState() {
    // We don't care about waiting for the future, we check wordsLoaded
    // instead and use that to determine whether to show the content.
    // Not really good practice, but it's how I did it.
    initStateAsync();
    super.initState();
  }

  Future<void> initStateAsync() async {
    setState(() {
      wordsLoaded = true;
    });
  }

  @override
  void dispose() {
    controller!.dispose();
    super.dispose();
  }

  void search(String searchTerm) {
    setState(() {
      wordsSearched = searchList(searchTerm, wordsGlobal, []);
    });
  }

  void clearSearch() {
    setState(() {
      wordsSearched = [];
      _searchFieldController.clear();
    });
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
                    child: listWidget(context, wordsSearched, wordsGlobal),
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
    BuildContext context, List<Word?> wordsSearched, List<Word> allWords) {
  return ListView.builder(
    itemCount: wordsSearched.length,
    itemBuilder: (context, index) {
      return ListTile(
          title: listItem(context, wordsSearched[index]!, allWords));
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
