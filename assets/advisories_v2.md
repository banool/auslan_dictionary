//// ==========================================================================
//// App advisories (v2)
//// ==========================================================================
////
//// These are the in-app announcements shown on the "News" page. The app fetches
//// this file on startup and, when it finds an advisory it hasn't shown before,
//// opens the News page automatically (once per session, mobile only). The News
//// page itself always lists every advisory that applies to the running version,
//// newest first.
////
//// This is the v2 advisories file, read only by Auslan Dictionary 2.0.0 and
//// newer. Older app versions read the legacy assets/advisories.md instead and
//// never see anything added here — that's how we keep new announcements off old
//// builds without shipping a hotfix. Do NOT add new advisories to the old file;
//// add them here.
////
//// ---- Format ----
////
//// Each advisory is a section between START=== and END===. Inside a section:
////
////   DATE===YYYY-MM-DD     (required)  shown as the eyebrow above the body.
////   MINVERSION===X.Y.Z    (optional)  only show on app versions >= X.Y.Z.
////   MAXVERSION===X.Y.Z    (optional)  only show on app versions <= X.Y.Z.
////
//// Everything else in the section is the body, written in full Markdown. Lines
//// starting with four slashes (like this one) are comments and are ignored. Put
//// new advisories at the BOTTOM — the app counts sections to decide what's new,
//// so order matters.
////
//// MINVERSION / MAXVERSION (both inclusive, both optional) let a single
//// announcement target a slice of versions. Because every app reading THIS file
//// is already 2.0.0+, you only need them to target a NARROWER range — e.g. an
//// advisory only for the 2.1.x line:
////
////   START===
////   DATE===2026-09-01
////   MINVERSION===2.1.0
////   MAXVERSION===2.1.99
////   ## A note for 2.1 users
////   ...
////   END===
////
//// A section with no MINVERSION/MAXVERSION shows on every 2.0.0+ build.
//// ==========================================================================
START===
DATE===2024-01-03
## Happy 2024!!

Believe it or not but as of Jan 1st 2024 there are ~158,000 of you who use this app! That's absolutely incredible, thank you so much for using the app and learning Auslan. Happy New Year!!
END===
START===
DATE===2024-03-04
## Community Lists!

You'll notice on the lists page there are now two tabs, one for your own lists and a new tab for community lists. These predefined lists are defined based on the categories defined on the Auslan Signbank website. This was a much requested feature, enjoy!!

P.S. You might be reading this because the app failed to start. If not, please ignore, but if so, you are on an old version of the app. Please head to the App Store or Play Store and update the app to fix this issue. Apologies, this one slipped through my testing!
END===
START===
DATE===2024-10-28
## Dark mode!

Hey all, long time no see!

We just added support for dark mode to the app! To smooth the transition, all apps default to light mode still, but you can set your preferred colour mode in the settings. If you run into any issues with this, please let me know! Go to `Settings -> Report issue with app (Email)`.

If you like the app, please consider leaving a review! Go to `Settings -> Give feedback on App / Play Store`. I work on this for free (forever) in my spare time. Reminder that I don't control the data the app uses! For issues with that, please use `Settings -> Report issue with dictionary data`.

Cheers,
Daniel
END===
START===
DATE===2026-01-01
## Happy 2026!!

The Auslan Dictionary app is over 5 years old now, thanks for coming along for the ride!! There are now ~372,000 of you who have downloaded this app! 

This update brings a new framework to help a few folks on Android who couldn't load videos, please reach out if you have issues. You can use the "Report issue with app (Email)" option in the settings page.

Thanks all!
END===
START===
DATE===2026-06-13
MINVERSION===2.0.0
## Version 2.0 is here! 🎉

This is a big one. You can now share your lists of signs with friends, family, students or classmates with a single link, and edit them together — your changes sync across everyone's devices. Sign in from the settings page to get started.

Another big change, rather than saving entire entries to lists, you now save specific videos. This should help you curate your lists to the exact signs / regions that you're focusing on.

Then of course the other very obvious big change, the app has a fresh coat of paint! When I first started this 6 years ago I went with the most out-of-the-box, basic visuals available; it's time for something a little bit prettier. If you don't like it, you can switch back to the "Classic" theme in the settings. It's not exactly the same as before but it should feel more familiar.

Thanks so much for using Auslan Dictionary! As always the app is free, no ads, and will stay that way forever. If you run into any issues, please use `Settings -> Report issue with app (Email)`.

Happy learning!
Daniel
END===
