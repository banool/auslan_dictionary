import 'package:auslan_dictionary/common.dart';
import 'package:auslan_dictionary/globals.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'word_list_logic.dart';
import 'word_list_page.dart';

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
    int i = 0;
    for (MapEntry<String, WordList> e in wordListManager.wordLists.entries) {
      String key = e.key;
      WordList wl = e.value;
      String name = wl.getName();
      Widget? trailing;
      if (controller.inEditMode && wl.canBeDeleted()) {
        trailing = IconButton(
            icon: Icon(
              Icons.remove_circle,
              color: Colors.red,
            ),
            onPressed: () async {
              bool confirmed = await confirmAlert(
                  context, Text("Are you sure you want to delete this list?"));
              if (confirmed) {
                await wordListManager.deleteWordList(key);
                setState(() {
                  controller.inEditMode = false;
                });
              }
            });
      }
      Card card = Card(
        key: ValueKey(name),
        child: ListTile(
          leading: wl.getLeadingIcon(inEditMode: controller.inEditMode),
          trailing: trailing,
          minLeadingWidth: 10,
          title: Text(
            name,
            textAlign: TextAlign.start,
            style: TextStyle(fontSize: 16),
          ),
          onTap: () async {
            await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => WordListPage(
                          wordList: wl,
                        )));
          },
        ),
      );
      Widget toAdd = card;
      if (wl.key == KEY_FAVOURITES_WORDS && controller.inEditMode) {
        toAdd = IgnorePointer(
          key: ValueKey(name),
          child: toAdd,
        );
      }
      if (controller.inEditMode) {
        toAdd = ReorderableDragStartListener(
            key: ValueKey(name), child: toAdd, index: i);
      }
      tiles.add(toAdd);
      i += 1;
    }
    if (controller.inEditMode) {
      return ReorderableListView(
          children: tiles,
          onReorder: (prev, updated) async {
            setState(() {
              wordListManager.reorder(prev, updated);
            });
            await wordListManager.writeWordListKeys();
          });
    } else {
      return ListView(
        children: tiles,
      );
    }
  }
}

// Returns true if a new list was created.
Future<bool> applyCreateListDialog(BuildContext context) async {
  TextEditingController controller = TextEditingController();

  List<Widget> children = [
    Text(
      "Only letters, numbers, and spaces are allowed.",
    ),
    Padding(padding: EdgeInsets.only(top: 10)),
    TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: 'Enter new list name',
      ),
      autofocus: true,
      inputFormatters: [
        FilteringTextInputFormatter.allow(WordList.validNameCharacters),
      ],
      textInputAction: TextInputAction.send,
      keyboardType: TextInputType.visiblePassword,
    )
  ];

  Widget body = Column(
    children: children,
    mainAxisSize: MainAxisSize.min,
  );
  bool confirmed = await confirmAlert(context, body, title: "New List");
  if (confirmed) {
    String name = controller.text;
    try {
      String key = WordList.getKeyFromName(name);
      await wordListManager.createWordList(key);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Failed to make new list: $e."),
          backgroundColor: Colors.red));
      confirmed = false;
    }
  }
  return confirmed;
}
