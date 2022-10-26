import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'common.dart';
import 'globals.dart';
import 'top_level_scaffold.dart';
import 'word_list_logic.dart';
import 'word_list_overview_help_page.dart';
import 'word_list_page.dart';

class WordListsOverviewPage extends StatefulWidget {
  @override
  _WordListsOverviewPageState createState() => _WordListsOverviewPageState();
}

class _WordListsOverviewPageState extends State<WordListsOverviewPage> {
  bool inEditMode = false;

  @override
  Widget build(BuildContext context) {
    List<Widget> tiles = [];
    int i = 0;
    for (MapEntry<String, WordList> e in wordListManager.wordLists.entries) {
      String key = e.key;
      WordList wl = e.value;
      String name = wl.getName();
      Widget? trailing;
      if (inEditMode && wl.canBeDeleted()) {
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
                  inEditMode = false;
                });
              }
            });
      }
      Card card = Card(
        key: ValueKey(name),
        child: ListTile(
          leading: wl.getLeadingIcon(inEditMode: inEditMode),
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
      if (wl.key == KEY_FAVOURITES_WORDS && inEditMode) {
        toAdd = IgnorePointer(
          key: ValueKey(name),
          child: toAdd,
        );
      }
      if (inEditMode) {
        toAdd = ReorderableDragStartListener(
            key: ValueKey(name), child: toAdd, index: i);
      }
      tiles.add(toAdd);
      i += 1;
    }
    Widget body;
    if (inEditMode) {
      body = ReorderableListView(
          children: tiles,
          onReorder: (prev, updated) async {
            setState(() {
              wordListManager.reorder(prev, updated);
            });
            await wordListManager.writeWordListKeys();
          });
    } else {
      body = ListView(
        children: tiles,
      );
    }

    FloatingActionButton? floatingActionButton;
    if (inEditMode) {
      floatingActionButton = FloatingActionButton(
          backgroundColor: Colors.green,
          onPressed: () async {
            bool confirmed = await applyCreateListDialog(context);
            if (confirmed) {
              setState(() {
                inEditMode = false;
              });
            }
          },
          child: Icon(Icons.add));
    }

    List<Widget> actions = [
      buildActionButton(
        context,
        inEditMode ? Icon(Icons.edit) : Icon(Icons.edit_outlined),
        () async {
          setState(() {
            inEditMode = !inEditMode;
          });
        },
      ),
      buildActionButton(
        context,
        Icon(Icons.help),
        () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => getWordListOverviewHelpPage()),
          );
        },
      )
    ];

    return TopLevelScaffold(
        body: body,
        title: "Lists",
        actions: actions,
        floatingActionButton: floatingActionButton);
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
      textCapitalization: TextCapitalization.words,
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
