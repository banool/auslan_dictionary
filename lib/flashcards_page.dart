import 'package:auslan_dictionary/types.dart';
import 'package:flutter/material.dart';

import 'common.dart';

class FlashcardsPageController {
  bool isMounted = false;

  void onMount() {
    isMounted = true;
  }

  void dispose() {
    isMounted = false;
  }
}

class FlashcardsPage extends StatefulWidget {
  final FlashcardsPageController controller;

  FlashcardsPage({Key? key, required this.controller}) : super(key: key);

  @override
  _FlashcardsPageState createState() => _FlashcardsPageState(controller);
}

class _FlashcardsPageState extends State<FlashcardsPage> {
  late FlashcardsPageController controller;

  _FlashcardsPageState(FlashcardsPageController _controller) {
    controller = _controller;
  }

  // All the user's favourites.
  late List<Word> favourites;

  late Future<void> initStateAsyncFuture;

  @override
  void initState() {
    initStateAsyncFuture = initStateAsync();
    super.initState();
  }

  Future<void> initStateAsync() async {
    var words = await loadWords(context);
    favourites = await loadFavourites(words, context);
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
          return Container(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 0.0, vertical: 8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.max,
                children: [Text("todo")],
              ),
            ),
          );
        });
  }
}
