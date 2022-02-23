You'll notice there are two files in this directory. Let me explain why.

On 2022-02-21 I made a change to how I represent region information. Previously I would have strings for each region, like "Everywhere", "WA", etc. The change I made was to instead use ints mapping to enum values. Unfortuntely, this change was not compatible with the existing version of the app, it would crash upon reading this new data. So instead of placing the new data at `words.json`, I put it in a new location `words_latest.json`. This makes for a cleaner migration, since only the new version of the app, which can handle the new format (as well as the old one in case, e.g. to handle the old format still stored locally), will read from the new location. So long as versions of the app prior to 2022-02-21 are deployed to user devices, I need to keep `words.json` here. Notably though, I don't intend to update this data, so those users will have increasingly stale data. I'm happy to make this trade off, most users have auto update enabled. `words_latest.json` will continue to be updated by the PR updater cron in `banool/server-setup`.

Actually this assertion that I need to keep `words.json` while users have old versions installed is untrue, I could delete it for the same effect, the app would try to pull the latest data and just fail, but that wouldn't hurt the app at all, since we run that in the background and don't do anything on failure.