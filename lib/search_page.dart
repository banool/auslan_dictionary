import 'package:flutter/material.dart';

import 'common.dart';
import 'globals.dart';
import 'home_page.dart';
import 'types.dart';

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
  final MyHomePageController myHomePageController;

  SearchPage({Key? key, required this.myHomePageController}) : super(key: key);

  @override
  _SearchPageState createState() => _SearchPageState(myHomePageController);
}

class _SearchPageState extends State<SearchPage> {
  MyHomePageController myHomePageController;

  _SearchPageState(this.myHomePageController);

  List<Word?> wordsSearched = [];
  int currentNavBarIndex = 0;

  final _formSearchKey = GlobalKey<FormState>();

  final _searchFieldController = TextEditingController();

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
    if (advisory != null && !myHomePageController.advisoryShownOnce) {
      Future.delayed(Duration(milliseconds: 500), () => showAdvisoryDialog());
      myHomePageController.advisoryShownOnce = true;
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
              child: listWidget(context, wordsSearched),
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

    return buildTopLevelScaffold(
      myHomePageController: myHomePageController,
      body: body,
      title: "Search",
      actions: actions,
    );
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
  return FlatButton(
    child: Align(alignment: Alignment.topLeft, child: Text("${word.word}")),
    onPressed: () => navigateToWordPage(context, word),
    splashColor: MAIN_COLOR,
  );
}
