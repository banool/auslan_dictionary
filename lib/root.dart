import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/root_app.dart';
import 'package:flutter/material.dart';

import 'common.dart';
import 'entries_types.dart';
import 'flashcards_landing_page.dart';
import 'legal_information.dart';
import 'word_page.dart';

/// Short plain-text preview of an entry's first definition, for the
/// "sign of the day" card on the search screen.
String? auslanDefinitionPreview(Entry entry) {
  if (entry is! MyEntry) return null;
  if (entry.subEntries.isEmpty) return null;
  final defs = entry.subEntries.first.definitions;
  if (defs.isEmpty) return null;
  final subdefs = defs.first.subdefinitions;
  if (subdefs == null || subdefs.isEmpty) return null;
  return subdefs.first;
}

/// Everything app-specific the shared root app needs. The route table, share
/// deep-link handling, engine-event snackbars, and theme plumbing all live in
/// dictionarylib's DictRootApp.
final DictRootAppConfig appRootConfig = DictRootAppConfig(
  appName: APP_NAME,
  classicSeed: MAIN_COLOR,
  wordPageConfig: auslanWordPageConfig,
  navigateToEntryPage: navigateToEntryPage,
  includeEntryTypeButton: false,
  entryDefinitionPreview: auslanDefinitionPreview,
  buildFlashcardsLandingPageController: () =>
      MyFlashcardsLandingPageController(),
  buildLegalInformationChildren: buildLegalInformationChildren,
  reportDataProblemUrl: 'https://www.auslan.org.au/feedback/',
  reportAppProblemUrl: 'https://github.com/banool/auslan_dictionary/issues',
  privacyPolicyUrl: 'https://auslandictionary.org/privacy',
  termsOfServiceUrl: 'https://auslandictionary.org/terms',
  iOSAppId: IOS_APP_ID,
  androidAppId: ANDROID_APP_ID,
);

/// Thin wrapper over the shared DictRootApp so main.dart and the integration
/// tests keep a stable app-local entrypoint (and so the app can diverge from
/// the shared scaffold later by growing this widget).
class RootApp extends StatelessWidget {
  const RootApp({super.key, required this.startingLocale});

  final Locale startingLocale;

  @override
  Widget build(BuildContext context) =>
      DictRootApp(startingLocale: startingLocale, config: appRootConfig);
}
