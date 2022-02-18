import 'package:auslan_dictionary/main.dart';
import 'package:auslan_dictionary/types.dart';
import 'package:flutter/material.dart';

import 'common.dart';

// - Add option to disable flashcards entirely, removes item from bottom nav bar.
// - Or perhaps only have that setting in settings and then put the others in the flashcards page.
// - The first screen for flashcards should be something that lets you choose
//   what list to revise. At first only favourites.
// - Once you start the review, push navigation, so you can't change the favourites
//   mid review.
// - In the settings, let people choose what state(s) they want to see flashcards for.
//   - What about the regional information unknown case?
// - In the settings, let people choose sign -> word and word -> sign.
// - In the flashcards app bar have a history button to see a summary of previous flashcard sessions.
// - In the settings, let people choose between random revision and spaced repetition, and in order (alphabetical or insertion order).
// - Add option to choose limit, like x cards at a time.

class FlashcardsPageController {
  bool isMounted = false;

  void onMount() {
    isMounted = true;
  }

  void dispose() {
    isMounted = false;
  }

  void Function() goToSettingsFunction;

  FlashcardsPageController(this.goToSettingsFunction);
}

class FlashcardsLandingPage extends StatefulWidget {
  final FlashcardsPageController controller;

  FlashcardsLandingPage({Key? key, required this.controller}) : super(key: key);

  @override
  _FlashcardsLandingPageState createState() =>
      _FlashcardsLandingPageState(controller);
}

class _FlashcardsLandingPageState extends State<FlashcardsLandingPage> {
  late FlashcardsPageController controller;

  _FlashcardsLandingPageState(FlashcardsPageController _controller) {
    controller = _controller;
  }

  @override
  Widget build(BuildContext context) {
    return Center(
        child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TextButton(
          child: Text(
            "Start",
            textAlign: TextAlign.center,
          ),
          style: ButtonStyle(
            backgroundColor: MaterialStateProperty.all<Color>(MAIN_COLOR),
            foregroundColor: MaterialStateProperty.all<Color>(Colors.white),
          ),
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => FlashcardsPage()),
            );
          },
        ),
        TextButton(
          child: Text(
            "Flashcard Settings",
            textAlign: TextAlign.center,
          ),
          style: ButtonStyle(
            backgroundColor: MaterialStateProperty.all<Color>(MAIN_COLOR),
            foregroundColor: MaterialStateProperty.all<Color>(Colors.white),
          ),
          onPressed: () {
            controller.goToSettingsFunction();
          },
        ),
      ],
    ));
  }
}

class FlashcardsPage extends StatefulWidget {
  FlashcardsPage({Key? key}) : super(key: key);

  @override
  _FlashcardsPageState createState() => _FlashcardsPageState();
}

class _FlashcardsPageState extends State<FlashcardsPage> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Start"),
      ],
    );
  }
}
