import 'package:flutter/material.dart';

import 'help_page_common.dart';

Widget getWordListHelpPage() {
  return HelpPage(title: "List FAQ", items: {
    "How do I add words to a list?": [
      "In the app bar in the top right corner, there is a pencil icon. "
          "Tap this to enter edit mode. Once in edit mode, you can use the search "
          "bar to search for words that you would like to add to the list. Press "
          "the green button to the right of each item to add it your list.",
      "The green plus button in the bottom right is just a convenience "
          "that opens the keyboard up for you.",
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
      "When you tap this, it adds the word to your Favourites. This is a convenience "
          "for the Favourites list only. ",
      "To add a word to any other list, you must add "
          "it from the page for that list directly. See \"How do I add words to a list?\"",
    ],
    "What does the sort button in the bottom right do?": [
      "This button toggles between two different sort orders. By default, we show "
          "items in the order you added them to the list. If you press this button, "
          "we instead show the items in alphabetical order. Each time you press the "
          "button the sort order will switch between these two options."
    ],
    "Why can't I see the star icon on a word page?": [
      "Originally, when you visited a word page from a list other than your favourites, "
          "we showed the star icon. How it actually worked was it would add the word to "
          "your Favourites no matter what, but some users expected it to add the word "
          "to the list they just came from. To avoid this confusing situation, we just "
          "do not show that button when visiting a word from a list (unless that list "
          "is your Favourites)."
    ],
  });
}
