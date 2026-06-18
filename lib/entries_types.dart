import 'package:dictionarylib/entry_types.dart';
import 'package:flutter/material.dart';

class MyEntry implements Entry {
  String entryInEnglish;
  List<MySubEntry> subEntries;
  List<String> categories;
  EntryType entryType;

  MyEntry(
      {required this.entryInEnglish,
      required this.subEntries,
      required this.categories,
      required this.entryType});

  // This should be an entry in the list under "data".
  static MyEntry fromJson(Map<String, dynamic> data) {
    if (data["entry_type"] != "WORD") {
      throw FormatException("Unexpected entry type ${data["entry_type"]}");
    }

    final entryInEnglish = data["entry_in_english"] as String;

    List<MySubEntry> subEntriesList = [];
    // Necessary to know how to build the link to Auslan Signbank.
    int index = 0;
    for (final subJson in (data["sub_entries"] as List<dynamic>? ?? const [])) {
      MySubEntry subEntry =
          MySubEntry.fromJson(subJson as Map<String, dynamic>, index);
      if (subEntry.getMedia().isNotEmpty) {
        subEntry.keywords.remove(entryInEnglish);
        subEntriesList.add(subEntry);
      }
      index += 1;
    }

    return MyEntry(
        entryInEnglish: entryInEnglish,
        subEntries: subEntriesList,
        categories: (data["categories"] as List<dynamic>).cast<String>(),
        entryType: EntryType.WORD);
  }

  @override
  int compareTo(Entry other) {
    return getKey().compareTo(other.getKey());
  }

  @override
  String toString() {
    return entryInEnglish;
  }

  @override
  String getKey() {
    return entryInEnglish;
  }

  @override
  String? getPhrase(Locale locale) {
    return entryInEnglish;
  }

  @override
  List<SubEntry> getSubEntries() {
    return subEntries;
  }

  @override
  EntryType getEntryType() {
    return EntryType.WORD;
  }

  @override
  List<String> getCategories() {
    return categories;
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

  MySubEntry.fromJson(Map<String, dynamic> wordJson, this.index) {
    keywords = (wordJson["keywords"] as List<dynamic>).cast<String>();

    // data-v2.json stores each media item as a path (the part after the
    // serving base, e.g. /mp4video/11/11450.mp4) rather than a full URL,
    // so a saved video survives the content moving between hosts. The
    // playable URL is rebuilt on demand via mediaUrlForPath (globals.dart)
    // + mediaBaseUrls. An old build still reading the full-URL data.json
    // keeps working: mediaUrlForPath passes an absolute URL through
    // unchanged.
    videoLinksInner = (wordJson["video_links"] as List<dynamic>).cast<String>();

    List<Definition> definitions = [];
    (wordJson["definitions"] as Map<String, dynamic>).forEach((heading, value) {
      List<String>? subdefinitions = (value as List<dynamic>).cast<String>();
      definitions
          .add(Definition(heading: heading, subdefinitions: subdefinitions));
    });
    this.definitions = definitions;

    List<Region> regions;
    try {
      // Expected new data format with ints for Regions.
      List<int> regionInts = (wordJson["regions"] as List<dynamic>).cast<int>();
      regions = regionInts.map((i) => Region.values[i]).toList();
    } catch (e) {
      List<String> regionStrings =
          (wordJson["regions"] as List<dynamic>).cast<String>();
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
    final videoLinks = List<String>.from(videoLinksInner);
    videoLinks.sort();
    String firstVideoLink;
    try {
      firstVideoLink = videoLinks[0].split("/auslan/")[1];
    } catch (_) {
      try {
        firstVideoLink = videoLinks[0].split("/mp4video/")[1];
      } catch (_) {
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
    // Returns media paths (the stable identity). Resolve to a playable
    // URL with mediaUrlForPath (globals.dart) — see fromJson above.
    return videoLinksInner;
  }

  @override
  List<MediaItem> getMediaItems() {
    // Auslan has no per-video versioning, so items carry no status — the word
    // page shows no status pill.
    return videoLinksInner.map((p) => MediaItem(path: p)).toList();
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
      throw ArgumentError("Unexpected legacy region string $s");
  }
}
