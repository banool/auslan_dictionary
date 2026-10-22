import 'package:dictionarylib_test_support/multi_device/upgrade_shared_favourites_suite.dart';

import '../test_config.dart';
import 'md_config.dart';

void main() => runUpgradeWithSharedFavourites(
  mdSuiteConfig,
  storedVideos: appTestConfig.storedVideos,
);
