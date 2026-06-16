import 'package:auslan_dictionary/entries_types.dart';
import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/page_word.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'common.dart';

/// App-bar action linking out to this sign on Auslan Signbank. Also used by the
/// flashcards screen, so it lives here rather than inline in [WordPageConfig].
Widget getAuslanSignbankLaunchAppBarActionWidget(
    BuildContext context, String word, int currentPage,
    {bool enabled = true}) {
  return buildActionButton(
    context,
    const Icon(Icons.public, semanticLabel: "Link to sign in Auslan Signbank"),
    () async {
      var url =
          'http://www.auslan.org.au/dictionary/words/$word-${currentPage + 1}.html';
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    },
    enabled: enabled,
  );
}

/// Auslan's definition layout: a small primary marker + the heading set as an
/// uppercase eyebrow, then the subdefinitions beneath it.
Widget auslanDefinition(BuildContext context, dynamic d) {
  final definition = d as Definition;
  final cs = Theme.of(context).colorScheme;
  return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // A small primary marker + the heading set as an uppercase eyebrow.
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              definition.heading!.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: cs.primary,
              ),
            ),
          ),
        ]),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: definition.subdefinitions!
              .map<Widget>((s) => Padding(
                  padding: const EdgeInsets.only(left: 14.0, top: 8.0),
                  child: Text(s,
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(height: 1.45))))
              .toList(),
        )
      ]));
}

/// Auslan's wiring for the shared [EntryPage]: English-only related-word
/// lookup, the region string from [MySubEntry], a 16:9 video, and the Signbank
/// link in the app bar (Auslan has no language switcher).
final WordPageConfig auslanWordPageConfig = WordPageConfig(
  getRelatedEntry: (keyword) => keyedByEnglishEntriesGlobal[keyword],
  navigateToEntryPage: navigateToEntryPage,
  buildDefinition: auslanDefinition,
  regionsString: (context, subEntry) =>
      (subEntry as MySubEntry).getRegionsString(),
  videoAspectRatio: 16 / 9,
  buildExtraAppBarActions: (context, ctx) => [
    getAuslanSignbankLaunchAppBarActionWidget(
        context, ctx.entry.getPhrase(LOCALE_ENGLISH)!, ctx.currentVariation),
  ],
);
