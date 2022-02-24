import 'package:dolphinsr_dart/dolphinsr_dart.dart';

import 'types.dart';

const String VIDEO_LINK_SEPARATOR = "======";

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
List<Master> getMasters(Map<String, List<SubWord>> subWords) {
  List<Master> masters = [];
  for (MapEntry<String, List<SubWord>> e in subWords.entries) {
    String word = e.key;
    for (SubWord sw in e.value) {
      var m = Master(id: sw.getKey(word), fields: [
        word,
        sw.videoLinks.join(VIDEO_LINK_SEPARATOR)
      ], combinations: [
        Combination(front: [0], back: [1]),
        Combination(front: [1], back: [0]),
      ]);
      masters.add(m);
    }
  }
  return masters;
}

DolphinSR getRandomDolphin(List<Master> masters) {
  DolphinSR dolphin = DolphinSR();
  dolphin.addMasters(masters);
  dolphin.addReviews([]);
  return dolphin;
}
