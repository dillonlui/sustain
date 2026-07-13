# Installing Sustain

Sustain is a free, native macOS app. It works fully offline. It requires
**macOS 14 (Sonoma) or newer**.

## 1. Download & install

1. Download **`Sustain-<version>.zip`** from the release page.
2. Double-click the zip to unzip it — you'll get **`Sustain.app`**.
3. Drag **`Sustain.app`** into your **Applications** folder.

## 2. First launch (important)

Sustain is not distributed through the Mac App Store and is not "notarized" by
Apple (that requires a paid Apple developer account). Because of that, the
**first** time you open it, macOS will show a warning and refuse to open it.
This is expected — here's how to approve it. You only do this once.

**On macOS 15 (Sequoia) and newer:**

1. Double-click **Sustain**. You'll see a message that it "could not be opened
   because Apple cannot check it for malicious software." Click **Done**.
2. Open **System Settings → Privacy & Security**.
3. Scroll down to the **Security** section. You'll see a line saying
   *"Sustain was blocked to protect your Mac."* Click **Open Anyway**.
4. Confirm with **Open Anyway** and authenticate (Touch ID / password) if asked.
5. Sustain now opens normally every time.

**On macOS 14 (Sonoma):**

1. In Finder, **right-click** (or Control-click) **Sustain.app** → **Open**.
2. In the dialog, click **Open**.
3. Sustain now opens normally every time.

### If it still won't open

Open **Terminal** (Applications → Utilities) and run this one line, which clears
the "downloaded from the internet" flag:

```sh
xattr -dr com.apple.quarantine /Applications/Sustain.app
```

Then open Sustain normally.

## 3. Set up your audio (recommended)

Open **Sustain → Settings** (⌘,) → **Audio** to choose which output device
plays pads and which plays click. If you're on a laptop with just built-in
speakers, pads and click share one output and Sustain will tell you so — that's
fine for trying it out, but for a live service you'll want separate outputs.

## Credits

Included pad audio: **"Ambient Pad Bases" by Karl Verkade**, offered free for
church use. Please support the artist:
https://karlverkade.bandcamp.com/album/ambient-pad-bases
