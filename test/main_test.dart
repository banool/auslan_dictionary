import 'package:auslan_dictionary/entries_types.dart';
import 'package:auslan_dictionary/root.dart';
import 'package:dictionarylib/dictionarylib.dart';
import 'package:dolphinsr_dart/dolphinsr_dart.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  entriesGlobal = {
    MyEntry(
        entryInEnglish: "friend",
        subEntries: [
          MySubEntry(index: 0, definitions: [
            Definition(
                heading: "As a Noun", subdefinitions: ["Someone you love :)"])
          ], videoLinksInner: [
            "auslan/46/46930.mp4"
          ], regions: [
            Region.EVERYWHERE
          ], keywords: [])
        ],
        categories: [],
        entryType: EntryType.WORD)
  };

  SharedPreferences.setMockInitialValues({});
  sharedPreferences = await SharedPreferences.getInstance();

  enableFlashcardsKnob = true;

  showFlashcards = true;

  testWidgets('Pump app test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(RootApp(startingLocale: LOCALE_ENGLISH));
    print("Pump successful!");
  });

  test('Dolphin test', () async {
    DolphinSR dolphin = DolphinSR();

    List<Master> masters = [];
    for (Entry w in entriesGlobal) {
      var ww = w as MyEntry;
      for (MySubEntry sw in ww.subEntries) {
        var m = Master(id: sw.getKey(ww), fields: [
          ww.entryInEnglish,
          sw.videoLinks.join("=====")
        ], combinations: const [
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
