import 'package:dictionarylib_test_support/multi_device/upgrade_sync_from_old_install_suite.dart';

import '../test_config.dart';
import 'md_config.dart';

void main() => runUpgradeSyncFromOldInstall(
  mdSuiteConfig,
  storedVideos: appTestConfig.storedVideos,
);
