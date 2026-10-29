import 'package:dictionarylib_test_support/multi_device/account_sync_suites.dart';

import '../test_config.dart';
import 'md_config.dart';

void main() => runSoloOfflineOnline(
  mdSuiteConfig,
  navigateToEntryPage: appTestConfig.navigateToEntryPage,
);
