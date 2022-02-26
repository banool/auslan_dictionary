import 'dart:convert';

import 'package:auslan_dictionary/globals.dart';
import 'package:dolphinsr_dart/dolphinsr_dart.dart';

import 'types.dart';

const String VIDEO_LINKS_MARKER = "videolinks";

class DolphinInformation {
  DolphinInformation({
    required this.dolphin,
    required this.keyToSubWordMap,
  });

  DolphinSR dolphin;
  Map<String, SubWord> keyToSubWordMap;
}

Map<String, List<SubWord>> getSubWordsFromWords(List<Word> favourites) {
  Map<String, List<SubWord>> subWords = Map();
  for (Word w in favourites) {
    subWords[w.word] = w.subWords;
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

Map<String, List<SubWord>> filterSubWords(
    Map<String, List<SubWord>> subWords,
    List<Region> allowedRegions,
    bool useUnknownRegionSigns,
    bool oneCardPerWord) {
  Map<String, List<SubWord>> out = Map();

  for (MapEntry<String, List<SubWord>> e in subWords.entries) {
    List<SubWord> validSubWords = [];
    for (SubWord sw in e.value) {
      if (validSubWords.length > 0 && oneCardPerWord) {
        break;
      }
      if (sw.regions.contains(Region.EVERYWHERE)) {
        validSubWords.add(sw);
        continue;
      }
      if (sw.regions.length == 0 && useUnknownRegionSigns) {
        validSubWords.add(sw);
        continue;
      }
      for (Region r in sw.regions) {
        if (allowedRegions.contains(r)) {
          validSubWords.add(sw);
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
List<Master> getMasters(
    Map<String, List<SubWord>> subWords, bool wordToSign, bool signToWord) {
  List<Master> masters = [];
  for (MapEntry<String, List<SubWord>> e in subWords.entries) {
    String word = e.key;
    for (SubWord sw in e.value) {
      List<Combination> combinations = [];
      if (wordToSign) {
        combinations.add(Combination(front: [0], back: [1]));
      }
      if (signToWord) {
        combinations.add(Combination(front: [1], back: [0]));
      }
      var m = Master(
        id: sw.getKey(word),
        fields: [word, VIDEO_LINKS_MARKER],
        combinations: combinations,
      );
      masters.add(m);
    }
  }
  masters.shuffle();
  return masters;
}

int getNumCards(DolphinSR dolphin) {
  return dolphin.cardsLength();
}

DolphinInformation getDolphinInformation(
    Map<String, List<SubWord>> subWords, List<Master> masters,
    {List<Review>? reviews}) {
  reviews = reviews ?? [];
  Map<String, SubWord> keyToSubWordMap = Map();
  for (MapEntry<String, List<SubWord>> e in subWords.entries) {
    String word = e.key;
    for (SubWord sw in e.value) {
      keyToSubWordMap[sw.getKey(word)] = sw;
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
    epoch += 10000000;
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
    print("Added review $r");
  }
  print("Added ${filteredReviews.length} total reviews to Dolphin");
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
