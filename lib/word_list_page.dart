import 'package:flutter/material.dart';

import 'common.dart';
import 'globals.dart';
import 'types.dart';
import 'word_list_logic.dart';

class WordListPage extends StatefulWidget {
  final WordList wordList;

  WordListPage({Key? key, required this.wordList}) : super(key: key);

  @override
  _WordListPageState createState() => _WordListPageState(wordList: wordList);
}

class _WordListPageState extends State<WordListPage> {
  _WordListPageState({required this.wordList});

  WordList wordList;

  // The words that match the user's search term.
  late List<Word> wordsSearched;

  bool viewSortedList = false;
  bool enableSortButton = true;

  String currentSearchTerm = "";

  final _searchFieldController = TextEditingController();

  @override
  void initState() {
    wordsSearched = List.from(wordList.words);
    super.initState();
  }

  void toggleSort() {
    setState(() {
      viewSortedList = !viewSortedList;
      search();
    });
  }

  Color getFloatingActionButtonColor() {
    return enableSortButton ? MAIN_COLOR : Colors.grey;
  }

  void updateCurrentSearchTerm(String term) {
    setState(() {
      currentSearchTerm = term;
      enableSortButton = currentSearchTerm.length == 0;
    });
  }

  void search() {
    setState(() {
      if (currentSearchTerm.length > 0) {
        wordsSearched =
            searchList(currentSearchTerm, wordList.words, wordList.words);
      } else {
        wordsSearched = List.from(wordList.words);
        if (viewSortedList) {
          wordsSearched.sort();
        }
      }
    });
  }

  void clearSearch() {
    setState(() {
      wordsSearched = [];
      _searchFieldController.clear();
      updateCurrentSearchTerm("");
      search();
    });
  }

  void removeWord(Word word) async {
    await wordList.removeWord(word);
    setState(() {
      search();
    });
  }

  Future<void> refreshWords() async {
    setState(() {
      search();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(wordList.getName()),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
          backgroundColor: getFloatingActionButtonColor(),
          onPressed: () {
            if (!enableSortButton) {
              return;
            }
            toggleSort();
          },
          child: Icon(Icons.sort)),
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 0.0, vertical: 8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: 10, left: 32, right: 32, top: 0),
              child: Form(
                  child: Column(children: <Widget>[
                TextField(
                  controller: _searchFieldController,
                  decoration: InputDecoration(
                    hintText: "Search ${wordList.getName()}",
                    suffixIcon: IconButton(
                      onPressed: () {
                        clearSearch();
                      },
                      icon: Icon(Icons.clear),
                    ),
                  ),
                  // The validator receives the text that the user has entered.
                  onChanged: (String value) {
                    updateCurrentSearchTerm(value);
                    search();
                  },
                  autofocus: false,
                  textInputAction: TextInputAction.search,
                  keyboardType: TextInputType.visiblePassword,
                  autocorrect: false,
                ),
              ])),
            ),
            new Expanded(
              child: listWidget(
                  context, wordsSearched, wordsGlobal, refreshWords,
                  showFavouritesButton: wordList.key == KEY_FAVOURITES_WORDS),
            ),
          ],
        ),
      ),
    );
  }
}

Widget listWidget(BuildContext context, List<Word?> wordsSearched,
    Set<Word> allWords, Function refreshWordsFn,
    {bool showFavouritesButton = true}) {
  return ListView.builder(
    itemCount: wordsSearched.length,
    itemBuilder: (context, index) {
      return ListTile(
          title: listItem(context, wordsSearched[index]!, refreshWordsFn,
              showFavouritesButton: showFavouritesButton));
    },
  );
}

// We can pass in showFavouritesButton and set it to false for lists that
// aren't the the favourites list, since that star icon might be confusing
// and lead people to beleive they're interacting with the non-favourites
// list they just came from.
Widget listItem(BuildContext context, Word word, Function refreshWordsFn,
    {bool showFavouritesButton = true}) {
  return FlatButton(
    child: Align(alignment: Alignment.topLeft, child: Text("${word.word}")),
    onPressed: () async => {
      await navigateToWordPage(context, word,
          showFavouritesButton: showFavouritesButton),
      await refreshWordsFn(),
    },
    splashColor: MAIN_COLOR,
  );
}
