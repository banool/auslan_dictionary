import 'package:flutter/material.dart';

class HelpPage extends StatelessWidget {
  final String title;
  final Map<String, List<String>> items;

  HelpPage({required this.title, required this.items});

  Widget build(BuildContext context) {
    List<Widget> tiles = [];
    for (MapEntry<String, List<String>> e in items.entries) {
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
                List<Widget> children = [];
                for (String s in e.value) {
                  children.add(Text(
                    s,
                    strutStyle: StrutStyle(fontSize: 15),
                  ));
                  children.add(Padding(
                    padding: EdgeInsets.only(top: 20),
                  ));
                }
                children.removeLast();
                return SimpleDialog(
                  contentPadding: EdgeInsets.all(20),
                  children: children,
                );
              }),
        ),
      ));
    }
    return Scaffold(
        appBar: AppBar(
          title: Text(title),
        ),
        body: ListView(
          children: tiles,
        ));
  }
}
