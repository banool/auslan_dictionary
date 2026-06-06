import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/hearth.dart';
import 'package:dictionarylib/page_flashcards_landing.dart';
import 'package:dictionarylib/revision.dart';
import 'package:dolphinsr_dart/dolphinsr_dart.dart';
import 'package:flutter/material.dart';
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

  /// Filter the saved-video pool against the user's region prefs and
  /// the "one card per word" toggle.
  ///
  /// Region filter: applied to the parent sub-entry of each saved
  /// video — a video belonging to a sub-entry tagged Victoria is in
  /// scope iff Victoria is one of the allowed regions (or the "all
  /// of Australia" / "unknown region" branches apply).
  ///
  /// One card per word: when set, dedupe by entry key, keeping the
  /// first saved video the user has for the entry. Insertion order is
  /// preserved.
  @override
  List<ResolvedSavedVideo> filterSavedVideos(
      List<ResolvedSavedVideo> videos) {
    final allowedRegions =
        (sharedPreferences.getStringList(KEY_FLASHCARD_REGIONS) ?? [])
            .map((i) => Region.values[int.parse(i)])
            .toList();
    final useUnknownRegionSigns =
        sharedPreferences.getBool(KEY_USE_UNKNOWN_REGION_SIGNS) ?? true;

    final out = <ResolvedSavedVideo>[];
    for (final r in videos) {
      final sub = r.subEntry as MySubEntry;
      final regions = sub.getRegions();
      bool passesRegion;
      if (regions.contains(Region.EVERYWHERE)) {
        passesRegion = true;
      } else if (regions.isEmpty && useUnknownRegionSigns) {
        passesRegion = true;
      } else {
        passesRegion = regions.any(allowedRegions.contains);
      }
      if (!passesRegion) continue;
      out.add(r);
    }
    return out;
  }

  @override
  List<Widget> getExtraSettingsRows(
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
      HearthRow(
        icon: Icons.public,
        title: DictLibLocalizations.of(context)!.regionSheetTitle,
        subtitle: regionsString,
        onTap: () =>
            _showRegionSheet(context, setState, updateRevisionSettings),
      ),
    ];
  }

  /// The Auslan sign-region configurator: dialect pills (Southern / Northern)
  /// + state/territory pills, plus the "signs with unknown region" toggle.
  /// Operates directly on the [Region] set stored in KEY_FLASHCARD_REGIONS so
  /// the revision filter semantics are unchanged.
  Future<void> _showRegionSheet(
      BuildContext context,
      void Function(void Function() fn) pageSetState,
      void Function() updateRevisionSettings) async {
    const states = [
      Region.NSW,
      Region.VIC,
      Region.QLD,
      Region.SA,
      Region.WA,
      Region.TAS,
      Region.NT,
      Region.ACT,
    ];

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          final cs = Theme.of(ctx).colorScheme;
          final tt = Theme.of(ctx).textTheme;
          final selected =
              (sharedPreferences.getStringList(KEY_FLASHCARD_REGIONS) ?? [])
                  .map(int.parse)
                  .toSet();
          final unknown =
              sharedPreferences.getBool(KEY_USE_UNKNOWN_REGION_SIGNS) ?? true;

          void toggleRegion(Region r) {
            final s =
                (sharedPreferences.getStringList(KEY_FLASHCARD_REGIONS) ?? [])
                    .map(int.parse)
                    .toSet();
            if (!s.add(r.index)) s.remove(r.index);
            sharedPreferences.setStringList(
                KEY_FLASHCARD_REGIONS, s.map((e) => e.toString()).toList());
            updateRevisionSettings();
            pageSetState(() {});
            setSheet(() {});
          }

          Widget pill(Region r) {
            final on = selected.contains(r.index);
            // A toggle chip exposed to screen readers as a selectable button.
            return Semantics(
              button: true,
              selected: on,
              label: r.pretty,
              excludeSemantics: true,
              child: Material(
                color: on ? cs.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  onTap: () => toggleRegion(r),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: on ? cs.primary : cs.outline, width: 1.5),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (on) ...[
                        Icon(Icons.check, size: 14, color: cs.onPrimary),
                        const SizedBox(width: 6),
                      ],
                      Text(r.pretty,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: on ? cs.onPrimary : cs.onSurface)),
                    ]),
                  ),
                ),
              ),
            );
          }

          Widget sectionLabel(String t) => Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 9),
                child: Text(t,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                        color: cs.onSurfaceVariant)),
              );

          return SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(DictLibLocalizations.of(ctx)!.regionSheetTitle,
                        style: tt.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      DictLibLocalizations.of(ctx)!.regionSheetDescription,
                      style: tt.bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
                    ),
                    sectionLabel(
                        DictLibLocalizations.of(ctx)!.regionSheetDialects.toUpperCase()),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      pill(Region.SOUTHERN),
                      pill(Region.NORTHERN),
                    ]),
                    sectionLabel(DictLibLocalizations.of(ctx)!
                        .regionSheetStatesTerritories
                        .toUpperCase()),
                    Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: states.map(pill).toList()),
                    const SizedBox(height: 18),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(children: [
                        Expanded(
                          child: Text(UNKNOWN_REGIONS_TEXT,
                              style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Switch(
                          value: unknown,
                          onChanged: (v) {
                            sharedPreferences.setBool(
                                KEY_USE_UNKNOWN_REGION_SIGNS, v);
                            updateRevisionSettings();
                            pageSetState(() {});
                            setSheet(() {});
                          },
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style:
                            FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                        child: Text(
                            DictLibLocalizations.of(ctx)!.shareLinkDoneButton),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }
}
