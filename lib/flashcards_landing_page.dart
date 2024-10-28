import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/page_flashcards_landing.dart';
import 'package:dictionarylib/revision.dart';
import 'package:dolphinsr_dart/dolphinsr_dart.dart';
import 'package:flutter/material.dart';
import 'package:multi_select_flutter/multi_select_flutter.dart';
import 'package:settings_ui/settings_ui.dart';
import 'package:dictionarylib/dictionarylib.dart' show DictLibLocalizations;

import 'entries_types.dart';
import 'flashcards_help_page.dart';
import 'flashcards_page.dart';

const String UNKNOWN_REGIONS_TEXT = "Signs with unknown region";

class MyFlashcardsLandingPageController
    extends FlashcardsLandingPageController {
  @override
  Widget buildFlashcardsPage(
      {required DolphinInformation dolphinInformation,
      required RevisionStrategy revisionStrategy,
      required List<Review> existingReviews}) {
    return FlashcardsPage(
        di: dolphinInformation,
        revisionStrategy: revisionStrategy,
        existingReviews: existingReviews);
  }

  @override
  Widget buildHelpPage(BuildContext context) {
    return getFlashcardsHelpPage(context);
  }

  @override
  Map<Entry, List<SubEntry>> filterSubEntries(
      Map<Entry, List<SubEntry>> subEntries) {
    List<Region> allowedRegions =
        (sharedPreferences.getStringList(KEY_FLASHCARD_REGIONS) ?? [])
            .map((i) => Region.values[int.parse(i)])
            .toList();
    bool useUnknownRegionSigns =
        sharedPreferences.getBool(KEY_USE_UNKNOWN_REGION_SIGNS) ?? true;
    bool oneCardPerEntry =
        sharedPreferences.getBool(KEY_ONE_CARD_PER_WORD) ?? false;

    Map<Entry, List<SubEntry>> out = {};

    for (MapEntry<Entry, List<SubEntry>> e in subEntries.entries) {
      List<SubEntry> validSubEntries = [];
      for (SubEntry se in e.value) {
        if (validSubEntries.isNotEmpty && oneCardPerEntry) {
          break;
        }
        if (se.getRegions().contains(Region.EVERYWHERE)) {
          validSubEntries.add(se);
          continue;
        }
        if (se.getRegions().isEmpty && useUnknownRegionSigns) {
          validSubEntries.add(se);
          continue;
        }
        for (Region r in se.getRegions()) {
          if (allowedRegions.contains(r)) {
            validSubEntries.add(se);
            break;
          }
        }
      }
      if (validSubEntries.isNotEmpty) {
        out[e.key] = validSubEntries;
      }
    }

    return out;
  }

  @override
  List<SettingsTile> getExtraSettingsTiles(
      BuildContext context,
      void Function(void Function() fn) setState,
      void Function(String key, bool newValue, bool influencesStartValidity)
          onPrefSwitch,
      void Function() updateRevisionSettings) {
    List<int> additionalRegionsValues =
        (sharedPreferences.getStringList(KEY_FLASHCARD_REGIONS) ?? [])
            .map((e) => int.parse(e))
            .toList();

    String regionsString = "All of Australia";

    String additionalRegionsValuesString = additionalRegionsValues
        .map((i) => Region.values[i].pretty)
        .toList()
        .join(", ");

    if (additionalRegionsValuesString.isNotEmpty) {
      regionsString += " + $additionalRegionsValuesString";
    }

    bool useUnknownRegionSigns =
        sharedPreferences.getBool(KEY_USE_UNKNOWN_REGION_SIGNS) ?? true;

    if (useUnknownRegionSigns) {
      regionsString += " + signs with unknown region";
    }
    return [
      SettingsTile.navigation(
        title: getText("Select additional sign regions"),
        trailing: Container(),
        onPressed: (BuildContext context) async {
          await showDialog(
            context: context,
            builder: (ctx) {
              return buildMultiSelectDialog(
                  context: context,
                  title: DictLibLocalizations.of(context)!.flashcardsRegions,
                  items: regionsWithoutEverywhere
                      .map((e) => MultiSelectItem(e.index, e.pretty))
                      .toList(),
                  initialValue: additionalRegionsValues,
                  onConfirm: (values) {
                    setState(() {
                      sharedPreferences.setStringList(KEY_FLASHCARD_REGIONS,
                          values.map((e) => e.toString()).toList());
                      updateRevisionSettings();
                    });
                  });
            },
          );
        },
      ),
      SettingsTile.switchTile(
        title: const Text(
          UNKNOWN_REGIONS_TEXT,
          style: TextStyle(fontSize: 15),
        ),
        initialValue: useUnknownRegionSigns,
        onToggle: (newValue) {
          onPrefSwitch(KEY_USE_UNKNOWN_REGION_SIGNS, newValue, false);
          updateRevisionSettings();
        },
        description: Text(
          regionsString,
          textAlign: TextAlign.center,
        ),
      ),
    ];
  }
}
