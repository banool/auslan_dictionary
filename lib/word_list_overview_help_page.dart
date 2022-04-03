import 'package:flutter/material.dart';

import 'help_page_common.dart';

Widget getWordListOverviewHelpPage() {
  return HelpPage(title: "Lists FAQ", items: {
    "How do I make a new list?": [
      "In the app bar in the top right corner, there is a pencil icon. Tap this to enter edit mode. "
          "Once in edit mode, tap the green plus button. This will allow you to make a new list.",
    ],
    "How do I delete a list?": [
      "In the app bar in the top right corner, there is a pencil icon. Tap this to enter edit mode. "
          "Once in edit mode, tap the red icon to the right of the list you want to delete.",
      "Note that you cannot delete the Favourites list.",
    ],
    "How do I change the order of my lists?": [
      "In the app bar in the top right corner, there is a pencil icon. "
          "First, tap this icon to enter edit mode. "
          "After that, you can drag the lists around to change the order.",
      "Note that you cannot reorder the Favourites list, it will always be first."
    ],
    "How does the Favourites list work?": [
      "The Favourites list is a special list that you cannot delete. When you visit "
          "a word page, there is a star icon that you can use to save words to your "
          "Favourites. The intention here is to make it easy to quickly save a word "
          "that you come across while searching.",
      "To add words to any other list, you must add them from the page for that list. "
          "To see more information about how to do this, open any list (e.g. "
          "Favourites), click the help icon in the top right, and read the information "
          "under \"How do I add words to a list?\"",
    ],
  });
}
