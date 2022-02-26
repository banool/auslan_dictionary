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
    e.value.shuffle();
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
  dolphin.addReviews(reviews);
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

void writeReviews(
  List<Review> existing,
  List<Review> additional,
) {
  if (additional.isEmpty) {
    return;
  }
  List<Review> toWrite = existing + additional;
  List<String> encoded = toWrite
      .map(
        (e) => encodeReview(e),
      )
      .toList();
  print("Wrote ${additional.length} new reviews to storage");
  sharedPreferences.setStringList(KEY_STORED_REVIEWS, encoded);
}
