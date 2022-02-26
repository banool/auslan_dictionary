import 'package:auslan_dictionary/common.dart';
import 'package:flutter/material.dart';

class FlashcardsHelpPage extends StatefulWidget {
  @override
  _FlashcardsHelpPageState createState() => _FlashcardsHelpPageState();
}

class _FlashcardsHelpPageState extends State<FlashcardsHelpPage> {
  @override
  Widget build(BuildContext context) {
    Map<String, Widget> items = {
      "What do the Flashcard Types mean?": Container(),
      "How does the random revision strategy work?": Container(),
      "How does the spaced repetition revision strategy work?": Container(),
      "What do all these sign selection options mean?": Container(),
      "What does \"Show only one entry per word\" mean?": Container(),
    };
    List<Widget> tiles = [];
    for (MapEntry<String, Widget> e in items.entries) {
      tiles.add(Card(
        child: ListTile(
          title: Text(
            e.key,
            textAlign: TextAlign.start,
            style: TextStyle(fontSize: 14),
          ),
          onTap: () async => showDialog(
              context: context,
              builder: (BuildContext context) {
                SimpleDialog dialog = SimpleDialog();
                return dialog;
              }),
        ),
      ));
    }
    return Scaffold(
        appBar: AppBar(
          title: Text("Revision FAQ"),
        ),
        body: ListView(
          children: tiles,
        ));
  }
}
