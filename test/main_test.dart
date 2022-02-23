import 'package:auslan_dictionary/types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:auslan_dictionary/main.dart';
import 'package:auslan_dictionary/globals.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  wordsGlobal = [
    Word(word: "friend", subWords: [
      SubWord(definitions: [
        Definition(
            heading: "As a Noun", subdefinitions: ["Someone you love :)"])
      ], videoLinks: [
        "https://media.auslan.org.au/auslan/46/46930.mp4"
      ], regions: [
        Region.EVERYWHERE
      ], keywords: [])
    ])
  ];

  SharedPreferences.setMockInitialValues({});
  sharedPreferences = await SharedPreferences.getInstance();

  enableFlashcardsKnob = true;
  downloadWordsDataKnob = false;

  showFlashcards = true;

  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(MyApp());
    print("Pump successful!");
  });
}
