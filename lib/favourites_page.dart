import 'package:auslan_dictionary/types.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'common.dart';

// todo add ability to sort by time added and alphabetically

class FavouritesPage extends StatefulWidget {
  FavouritesPage({Key? key}) : super(key: key);

  @override
  _FavouritesPageState createState() => _FavouritesPageState();
}

class _FavouritesPageState extends State<FavouritesPage> {
  // All the words in the dictionary.
  late List<Word> words;

  // All the user's favourites.
  late List<Word> favourites;

  // TODO: Let users choose to sort list items by default or not.
  bool viewSortedList = false;

  // The favourites that match the user's search term.
  late List<Word> favouritesSearched;

  String currentSearchTerm = "";

  final _favouritesFieldController = TextEditingController();

  late Future<void> initStateAsyncFuture;
  late SharedPreferences prefs;

  void toggleSort() {
    setState(() {
      viewSortedList = !viewSortedList;
      search();
    });
  }

  @override
  void initState() {
    initStateAsyncFuture = initStateAsync();
    super.initState();
  }

  Future<void> initStateAsync() async {
    // I assume that we load the words first, don't change this order.
    words = await loadWords(context);
    await loadFavouritesInner();
  }

  Future<void> loadFavouritesInner() async {
    favourites = await loadFavourites(words, context);
    favouritesSearched = List.from(favourites);
  }

  void updateCurrentSearchTerm(String term) {
    setState(() {
      currentSearchTerm = term;
    });
  }

  void search() {
    setState(() {
      if (currentSearchTerm.length > 0) {
        favouritesSearched =
            searchList(currentSearchTerm, favourites, favourites);
      } else {
        favouritesSearched = List.from(favourites);
        if (viewSortedList) {
          favouritesSearched.sort();
        }
      }
    });
  }

  void clearSearch() {
    setState(() {
      favouritesSearched = List.from(favourites);
      _favouritesFieldController.clear();
      currentSearchTerm = "";
      search();
    });
  }

  void removeFavourite(Word word) {
    removeFromFavourites(word, words, context);
    setState(() {
      favourites.removeWhere((element) => element.word == word.word);
      search();
    });
  }

  Future<void> refreshFavourites() async {
    await loadFavouritesInner();
    setState(() {
      search();
    });
  }

  @override
  Widget build(BuildContext context) {
    bool enableSortButton = currentSearchTerm.length == 0;
    Color floatingActionButtonColor =
        enableSortButton ? MAIN_COLOR : Colors.grey;
    print(floatingActionButtonColor);
    return FutureBuilder(
        future: initStateAsyncFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return new Center(
              child: new CircularProgressIndicator(),
            );
          }
          return Container(
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
                        child: Column(children: <Widget>[
                      TextField(
                        controller: _favouritesFieldController,
                        decoration: InputDecoration(
                          hintText: 'Search your favourites',
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
                    child: listWidget(context, favouritesSearched, words,
                        removeFavourite, refreshFavourites),
                  ),
                  // TODO: Just do this with a scaffold like a normal person.
                  Align(
                    child: Container(
                      child: FloatingActionButton(
                          backgroundColor: floatingActionButtonColor,
                          onPressed: () {
                            if (!enableSortButton) {
                              return;
                            }
                            toggleSort();
                          },
                          child: Icon(Icons.sort)),
                      padding: EdgeInsets.only(right: 20, bottom: 10),
                    ),
                    alignment: Alignment.bottomRight,
                  )
                ],
              ),
            ),
          );
        });
  }
}

Widget listWidget(
    BuildContext context,
    List<Word?> favouritesSearched,
    List<Word> allWords,
    Function removeFavouriteFn,
    Function refreshFavouritesFn) {
  return ListView.builder(
    itemCount: favouritesSearched.length,
    itemBuilder: (context, index) {
      return ListTile(
          title: listItem(context, favouritesSearched[index]!, allWords,
              removeFavouriteFn, refreshFavouritesFn));
    },
  );
}

Widget listItem(BuildContext context, Word word, List<Word> allWords,
    Function removeFavouriteFn, Function refreshFavouritesFn) {
  return FlatButton(
    child: Align(alignment: Alignment.topLeft, child: Text("${word.word}")),
    onPressed: () async => {
      await navigateToWordPage(context, word, allWords),
      await refreshFavouritesFn(),
    },
    onLongPress: () => removeFavouriteFn(word),
    splashColor: MAIN_COLOR,
  );
}
