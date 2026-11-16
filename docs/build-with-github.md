# Build the iPhone app with GitHub (no Mac needed)

This guide builds the app for you on one of GitHub's Macs, in the cloud, for free. You only need a web browser:
a computer is easiest, but every step also works in Safari on an iPhone or iPad.

**What you need**

- Your own copy of *Phantasy Star Online Episode I & II Plus* for GameCube, **USA**, as a disc image (ISO,
  CISO, GCZ or RVZ). It must be the USA *Plus* version (game ID `GPOE8P`); the build checks this.
- A free **GitHub account** ([github.com/signup](https://github.com/signup)).
- A way to sideload apps onto your iPhone, such as AltStore, SideStore or Sideloadly.

**Why this is set up this way.** The app is built from your disc's game program, `PsoV3.dol`. That file is
Sega's code, so it can't be shared, and the app built from it can't be shared either. You keep it in a
**private** repository (a project folder on GitHub that only you can see). GitHub's Mac downloads the main
project's prebuilt engine (the app without any game code), turns your `PsoV3.dol` into the game part, puts the
two together and gives the app back only to you.

The build takes about **10 to 15 minutes**. You do steps 1 to 3 once. After that, getting a new version only takes
step 4 again.

---

## Step 1: Get `PsoV3.dol` from your disc image

`PsoV3.dol` is a 5 MB file inside the disc image.

**The easy way:** open **[xbusse.github.io/pso-ios/extract](https://xbusse.github.io/pso-ios/extract/)**,
choose your disc image (ISO, CISO, GCZ or RVZ) and tap **Save PsoV3.dol**. It works on a computer or in Safari on
an iPhone or iPad. Everything happens in your browser; your disc image isn't uploaded anywhere. The page also
checks that it's the right version of the game.

**With Dolphin instead** (the GameCube emulator, on any Windows, Linux or Mac computer,
[dolphin-emu.org](https://dolphin-emu.org/download/)):

1. Open Dolphin. If your game isn't listed, choose **Config > Paths > Add...** and pick the folder that holds
   your disc image.
2. Right-click the game and choose **Properties**.
3. Open the **Filesystem** tab. You'll see a list of the disc's files.
4. Find **`PsoV3.dol`** in that list (it's near the top, not inside a folder). Right-click it and choose
   **Extract File...**.
5. Save it somewhere you'll find it, keeping the name `PsoV3.dol`.

Don't use `main.dol` or the "Extract System Data" option: on this disc, `main.dol` is only a small launcher.

## Step 2: Make your private copy on GitHub

1. Sign in to GitHub, then open **[github.com/new/import](https://github.com/new/import)**.
2. In **"The URL for your source repository"**, paste:

       https://github.com/xBusse/pso-ios.git

   Leave the username and password fields empty.
3. Under **Repository name**, type a name, for example `pso-build`.
4. Select **Private**. This matters: the build won't run in a public repository, and your `PsoV3.dol` must
   never be public.
5. Click **Begin import** and wait for "Your new repository is ready" (usually under a minute).

(Don't use the **Fork** button instead: a fork of a public project is always public.)

## Step 3: Add your `PsoV3.dol` to it

1. Open your new repository (GitHub shows a link when the import finishes).
2. Click **Add file > Upload files** (on a phone: the **+** button or the **...** menu, then **Upload files**).
3. Drag in `PsoV3.dol`, or tap **choose your files** and pick it.
4. Click **Commit changes** at the bottom.

<details>
<summary>Prefer to keep it out of the file list? Attach it to a release instead.</summary>

Open **Releases** (right-hand side of the repository page) > **Draft a new release**. In **Choose a tag**, type
`dol` and pick **Create new tag**. Drag `PsoV3.dol` into the attachments box, then click **Publish release**.
Releases of a private repository are private too. Don't skip "Publish": the build can't see drafts.
</details>

## Step 4: Build the app

1. In your repository, open the **Actions** tab. If GitHub asks, click
   **I understand my workflows, go ahead and enable them**.
2. On the left, click **Build iOS app**.
3. On the right, click **Run workflow**, leave the boxes as they are, and click the green
   **Run workflow** button.
4. A new run appears in the list after a few seconds (refresh if it doesn't). It shows a yellow dot while it
   builds and turns into a green tick when it's done, about **10 to 15 minutes** later. You can close the page in the
   meantime; GitHub emails you if a run fails.

The boxes are for testing other versions: **source** is the project the code comes from and **ref** is its
branch. **Full build** builds everything from scratch instead of using the prebuilt engine, which takes about an
hour (a run also does this by itself if that branch has no prebuilt engine). Leave them alone unless someone tells
you otherwise.

## Step 5: Download the app

1. Click the finished run (the line with the green tick).
2. Scroll down to **Artifacts** and click **PSO-unsigned-...** to download it. It arrives as a `.zip` file.
3. Unzip it to get **`PSO-unsigned-<date>.ipa`**: double-click it on a computer, or on an iPhone open it in the
   **Files** app and tap it.

GitHub deletes the download after 7 days. Run the build again if you need it later.

## Step 6: Install and play

1. Sideload the `.ipa` with your usual tool (AltStore, SideStore, Sideloadly, ...), the same way you'd install
   any other app that isn't from the App Store.
2. Open the app and choose **Game Files > Import disc image**, then pick your disc image from the Files app or
   iCloud Drive. The app copies the game's data out of it once and checks it's the right disc.
3. Back on the start screen, tap **Play**.

The app itself doesn't contain the game's data files (music, maps, models), which is why it asks for your disc
image the first time.

## Updating to a new version

Open **Actions > Build iOS app > Run workflow** again (step 4), then download and install as in steps 5 and 6.
Each run builds the newest code from the main project, so there's nothing to update in your copy. Installing
over the old app keeps your saves and settings.

---

## Cost: GitHub's free monthly allowance

Building on GitHub's Macs is free up to a monthly allowance. For private repositories, GitHub counts each Mac
minute as 10 minutes from that allowance. The free plan includes 2,000 minutes a month, which is about
**200 Mac minutes**, so roughly **12 builds a month** (a full build uses about four times as much). The allowance
resets each month.

- See how much you've used under your profile picture > **Settings > Billing and plans**.
- On a free account with no payment method, GitHub stops the build when the allowance runs out. It doesn't
  charge you.
- GitHub changes its pricing from time to time. Their
  [billing page](https://docs.github.com/en/billing/managing-billing-for-github-actions/about-billing-for-github-actions)
  has the current numbers.

## If something goes wrong

Click the failed run, then the red **build** box, to see which step failed. Its first error line usually says
why.

| Message | What to do |
| --- | --- |
| "This repository is public" | Your copy is public. Go to **Settings**, scroll to the bottom (**Danger Zone**), click **Change visibility** and choose **Private**. Then run it again. |
| "PsoV3.dol wasn't found" | Do step 3. The file must be named exactly `PsoV3.dol`. If you used a release, check it's published, not a draft. |
| "isn't from the USA v1.02 disc" | The file is from a different version of the game (Japanese, European or the original non-Plus release), or it's `main.dol` instead of `PsoV3.dol`. You need the USA *Plus* disc. |
| The run sits on "Queued" or "Waiting for a runner" | GitHub's Macs are busy, or you've used this month's allowance (see **Cost**). |
| The run fails in **Get the code to build** | The **source** or **ref** box was changed. Run it again with the default values. |
| It fails in **Build** | Run it once more (GitHub sometimes has a hiccup). If it fails again, try it with **Full build** ticked, and report it with the last lines of that step's log. |

## Questions

**Can I share the app with a friend?** No. It contains the game's program, built from your disc. Your friend
can make their own copy with this guide and their own disc.

**Does this give anyone else my disc?** No. Your repository is private, and so are its builds and downloads.
Only `PsoV3.dol` is uploaded, never the whole disc.

**Can I build it on my own Mac instead?** Yes, see "Building for iOS" in the [README](../README.md).
