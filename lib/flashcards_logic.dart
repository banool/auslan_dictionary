import 'package:dolphinsr_dart/dolphinsr_dart.dart';

import 'globals.dart';
import 'types.dart';

const String VIDEO_LINKS_MARKER = "videolinks";
const String KEY_RANDOM_REVIEWS_COUNTER = "mykey_random_reviews_counter";
const String KEY_FIRST_RANDOM_REVIEW = "mykey_first_random_review";

class DolphinInformation {
  DolphinInformation({
    required this.dolphin,
    required this.keyToSubWordMap,
  });

  DolphinSR dolphin;
  Map<String, SubWordWrapper> keyToSubWordMap;
}

class SubWordWrapper {
  SubWord subWord;
  // We need this to know how to build the link to Auslan Signbank.
  int index;

  SubWordWrapper({
    required this.subWord,
    required this.index,
  });
}

Set<Word> getWordsFromLists(List<String> listsToUse) {
  Set<Word> out = {};
  for (String key in listsToUse) {
    out.addAll(wordListManager.wordLists[key]!.words);
  }
  return out;
}

Map<String, List<SubWordWrapper>> getSubWordsFromWords(Set<Word> favourites) {
  Map<String, List<SubWordWrapper>> subWords = Map();
  for (Word w in favourites) {
    int i = 0;
    subWords[w.word] = [];
    for (SubWord sw in w.subWords) {
      subWords[w.word]!.add(SubWordWrapper(subWord: sw, index: i));
      i += 1;
    }
  }
  return subWords;
}

int getNumSubWords(Map<String, List<SubWord>> subWords) {
  if (subWords.values.length == 0) {
    return 0;
  }
  if (subWords.values.length == 1) {
    return subWords.values.toList()[0].length;
  }
  return subWords.values.map((v) => v.length).reduce((a, b) => a + b);
}

Map<String, List<SubWordWrapper>> filterSubWords(
    Map<String, List<SubWordWrapper>> subWords,
    List<Region> allowedRegions,
    bool useUnknownRegionSigns,
    bool oneCardPerWord) {
  Map<String, List<SubWordWrapper>> out = Map();

  for (MapEntry<String, List<SubWordWrapper>> e in subWords.entries) {
    List<SubWordWrapper> validSubWords = [];
    for (SubWordWrapper sww in e.value) {
      if (validSubWords.length > 0 && oneCardPerWord) {
        break;
      }
      if (sww.subWord.regions.contains(Region.EVERYWHERE)) {
        validSubWords.add(sww);
        continue;
      }
      if (sww.subWord.regions.length == 0 && useUnknownRegionSigns) {
        validSubWords.add(sww);
        continue;
      }
      for (Region r in sww.subWord.regions) {
        if (allowedRegions.contains(r)) {
          validSubWords.add(sww);
          break;
        }
      }
    }
    if (validSubWords.length > 0) {
      out[e.key] = validSubWords;
    }
  }
  return out;
}

// You should provide this function the filtered list of SubWords.
List<Master> getMasters(Map<String, List<SubWordWrapper>> subWords,
    bool wordToSign, bool signToWord) {
  print("Making masters from ${subWords.length} words");
  List<Master> masters = [];
  Set<String> keys = {};
  for (MapEntry<String, List<SubWordWrapper>> e in subWords.entries) {
    String word = e.key;
    for (SubWordWrapper sww in e.value) {
      List<Combination> combinations = [];
      if (wordToSign) {
        combinations.add(Combination(front: [0], back: [1]));
      }
      if (signToWord) {
        combinations.add(Combination(front: [1], back: [0]));
      }
      var key = sww.subWord.getKey(word);
      var m = Master(
        id: key,
        fields: [word, VIDEO_LINKS_MARKER],
        combinations: combinations,
      );
      if (!keys.contains(key)) {
        masters.add(m);
      } else {
        print("Skipping master $m with duplicate key: $key");
      }
      keys.add(key);
    }
  }
  masters.shuffle();
  print("Built ${masters.length} masters");
  return masters;
}

int getNumCards(DolphinSR dolphin) {
  return dolphin.cardsLength();
}

DolphinInformation getDolphinInformation(
    Map<String, List<SubWordWrapper>> subWords, List<Master> masters,
    {List<Review>? reviews}) {
  reviews = reviews ?? [];
  Map<String, SubWordWrapper> keyToSubWordMap = Map();
  for (MapEntry<String, List<SubWordWrapper>> e in subWords.entries) {
    String word = e.key;
    for (SubWordWrapper sww in e.value) {
      keyToSubWordMap[sww.subWord.getKey(word)] = sww;
    }
  }
  DolphinSR dolphin = DolphinSR();
  dolphin.addMasters(masters);

  // For each master + combination in random order, seed a review with an
  // increasing timestamp near the epoch with Rating.Again. This way, ignoring
  // the effect of other reviews added after, the masters will come out in a
  // random order. I use MapEntry just because of the absence of a pair / tuple
  // type.
  List<MapEntry<String, Combination>> mastersEntries = [];
  for (Master m in masters) {
    for (Combination c in m.combinations!) {
      mastersEntries.add(MapEntry(m.id!, c));
    }
  }
  mastersEntries.shuffle();
  List<Review> seedReviews = [];
  int epoch = 1000000;
  for (MapEntry<String, Combination> e in mastersEntries) {
    seedReviews.add(Review(
        master: e.key,
        combination: e.value,
        ts: DateTime.fromMillisecondsSinceEpoch(epoch),
        rating: Rating.Again));
    epoch += 100000000;
  }
  dolphin.addReviews(seedReviews);

  // Dolphin cannot handle reviews for masters it doesn't know about, so we
  // filter those out. This can happen if you have reviews for a card but then
  // choose to filter it out / remove it from your favourites. Be careful not
  // to somehow retrieve the reviews from within the DolphinSR object and store
  // them, since you'd be wiping reviews that are valid if not for the masters
  // we ended up adding to this particular DolphinSR object.
  Map<String, Master> masterLookup = Map.fromEntries(masters.map(
    (e) => MapEntry(e.id!, e),
  ));
  List<Review> filteredReviews = [];
  for (Review r in reviews) {
    Master? m = masterLookup[r.master!];
    if (m == null) {
      print(
          "Filtered out review for ${r.master!} because the master wasn't present");
      continue;
    }
    if (!m.combinations!.contains(r.combination!)) {
      print(
          "Filtered out review for ${r.master!} because the master was present but not with the needed combination");
      continue;
    }
    filteredReviews.add(r);
  }
  print(
      "Added ${filteredReviews.length} total reviews to Dolphin (excluding seed reviews)");
  dolphin.addReviews(filteredReviews);
  return DolphinInformation(dolphin: dolphin, keyToSubWordMap: keyToSubWordMap);
}

const String KEY_STORED_REVIEWS = "stored_reviews";
const String REVIEW_DELIMITER = "===";
const String COMBINATION_DELIMETER = "@@@";

String encodeReview(Review review) {
  String combination =
      "${review.combination!.front![0]}$COMBINATION_DELIMETER${review.combination!.back![0]}";
  return "${review.master}$REVIEW_DELIMITER$combination$REVIEW_DELIMITER${review.rating!.index}$REVIEW_DELIMITER${review.ts!.microsecondsSinceEpoch}";
}

Review decodeReview(String s) {
  List<String> split = s.split(REVIEW_DELIMITER);
  List<String> combinationSplit = split[1].split(COMBINATION_DELIMETER);
  int front = int.parse(combinationSplit[0]);
  int back = int.parse(combinationSplit[1]);
  Combination combination = Combination(front: [front], back: [back]);
  Rating rating = Rating.values[int.parse(split[2])];
  DateTime ts = DateTime.fromMicrosecondsSinceEpoch(int.parse(split[3]));
  return Review(
    master: split[0],
    combination: combination,
    rating: rating,
    ts: ts,
  );
}

List<Review> readReviews() {
  List<String> encoded =
      sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? [];
  return encoded
      .map(
        (e) => decodeReview(e),
      )
      .toList();
}

Future<void> writeReviews(List<Review> existing, List<Review> additional,
    {bool force = false}) async {
  if (!force && additional.isEmpty) {
    print("No reviews to write and force = $force");
    return;
  }
  List<Review> toWrite = existing + additional;
  List<String> encoded = toWrite
      .map(
        (e) => encodeReview(e),
      )
      .toList();
  await sharedPreferences.setStringList(KEY_STORED_REVIEWS, encoded);
  print(
      "Wrote ${additional.length} new reviews (making ${toWrite.length} in total) to storage");
}

int getNumDueCards(DolphinSR dolphin, RevisionStrategy revisionStrategy) {
  switch (revisionStrategy) {
    case RevisionStrategy.Random:
      return getNumCards(dolphin);
    case RevisionStrategy.SpacedRepetition:
      SummaryStatics summary = dolphin.summary();
      // Everything but "later", that seems to match up with what Dolphin
      // will spit out from nextCard. Note, this is only true if the user
      // gets all the cards correct. If the user gets them wrong, those cards
      // will immediately reappear in nextCard. Currently I just make it that
      // you have to re-enter the review flow once it's all done.
      int due =
          (summary.due ?? 0) + (summary.overdue ?? 0) + (summary.learning ?? 0);
      return due;
  }
}

Future<void> bumpRandomReviewCounter(int bumpAmount) async {
  int current = sharedPreferences.getInt(KEY_RANDOM_REVIEWS_COUNTER) ?? 0;
  int updated = current + bumpAmount;
  await sharedPreferences.setInt(KEY_RANDOM_REVIEWS_COUNTER, updated);
  print(
      "Incremented random review counter by $bumpAmount ($current to $updated)");
  int? firstUnixtime = sharedPreferences.getInt(KEY_FIRST_RANDOM_REVIEW);
  if (firstUnixtime == null) {
    await sharedPreferences.setInt(
        KEY_FIRST_RANDOM_REVIEW, DateTime.now().millisecondsSinceEpoch ~/ 1000);
  }
}
