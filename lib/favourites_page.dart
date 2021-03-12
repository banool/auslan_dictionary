import 'dart:convert';

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
  List<Word> words = [];

  // All the user's favourites.
  List<Word?> favourites = [];

  // The favourites that match the user's search term.
  List<Word?> favouritesSearched = [];

  String currentSearchTerm = "";

  final _favouritesFieldController = TextEditingController();

  Future<void>? initStateAsyncFuture;
  SharedPreferences? prefs;

  @override
  void initState() {
    initStateAsyncFuture = initStateAsync();
    super.initState();
  }

  Future<void> initStateAsync() async {
    // I assume that we load the words first, don't change this order.
    await loadWords();
    await loadFavouritesInner();
  }

  Future<void> loadFavouritesInner() async {
    favourites = await loadFavourites(words, context);
    favouritesSearched = favourites;
    search(currentSearchTerm);
  }

  Future<void> loadWords() async {
    String data = await DefaultAssetBundle.of(context)
        .loadString("assets/data/words.json");
    dynamic wordsJson = json.decode(data);
    for (MapEntry e in wordsJson.entries) {
      words.add(Word.fromJson(e.key, e.value));
    }
    print("Loaded ${words.length} words");
  }

  void search(String searchTerm) {
    setState(() {
      currentSearchTerm = searchTerm;
      favouritesSearched = searchList(searchTerm, favourites, favourites);
    });
  }

  void clearFavourites() {
    setState(() {
      favouritesSearched = favourites;
      _favouritesFieldController.clear();
    });
  }

  void removeFavourite(Word word) {
    removeFromFavourites(word, words, context);
    setState(() {
      favourites.removeWhere((element) => element!.word == word.word);
    });
  }

  Future<void> refreshFavourites() async {
    await loadFavouritesInner();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: initStateAsyncFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return new Center(
              child: new CircularProgressIndicator(),
            );
          }
          return Center(
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
                              clearFavourites();
                            },
                            icon: Icon(Icons.clear),
                          ),
                        ),
                        // The validator receives the text that the user has entered.
                        onChanged: (String value) {
                          search(value);
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
