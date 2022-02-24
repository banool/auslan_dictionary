import 'package:auslan_dictionary/types.dart';
import 'package:dolphinsr_dart/dolphinsr_dart.dart';
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

  testWidgets('Pump app test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(MyApp());
    print("Pump successful!");
  });

  test('Dolphin test', () async {
    DolphinSR dolphin = DolphinSR();

    List<Master> masters = [];
    for (Word w in wordsGlobal) {
      for (SubWord sw in w.subWords) {
        var m = Master(id: sw.getKey(w.word), fields: [
          w.word,
          sw.videoLinks.join("=====")
        ], combinations: [
          Combination(front: [0], back: [1]),
          Combination(front: [1], back: [0]),
        ]);
        masters.add(m);
      }
    }

    dolphin.addMasters(masters);

    DRCard card = dolphin.nextCard()!;

    print(card);
  });
}
