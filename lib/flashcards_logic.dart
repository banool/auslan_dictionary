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

DolphinInformation getRandomDolphin(
    Map<String, List<SubWord>> subWords, List<Master> masters) {
  Map<String, SubWord> keyToSubWordMap = Map();
  for (MapEntry<String, List<SubWord>> e in subWords.entries) {
    String word = e.key;
    for (SubWord sw in e.value) {
      keyToSubWordMap[sw.getKey(word)] = sw;
    }
  }
  DolphinSR dolphin = DolphinSR();
  dolphin.addMasters(masters);
  dolphin.addReviews([]);
  return DolphinInformation(dolphin: dolphin, keyToSubWordMap: keyToSubWordMap);
}
