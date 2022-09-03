import 'package:flutter/material.dart';

import 'common.dart';
import 'globals.dart';
import 'types.dart';
import 'word_list_help_page.dart';
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
  bool inEditMode = false;

  String currentSearchTerm = "";

  final textFieldFocus = FocusNode();
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
        if (inEditMode) {
          Set<Word> wordsGlobalWithoutWordsAlreadyInList =
              wordsGlobal.difference(wordList.words);
          wordsSearched = searchList(
              currentSearchTerm, wordsGlobalWithoutWordsAlreadyInList, {});
        } else {
          wordsSearched =
              searchList(currentSearchTerm, wordList.words, wordList.words);
        }
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

  Future<void> addWord(Word word) async {
    await wordList.addWord(word);
    setState(() {
      search();
    });
  }

  Future<void> removeWord(Word word) async {
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
    List<Widget> actions = [
      buildActionButton(
        context,
        inEditMode ? Icon(Icons.edit) : Icon(Icons.edit_outlined),
        () async {
          setState(() {
            inEditMode = !inEditMode;
            if (!inEditMode) {
              clearSearch();
            }
            search();
          });
        },
      ),
      buildActionButton(
        context,
        Icon(Icons.help),
        () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => getWordListHelpPage()),
          );
        },
      ),
    ];

    String listName = wordList.getName();

    FloatingActionButton? floatingActionButton = FloatingActionButton(
        backgroundColor: getFloatingActionButtonColor(),
        onPressed: () {
          if (!enableSortButton) {
            return;
          }
          toggleSort();
        },
        child: Icon(Icons.sort));

    String hintText;
    if (inEditMode) {
      hintText = "Search for words to add";
      bool keyboardIsShowing = MediaQuery.of(context).viewInsets.bottom > 0;
      if (currentSearchTerm.length > 0 || keyboardIsShowing) {
        floatingActionButton = null;
      } else {
        floatingActionButton = FloatingActionButton(
            backgroundColor: Colors.green,
            onPressed: () {
              textFieldFocus.requestFocus();
            },
            child: Icon(Icons.add));
      }
    } else {
      hintText = "Search $listName";
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(wordList.getName()),
        centerTitle: true,
        actions: buildActionButtons(actions),
      ),
      floatingActionButton: floatingActionButton,
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
                  focusNode: textFieldFocus,
                  decoration: InputDecoration(
                    hintText: hintText,
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
            Expanded(
                child: Padding(
              padding: EdgeInsets.only(left: 8),
              child: listWidget(
                  context, wordsSearched, wordsGlobal, refreshWords,
                  showFavouritesButton: wordList.key == KEY_FAVOURITES_WORDS,
                  deleteWordFn: inEditMode && currentSearchTerm.length == 0
                      ? removeWord
                      : null,
                  addWordFn: inEditMode && currentSearchTerm.length > 0
                      ? addWord
                      : null),
            )),
          ],
        ),
      ),
    );
  }
}

Widget listWidget(
  BuildContext context,
  List<Word?> wordsSearched,
  Set<Word> allWords,
  Function refreshWordsFn, {
  bool showFavouritesButton = true,
  Future<void> Function(Word)? deleteWordFn,
  Future<void> Function(Word)? addWordFn,
}) {
  return ListView.builder(
    itemCount: wordsSearched.length,
    itemBuilder: (context, index) {
      Word word = wordsSearched[index]!;
      Widget? trailing;
      if (deleteWordFn != null) {
        trailing = IconButton(
          padding: EdgeInsets.only(left: 8, right: 16, top: 8, bottom: 8),
          icon: Icon(
            Icons.remove_circle,
            color: Colors.red,
          ),
          onPressed: () async => await deleteWordFn(word),
        );
      }
      if (addWordFn != null) {
        trailing = IconButton(
          padding: EdgeInsets.only(left: 8, right: 16, top: 8, bottom: 8),
          icon: Icon(
            Icons.add_circle,
            color: Colors.green,
          ),
          onPressed: () async => await addWordFn(word),
        );
      }
      return ListTile(
        key: ValueKey(word.word),
        title: listItem(context, word, refreshWordsFn,
            showFavouritesButton: showFavouritesButton),
        trailing: trailing,
      );
    },
  );
}

// We can pass in showFavouritesButton and set it to false for lists that
// aren't the the favourites list, since that star icon might be confusing
// and lead people to beleive they're interacting with the non-favourites
// list they just came from.
Widget listItem(BuildContext context, Word word, Function refreshWordsFn,
    {bool showFavouritesButton = true}) {
  return TextButton(
    child: Align(
        alignment: Alignment.topLeft,
        child: Text(
          "${word.word}",
          style: TextStyle(color: Colors.black),
        )),
    onPressed: () async => {
      await navigateToWordPage(context, word,
          showFavouritesButton: showFavouritesButton),
      await refreshWordsFn(),
    },
  );
}
