# Directive 08 — Releasing a Build to TestFlight

**What this is:** the exact, plain-English steps to get a new version of Virtual Backup Box
onto testers' iPhones through TestFlight. Written for Scott (not a developer). Follow it
one step at a time. The first build (1.0, build 1) shipped this way on 2026-06-16.

**Golden rule for Claude:** when walking Scott through this, give ONE step at a time and wait
for him to confirm before giving the next. Do not paste the whole list at him at once.

---

## Facts that stay the same every time

- Apple Developer account: paid, active (Scott is the Account Holder).
- Signing: **Automatic**, team `B96HF9533R`. Nothing to configure.
- App bundle ID: `com.scottfrey.Virtual-Backup-Box`.
- Builds go through the **Xcode app** (the command-line `xcodebuild` is not set up on this Mac).
- Testers live in the **"Testers"** internal group in App Store Connect (automatic distribution
  is on, so a new build reaches them by itself once it finishes processing).

---

## Step 1 — Bump the build number (Claude does this)

Before every new upload, the **build number** must go up by one, or Apple rejects it as a
duplicate. This is the `CURRENT_PROJECT_VERSION` value in the Xcode project file.

- Build 1 was `CURRENT_PROJECT_VERSION = 1`. The next one is `2`, then `3`, and so on.
- The **version** (`MARKETING_VERSION`, e.g. `1.0`) only changes when you want testers to see a
  new version name — it does **not** need to change for every test build.
- Claude edits this and commits it.

## Step 2 — Open the project

Open `Virtual Backup Box.xcodeproj` in Xcode.

## Step 3 — Pick the right destination

At the top of the Xcode window, set the device dropdown to **"Any iOS Device (arm64)"**.
(You cannot Archive while a simulator is selected — this is the #1 thing people miss.)

## Step 4 — Archive

Menu bar: **Product → Archive**. Wait for it to build. The **Organizer** window opens with the
new archive listed.

## Step 5 — Upload

In the Organizer:
1. **Distribute App**
2. **App Store Connect**  ← (this is the upload-to-Apple option)
3. **Distribute**, and let it use **automatic signing**.
4. Wait for the green check: **"… uploaded."** Click **Done**.

## Step 6 — Wait for processing

Apple processes the build (about 5–15 minutes). You get an Xcode notification:
**"… is Ready to Test."**

## Step 7 — Clear the encryption question (only if it appears)

Go to **appstoreconnect.apple.com → Virtual Backup Box → TestFlight tab**. If the build shows
**"Missing Compliance,"** click **Manage** and choose **"None of the algorithms mentioned
above"** → **Save**. (The app only uses Apple's standard system encryption, so this is correct.)
This only tends to appear on the first build of a version; later builds often skip it.

## Step 8 — Testers get it automatically

Because the "Testers" group has automatic distribution turned on, the new build goes to everyone
in that group once it's ready. On the iPhone, open the **TestFlight** app → **Virtual Backup
Box** → **Update** (or Install). Done.

---

## If you want to add a NEW tester later

- **Friends / family / you** who are on the Apple team → add them under **Internal Testing**
  (instant, no review).
- **Anyone else** → add them under **External Testing** (Apple does a quick one-time review,
  usually under a day).
- Group *names* are just labels for your own organizing — they don't change how anything works.
