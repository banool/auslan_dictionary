import 'package:flutter/material.dart';

import 'common.dart';
import 'globals.dart';
import 'top_level_scaffold.dart';
import 'types.dart';

class SearchPage extends StatefulWidget {
  final String? initialQuery;

  SearchPage({Key? key, this.initialQuery}) : super(key: key);

  @override
  _SearchPageState createState() =>
      _SearchPageState(initialQuery: initialQuery);
}

class _SearchPageState extends State<SearchPage> {
  final String? initialQuery;

  _SearchPageState({this.initialQuery});

  List<Word?> wordsSearched = [];
  int currentNavBarIndex = 0;

  final _searchFieldController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (initialQuery != null) {
      _searchFieldController.text = initialQuery!;
      search(initialQuery!);
    }
  }

  void search(String searchTerm) {
    setState(() {
      wordsSearched = searchList(searchTerm, wordsGlobal, {});
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
    if (advisory != null && !advisoryShownOnce) {
      Future.delayed(Duration(milliseconds: 500), () => showAdvisoryDialog());
      advisoryShownOnce = true;
    }

    Widget body = Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 0.0, vertical: 8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: 10, left: 32, right: 32, top: 0),
              child: Form(
                  key: ValueKey("searchPage.searchForm"),
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
              child: Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: listWidget(context, wordsSearched)),
            ),
          ],
        ),
      ),
    );

    List<Widget> actions = [];
    if (advisory != null) {
      actions.add(buildActionButton(
        context,
        Icon(Icons.announcement),
        () async {
          showAdvisoryDialog();
        },
      ));
    }

    return TopLevelScaffold(body: body, title: "Search", actions: actions);
  }

  void showAdvisoryDialog() {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: Text("Announcement"),
              content: Text(advisory!),
            ));
  }
}

Widget listWidget(BuildContext context, List<Word?> wordsSearched) {
  return ListView.builder(
    itemCount: wordsSearched.length,
    itemBuilder: (context, index) {
      return ListTile(title: listItem(context, wordsSearched[index]!));
    },
  );
}

Widget listItem(BuildContext context, Word word) {
  return TextButton(
    child: Align(
        alignment: Alignment.topLeft,
        child: Text("${word.word}", style: TextStyle(color: Colors.black))),
    onPressed: () => navigateToWordPage(context, word),
  );
}
