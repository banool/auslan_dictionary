import 'package:auslan_dictionary/common.dart';
import 'package:auslan_dictionary/globals.dart';
import 'package:flutter/material.dart';

import 'word_list_logic.dart';

class WordListsOverviewController {
  bool inEditMode = false;

  void toggleEditMode() {
    inEditMode = !inEditMode;
  }
}

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
      Widget? trailing;
      if (controller.inEditMode) {
        trailing = IconButton(
          icon: Icon(
            Icons.remove_circle,
            color: Colors.red,
          ),
          onPressed: () => print("todo"),
        );
      }
      tiles.add(Card(
        child: ListTile(
          leading: wl.getLeadingIcon(),
          trailing: trailing,
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

// Returns true if a new list was created.
Future<bool> showCreateListDialog(BuildContext context) async {
  return confirmAlert(context, Text("testing"));
}
