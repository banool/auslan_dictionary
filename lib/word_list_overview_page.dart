import 'package:auslan_dictionary/globals.dart';
import 'package:flutter/material.dart';

import 'word_list_logic.dart';

class WordListsOverviewController {}

class WordListsOverviewPage extends StatefulWidget {
  final WordListsOverviewController controller;

  WordListsOverviewPage({Key? key, required this.controller}) : super(key: key);

  @override
  _WordListsOverviewPageState createState() =>
      _WordListsOverviewPageState(controller: controller);
}

class _WordListsOverviewPageState extends State<WordListsOverviewPage> {
  WordListsOverviewController controller;

  _WordListsOverviewPageState({required this.controller});

  @override
  Widget build(BuildContext context) {
    List<Widget> tiles = [];
    for (MapEntry<String, WordList> e in wordListManager.wordLists.entries) {
      WordList wl = e.value;
      tiles.add(Card(
        child: ListTile(
          leading: wl.getLeadingIcon(),
          minLeadingWidth: 10,
          title: Text(
            wl.getName(),
            textAlign: TextAlign.start,
            style: TextStyle(fontSize: 16),
          ),
        ),
      ));
    }
    return ListView(
      children: tiles,
    );
  }
}
