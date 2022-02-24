class Word implements Comparable<Word> {
  Word({required this.word, required this.subWords});

  late String word;
  late List<SubWord> subWords;

  Word.fromJson(String word, dynamic wordJson) {
    this.word = word;

    List<SubWord> subWords = [];
    wordJson.forEach((subJson) {
      SubWord subWord = SubWord.fromJson(subJson);
      subWord.keywords.remove(word);
      subWords.add(subWord);
    });

    this.subWords = subWords;
  }

  @override
  int compareTo(Word other) {
    return this.word.compareTo(other.word);
  }

  @override
  String toString() {
    return this.word;
  }
}

class SubWord {
  SubWord(
      {required this.keywords,
      required this.videoLinks,
      required this.definitions,
      required this.regions});

  late List<String> keywords;
  late List<String> videoLinks;
  late List<Definition> definitions;
  late List<Region> regions;

  SubWord.fromJson(dynamic wordJson) {
    this.keywords = wordJson["keywords"].cast<String>();

    this.videoLinks = wordJson["video_links"].cast<String>();

    List<Definition> definitions = [];
    wordJson["definitions"].forEach((heading, value) {
      List<String>? subdefinitions = value.cast<String>();
      definitions
          .add(Definition(heading: heading, subdefinitions: subdefinitions));
    });
    this.definitions = definitions;

    List<Region> regions;
    try {
      // Expected new data format with ints for Regions.
      List<int> regionInts = wordJson["regions"].cast<int>();
      regions = regionInts.map((i) => Region.values[i]).toList();
    } catch (e) {
      List<String> regionStrings = wordJson["regions"].cast<String>();
      regions = regionStrings.map((v) => regionFromLegacyString(v)).toList();
    }

    this.regions = regions;
  }

  String getRegionsString() {
    if (this.regions.length == 0) {
      return "Regional information unknown";
    }
    if (this.regions.contains(Region.EVERYWHERE)) {
      return Region.EVERYWHERE.pretty;
    }
    return this.regions.map((r) => r.pretty).join(", ");
  }

  // This is for DolphinSR. The video attached to a subword is the best we have
  // to globally identify it. If the video changes for a subword, the subword
  // itself has effectively changed for review purposes and it'd make sense to
  // consider it a new master anyway.
  String getKey(String word) {
    var videoLinks = List.from(this.videoLinks);
    videoLinks.sort();
    print(videoLinks);
    String firstVideoLink;
    try {
      firstVideoLink = videoLinks[0].split("/auslan/")[1];
    } catch (_e) {
      firstVideoLink = videoLinks[0].split("/mp4video/")[1];
    }
    return "$word-$firstVideoLink";
  }
}

class Definition {
  Definition({this.heading, this.subdefinitions});

  final String? heading;
  final List<String>? subdefinitions;
}

// IMPORTANT:
// Keep this in sync with Region in scripts/scrape_signbank.py, the order is important.
enum Region {
  EVERYWHERE,
  SOUTHERN,
  NORTHERN,
  WA,
  NT,
  SA,
  QLD,
  NSW,
  ACT,
  VIC,
  TAS,
}

extension PrintRegion on Region {
  String get pretty {
    switch (this) {
      case Region.EVERYWHERE:
        return "All states of Australia";
      case Region.SOUTHERN:
        return "Southern";
      case Region.NORTHERN:
        return "Northern";
      case Region.WA:
        return "WA";
      case Region.NT:
        return "NT";
      case Region.SA:
        return "SA";
      case Region.QLD:
        return "QLD";
      case Region.NSW:
        return "NSW";
      case Region.ACT:
        return "ACT";
      case Region.VIC:
        return "VIC";
      case Region.TAS:
        return "TAS";
    }
  }
}

final List<Region> regionsWithoutEverywhere =
    List.from(Region.values.where((r) => r != Region.EVERYWHERE).toList());

Region regionFromLegacyString(String s) {
  switch (s.toLowerCase()) {
    case "everywhere":
      return Region.EVERYWHERE;
    case "southern":
      return Region.SOUTHERN;
    case "northern":
      return Region.NORTHERN;
    case "wa":
      return Region.WA;
    case "nt":
      return Region.NT;
    case "sa":
      return Region.SA;
    case "qld":
      return Region.QLD;
    case "nsw":
      return Region.NSW;
    case "act":
      return Region.ACT;
    case "vic":
      return Region.VIC;
    case "tas":
      return Region.TAS;
    default:
      throw "Unexpected legacy region string $s";
  }
}

enum RevisionStrategy {
  SpacedRepetition,
  Random,
}

extension PrettyPrint on RevisionStrategy {
  String get pretty {
    switch (this) {
      case RevisionStrategy.SpacedRepetition:
        return "Spaced Repetition";
      case RevisionStrategy.Random:
        return "Random";
    }
  }
}
