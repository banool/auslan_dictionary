import 'package:dictionarylib_test_support/config.dart';

import 'package:auslan_dictionary/entries_loader.dart';
import 'package:auslan_dictionary/main.dart'
    show AUSLAN_MEDIA_BASE_URL, KNOBS_URL_BASE;
import 'package:auslan_dictionary/root.dart';

/// Auslan's plug-in points for the shared multi-device sharing suite.
final MdSuiteConfig mdSuiteConfig = MdSuiteConfig(
  appId: 'auslan',
  appName: 'Auslan Dictionary',
  advisoriesUrl: Uri.parse(
      'https://raw.githubusercontent.com/banool/auslan_dictionary/master/assets/advisories.md'),
  knobUrlBase: KNOBS_URL_BASE,
  mediaBaseUrls: const [AUSLAN_MEDIA_BASE_URL],
  buildEntryLoader: () => MyEntryLoader(),
  shareLinkBaseUrl: 'https://share.auslandictionary.org/l',
  shareLinkHost: 'share.auslandictionary.org',
  urlScheme: 'auslan',
  appleBundleId: 'com.banool.auslanDictionary',
  buildApp: (locale) => RootApp(startingLocale: locale),
);
