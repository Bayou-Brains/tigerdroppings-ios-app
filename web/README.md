# TD Live for desktop (Chrome)

The same condensed dark Tiger Droppings reader as the iPhone app, running in your browser on the real [tigerdroppings.com](https://www.tigerdroppings.com) site. Login, reply, quote, and voting keep working — this only restyles the pages and adds Live mode and resume badges.

> Unofficial fan project. Not affiliated with, authorized, or endorsed by TigerDroppings.com. All forum content belongs to its authors and TigerDroppings.

## What you get
- Black background, white text, tighter spacing, and dividers between posts
- Green and red vote bars on the left and right edges of each post, stronger the more lopsided the votes
- A **Live** toggle on thread pages that polls every 5 seconds and appends new replies in place, like a chat
- A **+N** badge on board lists for threads with new replies since you last viewed them, and a **NEW POSTS BELOW** marker so a thread reopens where you left off

There is no on-device AI thread summary on the desktop version.

## Install with Tampermonkey (easiest)

1. Install [Tampermonkey](https://www.tampermonkey.net/) for Chrome, Edge, Firefox, or Safari.
2. Open this file and Tampermonkey should offer to install it:

   **https://raw.githubusercontent.com/Bayou-Brains/tigerdroppings-ios-app/main/web/tdlive.user.js**

3. Confirm the install. Updates come from that same link automatically.

If the install prompt does not appear, open the Tampermonkey dashboard, choose **Create a new script**, paste the contents of `tdlive.user.js`, and save.

## Install as a Chrome extension (unpacked)

Use this if you would rather not install Tampermonkey.

1. Download this repository (Code → Download ZIP, or `git clone https://github.com/Bayou-Brains/tigerdroppings-ios-app.git`) and unzip it if needed.
2. In Chrome, open `chrome://extensions`.
3. Turn on **Developer mode** (top right).
4. Click **Load unpacked** and select the `web/chrome-extension` folder inside the repo.

Chrome will not auto-update an unpacked extension. To get changes, `git pull` (or re-download) and click **Reload** on the extension card.

## Using it
Open any board or thread on tigerdroppings.com. The dark layout applies immediately. On a thread, click **Go Live** to pin yourself to the newest page and pull new posts every 5 seconds. Your read positions stay in this browser only (localStorage); they are not sent anywhere.

To turn it off, disable the script in Tampermonkey or the extension on `chrome://extensions`.
