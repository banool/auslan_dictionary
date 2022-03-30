import 'package:auslan_dictionary/help_page_common.dart';
import 'package:flutter/material.dart';

Widget getWordListHelpPage() {
  return HelpPage(title: "List FAQ", items: {
    "How do I add words to a list?": [
      "In the app bar in the top right corner, there is a pencil icon. "
          "Tap this to enter edit mode. Once in edit mode, you can use the search "
          "bar to search for words that you would like to add to the list. Press "
          "the green button to the right of each item to add it your list.",
      "Once you are done, press the pencil icon again to exit edit mode."
    ],
    "How do I remove words from a list?": [
      "In the app bar in the top right corner, there is a pencil icon. "
          "Tap this to enter edit mode. Once in edit mode, you can press the "
          "red icon beside a word to remove it from the list.",
      "Note that if you search for a word, this will show words not currently "
          "in the list so you can add them to the list, it will not show you "
          "words already in the list.",
    ],
    "What does the star icon do on a word page?": [
      "When you tap this, it adds the word to your favourites. This is a convenience "
          "for the favourites list only, to add a word to any other list, you must use "
          "the standard flow from the lists page. See 'How do I add words to a list?'",
    ],
    "What does the sort button in the bottom right do?": [
      "This button toggles between two different sort orders. By default, we show "
          "items in the order you added them to the list. If you press this button, "
          "we instead show the items in alphabetical order. Each time you press the "
          "button the sort order will switch between these options."
    ],
  });
}
