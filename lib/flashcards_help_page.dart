import 'package:flutter/material.dart';

import 'help_page_common.dart';
import 'flashcards_landing_page.dart';

Widget getFlashcardsHelpPage() {
  return HelpPage(title: "Revision FAQ", items: {
    "What do the flashcard types mean?": [
      "There are two types of flashcards you can choose to revise. You must select at least one.",
      "Sign -> Word: We show you someone performing a sign and you must recall what word that sign represents.",
      "Word -> Sign: We show you a word and you must recall a sign for that word."
    ],
    "How do I navigate through each flashcard?": [
      "Once you have hit \"Start\" you'll be presented with a flashcard "
          "showing you a sign / word and a question like \"What sign "
          "is this?\". Take a moment to think about it and when you're ready, "
          "tap on the screen to reveal the answer. From there you can select "
          "whether you remembered the answer correctly or not.",
      "You can also just tap again anywhere if you got the answer right, as "
          "we select that option by default.",
    ],
    "Where do the words for the flashcards come from?": [
      "You may select one or more lists as the flashcard source. By default "
          "there is only one list, your favourites, but you may create additional "
          "lists and use words from many of them at once in a single revision session. ",
      "If two lists contain the same word, we will still only show the word once."
    ],
    "What do all these sign selection options mean?": [
      "Within a single dictionary entry in Auslan Dictionary there may be "
          "multiple \"sub-entries\", for example showing signs from different regions. "
          "By default we automatically opt you in to signs that are known to be "
          "used throughout the whole country, but you may also opt in to seeing "
          "signs from specific regions (e.g. Northern, VIC, WA, etc). ",
      "Many signs in the signbank don't have regional information attached. "
          "For those you may enable \"$UNKNOWN_REGIONS_TEXT\". I would "
          "generally recommend leaving this enabled, but we provide this option "
          "based on whatever works best for you."
    ],
    "What does \"$ONLY_ONE_CARD_TEXT\" mean?": [
      "Based on the other filtering options you have set, there may be "
          "situations where there are multiple sub-entries for a single entry. "
          "In other words, for a single word you might have a sub-entry from "
          "VIC, another from WA, and another that applies Australia-wide.",
      "You may not want this behaviour, instead preferring to see only one "
          "set of cards per word. If so, you should enable this option."
    ],
    "What is a revision strategy?": [
      "A revision strategy determines how we decide what flashcards to show "
          "you and what information we store about your progress.",
    ],
    "How does the random revision strategy work?": [
      "The random revision strategy is the simplest option. We simply take "
          "the cards you have selected, shuffle them up, and show them to you. "
          "The cards we show you are not influenced by any previous revision "
          "session, nor do we store any progress information as a result of the "
          "revision session. Think of it as bonus, untracked revision.",
    ],
    "How does the spaced repetition revision strategy work?": [
      "This strategy follows a Spaced Reptition Learning approach to revision. "
          "Imagine a set of buckets. When a card is first added, it is put in the "
          "first bucket. If you successfully recall what that card is, we move it "
          "into the second bucket. If you get it right again, we move it into the "
          "third bucket. Conversely, if you forget a card, we move it back a bucket.",
      "When a card is in the earlier buckets, we show it to you more frequently "
          "to help you learn. As you become more confident with a card and it "
          "moves into higher buckets, we show you the card less and less "
          "frequently.",
      "When you select this option, we figure out which cards are "
          "due at that particular time. You may not see every card in every "
          "review session, as some cards might not be due until a later date.",
      "Spaced Repetition Learning is most effective if you check in often, "
          "ideally every day (otherwise the cards can tend to pile up). Fortunately, "
          "if a single session seems overwhelming because there are so many "
          "cards to review, you can exit early and we will save your progress "
          "so far, leaving you fewer cards to review next time."
    ],
  });
}
