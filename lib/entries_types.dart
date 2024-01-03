import 'package:dictionarylib/entry_types.dart';
import 'package:flutter/material.dart';

const String BASE_URL = "https://media.auslan.org.au";

class MyEntry implements Entry {
  late String word;
  late List<MySubEntry> subEntries;

  MyEntry({required this.word, required this.subEntries});

  MyEntry.fromJson(this.word, dynamic wordJson) {
    List<MySubEntry> subEntries = [];
    // Necessary to know how to build the link to Auslan Signbank.
    int index = 0;
    wordJson.forEach((subJson) {
      MySubEntry subEntry = MySubEntry.fromJson(subJson, index);
      if (subEntry.videoLinks.isNotEmpty) {
        subEntry.keywords.remove(word);
        subEntries.add(subEntry);
      }
      index += 1;
    });

    this.subEntries = subEntries;
  }

  @override
  int compareTo(Entry other) {
    return getKey().compareTo(other.getKey());
  }

  @override
  String toString() {
    return word;
  }

  @override
  String getKey() {
    return word;
  }

  @override
  String? getPhrase(Locale locale) {
    return word;
  }

  @override
  List<SubEntry> getSubEntries() {
    return subEntries;
  }

  @override
  EntryType getEntryType() {
    return EntryType.WORD;
  }
}

class MySubEntry implements SubEntry {
  late List<String> keywords;
  late List<String> videoLinksInner;
  late List<Definition> definitions;
  late List<Region> regions;
  // We need this to know how to build the link to Auslan Signbank.
  late int index;

  MySubEntry(
      {required this.keywords,
      required this.videoLinksInner,
      required this.definitions,
      required this.regions,
      required this.index});

  List<String> get videoLinks {
    List<String> out = [];
    // See below for an explanation of why we do this.
    for (var link in videoLinksInner) {
      String l;
      if (link.startsWith("http")) {
        l = link;
      } else {
        // TODO: I don't think this branch is necessary anymore, all links in
        // the JSON have a full URL now.
        l = "$BASE_URL/$link";
      }
      out.add(l);
    }
    return out;
  }

  MySubEntry.fromJson(dynamic wordJson, this.index) {
    keywords = wordJson["keywords"].cast<String>();

    // In the past we made the assumption that all the videos came from the same
    // URL. Accordingly the scraper trimmed the host part of the URL and just
    // kept the path. This is no longer true, so the scraper now stores the full
    // URL in the data file. The code previously assumed the URLs were only the
    // paths but it no longer does this by default, it just uses the full URL.
    // If the scheme + host is missing though, we prepend it like we did before.
    // This might happen if the user has updated their app but is somehow still
    // sitting on old data. We can remove this behavior eventually.
    videoLinksInner = wordJson["video_links"].cast<String>();

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

  // This is for DolphinSR. The video attached to a subword is the best we have
  // to globally identify it. If the video changes for a subword, the subword
  // itself has effectively changed for review purposes and it'd make sense to
  // consider it a new master anyway. In addition to the video we accept the
  // Entry that this SubEntry comes from; we need the key from _that_ to
  // uniquely identify the subentry (some subentries from different entries
  // might use the same video).
  @override
  String getKey(Entry parentEntry) {
    var videoLinks = List.from(videoLinksInner);
    videoLinks.sort();
    String firstVideoLink;
    try {
      firstVideoLink = videoLinks[0].split("/auslan/")[1];
    } catch (_e) {
      try {
        firstVideoLink = videoLinks[0].split("/mp4video/")[1];
      } catch (_e) {
        firstVideoLink = videoLinks[0];
      }
    }
    return "${parentEntry.getKey()}-$firstVideoLink";
  }

  @override
  String toString() {
    return "SubWord($videoLinksInner)";
  }

  String getRegionsString() {
    if (regions.isEmpty) {
      return "Regional information unknown";
    }
    if (regions.contains(Region.EVERYWHERE)) {
      return Region.EVERYWHERE.pretty;
    }
    return regions.map((r) => r.pretty).join(", ");
  }

  @override
  List<String> getMedia() {
    // The dump only contains the final filename + ext, we have to build the
    // full URL. We do it here. buildUrl depends on the useCdnUrl knob having
    // a value.
    return videoLinks;
  }

  @override
  List<Definition> getDefinitions(Locale locale) {
    return definitions;
  }

  @override
  List<String> getRelatedWords() {
    return keywords;
  }

  @override
  List<Region> getRegions() {
    return regions;
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
