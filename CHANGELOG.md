# Changelog

## 1.16.0 - 2026-10-14

- Hide this track, in each track's tab: takes the track off the screen and out of Next track for now, without deleting it. Its tab stays, its name grayed, so you can bring it back. Hiding the running track moves on to the next track on show, and one track always stays on show.
- Collapse till hovered, in each track's tab: while the mouse is away, the track's row folds into its play / stop button, its icons sliding in under it. The button then shows the tracker that is on, glowing, with the swipe and seconds to the next switch and the next tracker small in its lower right corner. When the next one's turn comes, it grows out of the corner to fill the button, and the one after it grows into the corner. Point at the button and the row slides open again; it folds back once the mouse leaves the row.
- A tracker held on with Shift-click (Track and pause) glows reddish orange, and goes back to its normal glow when the rotation runs again.

## 1.15.0 - 2026-10-14

- Shift-click a tracker's icon to switch to it and pause the rotation, so it stays on until you press play.
- The key is set with the new "Track and pause" button under Tracker icons: Shift (the default), Ctrl, Alt or off. The icons' tooltips show it.
- A plain click works as before: it switches to that tracker straight away, and the rotation carries on from it after its usual time.

## 1.14.0 - 2026-10-14

- All tracks is laid out afresh. "Show all tracks together" and "Move Tracks Separately" (the new name for "Move each track's row on its own") share the top line. Below them, Vertical (moved here from Tracker icons, where it was "Stack them vertically") sits on the left of the alignment button, then Gap between tracks and Gap between icons.
- Move Tracks Separately and Gap between tracks are grayed out while Show all tracks together is off, since they only matter with every track on show. Vertical, the alignment and Gap between icons stay usable with one row, because they still decide its direction, its spacing and the side it stays lined up on when you switch tracks.
- With Move Tracks Separately on, Vertical, the alignment and Gap between icons move out of All tracks and into each track's tab, so every track can have its own. Each track starts from the shared settings, and every row stays where it is on screen. Untick it and they move back to All tracks as shared settings; each track's own choices are kept for next time.
- Tracks and trackers follows right under All tracks, so the page closes up when All tracks gets shorter.

## 1.13.3 - 2026-10-14

- Fixed: the alignment now holds the icons in place, not just the track's name. With "Show all tracks together" off, switching to a track with more or fewer trackers used to grow or shrink the row from its middle, so the icons always looked centered. Now a left-aligned row keeps its left edge still, a right-aligned one its right edge, and a centered one its middle. Stacked vertically, the same goes for top, center and bottom.
- The same holds when you add or remove trackers, with every track on show, and for rows moved on their own.
- Your saved position is converted once, so nothing jumps when you update.

## 1.13.2 - 2026-10-14

- Each track can put its play / stop button on the left or the right of its icons (at the top or the bottom when they are stacked vertically). Use the Play button in that track's tab under Tracks and trackers; every track has its own.

## 1.13.1 - 2026-10-14

- The settings that apply to every track now have their own All tracks section, above Tracks and trackers: Show all tracks together, the alignment, the gap between tracks, the gap between icons, and moving each track's row on its own. Tracks and trackers keeps New track, the tabs and the box that edits one track.
- "Show every track's icons at once" is now called "Show all tracks together".

## 1.13.0 - 2026-10-14

- The Tracks and trackers part of the options is rebuilt. Settings for every track sit at the top: show every track's icons, alignment, gap between tracks, the new gap between icons, and moving each track's row on its own. Below them, one track at a time is edited in an inset box.
- Each track has its own tab on top of that box once there are two or more. Click a tab to edit that track; the running track keeps running, and a check mark shows which one is current. "Use this track" makes the open one current. New track adds a tab without changing what's running.
- Drag and drop to sort: drag a tracker up or down by its name, or drag a tab sideways, and a gold line shows where it will land. The up and down arrows still work.
- Each tracker can have its own time: type seconds in the box beside it to keep it up longer or shorter than Time between switches, in that track. Leave it empty for the usual time. The countdown and the swipe follow it.
- New "Gap between icons" slider (0 to 20 px), and /forager icongap followed by a number.
- Each track can hide or show its name above its icons; a row without a name moves up into the space.
- Status: the text no longer runs into the button below it, and "Try the timer again" only appears when the timer was actually refused, so it always has something to do (and says so in chat).

## 1.12.4 - 2026-10-14

- Every reload and login starts on the timer. If the game refuses switches on a timer, Forager falls back to key presses for that session only, and its message about it isn't repeated after every reload.
- New "Switch only on key presses" checkbox under Switching. It's ticked whenever Forager is in key press mode, with a note underneath when Forager turned it on by itself and why. Untick it to go back to the timer at once. Tick it yourself to switch only when you press a key; your own choice stays across reloads. Also /forager keys on or off.
- In key press mode, these keys never make a switch: Ctrl, Shift, Alt and the Windows key on their own, Tab, Escape, Enter and Caps Lock, and any key pressed while Ctrl, Alt or Shift is held. Ability keys stay left alone as before.

## 1.12.3 - 2026-10-14

- Fixed: Forager could get stuck switching only on your next key press. It falls back to key presses when the game refuses switches on a timer, but it also did so when three switches in a row merely looked ignored: on a slow connection, where a switch can take more than a second to land, and with Find Treasure on before 1.9.1. That choice was saved, so it stayed after updating.
  - A switch now gets a few more seconds to land before it counts as ignored, so a slow server no longer looks like a refusal.
  - Key press mode saved by an older version is cleared once: you go back to the timer at your next login, with a note in chat.
  - If switches only seemed ignored, the timer gets another try at each login. Only a real refusal from the game keeps key press mode until you type /forager retest.
- In key press mode, the status line (in the options and the tooltips) says how to try the timer again: /forager retest, or "Try the timer again" in the options.

## 1.12.2 - 2026-10-14

- The options page scrolls the way Shard Grid's does: the game's thin modern scroll bar (the older one's arrow buttons don't draw on this client), hidden when everything fits, and the mouse wheel scrolls the page anywhere on it, sliders included, instead of stopping on them.

## 1.12.1 - 2026-10-14

- Fixed: the options page in Esc > Options > AddOns > Forager had shrunk to about half size in a corner of the page. It was being scaled down to fit the page's height, and the new track settings had made it much taller. It now fills the page's width at full size and scrolls when it is taller than the page.

## 1.12.0 - 2026-10-14

- Line up the tracks' rows on the left, in the center or on the right. With the icons stacked vertically, the columns line up at the top, in the center or at the bottom. Use the alignment button under Tracks and trackers: left-click for the next, right-click for the previous.
- New "Gap between tracks" slider (0 to 40 px) for the space between the tracks' rows or columns.
- New "Move each track's row on its own" option: drag each track's row wherever you want it, by its icons, its play button or its name. Each track remembers its spot. Untick it and the rows join up again, with their spots kept for next time.
- Locking the icons locks every row, and Reset position puts every row back.
- New commands: /forager align left, center, right, top or bottom; /forager gap followed by a number; /forager rows apart or together.

## 1.11.1 - 2026-10-14

- Fixed: after a reload, pressing play on another track's row did nothing until you clicked a tracker. The tracker the old track had left on was taken for one you picked yourself, so Forager waited. Now a tracker that is in any of your tracks never counts as your own pick, and the new track takes over at once.
- A tracker that isn't in any of your tracks is still left alone when you turn it on yourself.

## 1.11.0 - 2026-10-14

- Every track on screen at once: each track gets its own row of icons, with its name above it and its own play / stop button. Rows stack one under another, or sit side by side when the icons are stacked vertically.
- Press play on a row to run that track. The track that was running stops, so only one track runs at a time. Press stop on the running row to pause it.
- The running track's row is lit, with the glow, the countdown and the swipe; the other rows are dimmed until they run. Click a row's name to make it the current track without starting it.
- The icons in every row still work: left-click turns that tracker on, right-click leaves it out of that row's track or puts it back.
- New option under Tracks and trackers: "Show every track's icons at once" (on by default). Turn it off to show only the current track, whose name then steps through the tracks as before.
- With a single track, the icons look exactly as they did.

## 1.10.0 - 2026-10-14

- Right-click a tracker's icon to leave it out of the rotation for now. It turns grey and is skipped until you right-click it again. A left-click still turns it on, and the rotation carries on from it. Handy for a hunter picking the tracking to suit what's around.
- Leave all but one out and Forager keeps that one on.
- Clicking an icon, or pressing your "switch to the next tracker" key, now keeps the switch's sound, so you hear it worked. The timer's own switches stay quiet.
- Tracks: keep several sets of trackers, for example Gathering and Hunting, and switch between them. Only the chosen track runs, and switching hands over at once. Each track has its own ticked and left-out trackers.
  - Add, rename and delete tracks above the tracker list in the options (Delete asks for a second click).
  - Switch tracks with the track's name above the icons (left-click next, right-click previous), the new "Next track" key binding, or /forager track (next, previous, a number, a name, or new followed by a name).
  - What you had ticked becomes Track 1.
- A track with a single tracker keeps that one on instead of waiting for a second.
- Right-clicking an icon no longer opens the options; right-click the pause button or the minimap button for those.

## 1.9.1 - 2026-10-14

- Fixed for dwarves: Find Treasure stays on alongside other tracking on WoW Forever, and Forager now knows it.
  - With Find Treasure on but not ticked, the rotation no longer waits saying it isn't in the rotation. Forager leaves Find Treasure alone and rotates the rest.
  - With Find Treasure ticked, the rotation no longer gets stuck on it. Forager keeps Find Treasure on (and puts it back if it drops off) while the other ticked trackers take turns. Its icon glows while it's on, and the options list marks it "kept on".
- The rotation follows the tracker it last switched to, so a tracker that stays on unexpectedly can't hold it up either.
- The status line shows what is on alongside the rotation, for example "Find Herbs, plus Find Treasure".

## 1.9.0 - 2026-10-11

- Sparkles on the tracker that's on: a spell effect borrowed from the game glitters around the icon, reaching just past its border. Turn them on or off with "Sparkles on the active tracker" in the options.
- Eight sparkle effects to choose from with the Sparkle effect button: left-click for the next one, right-click for the previous one. Holy glitter is the default.
- Sparkle size (50 to 200 percent) and Sparkle intensity (0 to 100 percent) sliders. They are grayed out while sparkles are off.
- The glow and the sparkles fade from the old tracker to the new one when it switches, instead of jumping.
- Round icons: the glow on the tracker that's on is round now, and so is the pause button.
- The hover highlight is softer and stays inside the icon's shape.
- Fixed: in the action bar look, the countdown swipe left a strip down the left side of the icon uncovered. It now uses the same dark fill as the game's own action buttons and sits inside the frame.
- New commands: /forager sparkles turns them on or off, /forager sparkles next, previous or a number picks the effect, and /forager sparkles size or intensity followed by a percentage sets those.

## 1.8.0 - 2026-10-10

- New Look section in Forager's options. The Window style button picks Automatic, Blizzard or Dark: Blizzard is the game's own art, Dark is a flat dark look Forager draws itself with no other addon needed, and Automatic uses EllesmereUI's look when EllesmereUI is installed and Blizzard otherwise. Left-click for the next style, right-click for the previous one.
- A Dark background opacity slider sets how much of the world shows through the Dark window, from 0 to 100 percent. It is grayed out unless Dark is the style.
- The style covers the tracker icons, the pause button and the frame of Forager's own options window. The options themselves keep the game's look, and the minimap button is left as it is.
- New Icon shape button beside Reset position: Automatic, Round or Square. Automatic gives square icons in the Dark and EllesmereUI styles and the action bar look with Blizzard's; Round and Square work in any style. The glow on the tracker that's on and the countdown swipe stay in every shape, and the change shows at once.
- New commands: /forager style auto, blizzard or dark, and /forager shape auto, round or square. On their own they move on to the next one.
- EllesmereUI support: with EllesmereUI installed, Automatic draws the tracker icons and the options window in its look.
- Going from Blizzard to another style is drawn at once. Any other change takes a reload of the interface; Forager says so and offers a Reload now button.
- Fixed: the first time you opened Forager from Esc > Options > AddOns, the page showed only its title. The options are there on the first visit now.
- Fixed: the options window's close X could not close it in combat. It hides the window itself now, in combat and out of it.
- The minimap button stays where a minimap button collector, such as EllesmereUI's, puts it, instead of being pulled back to the edge of the minimap.
- American spelling throughout.

## 1.7.0 - 2026-10-02

- Set a pause / resume key right from Forager's options: click the button under Keys, press the key you want. Escape cancels, and Unbind clears it.
- If the key already does something else, Forager tells you what and asks you to press it again before taking it over.
- It's the same binding as Keybindings > AddOns > Forager > Pause / resume, so the two always agree, and the pause button's tooltip shows the key.

## 1.6.0 - 2026-10-02

- Quiet switches: every tracking switch plays a sound, so Forager mutes sound effects from the moment it switches until just after the switch lands (2 seconds at most). On by default; turn it off if it ever clips a sound you wanted.
- Waits while the loot window is open before making a due switch, so it never gets in the way of looting a node. On by default.
- The minimap button now shows the tracker that's on (optional).
- Swaps for the situation, each optional and on by default:
  - fishing pole equipped: Find Fish
  - druid in Cat Form: Track Humanoids
  - hunter in a battleground or arena: Track Humanoids
- When the situation passes, the rotation picks up again at once, or the tracker you had before comes back if the rotation is paused. Each swap only happens if the character knows that tracker.

## 1.5.0 - 2026-10-02

- Restores tracking after death. Dying clears your tracking; Forager remembers what each character was tracking and turns it back on as soon as you're alive again, whether you're resurrected or take the spirit healer, and even while the rotation is paused.
- It puts back whatever was on, including a tracker you picked yourself that isn't in the rotation. If you had switched tracking off, it stays off.
- New option: Restore tracking after death (on by default).

## 1.4.0 - 2026-10-02

- Set the order your trackers rotate in: every tracker in the options list has up and down arrows, and the rotation and the tracker icons follow that order.
- The order is saved account-wide. Trackers a character doesn't know keep their place for the characters that do.
- New command: /forager move <tracker> up or down, for example /forager move beasts up.

## 1.3.2 - 2026-10-02

First public release.

- Rotates your tracking spells on a timer you set (2 to 60 seconds) while you are out of combat. Find Herbs and Find Minerals are on by default; tick any other tracker your character knows, such as Find Treasure or hunter tracking, to add it.
- Tracker icons on screen: the tracker that is on glows, the next one shows a cooldown swipe and the seconds until it switches, and clicking an icon switches to it. A play / stop button pauses and resumes. Move, resize, lock, stack vertically or hide them in combat.
- Never switches in combat, while dead, on a flight path or while you are casting. Pauses in cities and inns and in dungeons, raids and battlegrounds (both optional), and can switch only while you are moving.
- Leaves the rotation alone when you turn on a tracker that isn't in it, and skips a tracker that can't be cast right now for a minute.
- Minimap button (left-click options, right-click pause / resume, can be hidden), an options page under Options > AddOns > Forager, key bindings for pause / resume, switch now and options, and /forager commands.
- If the game ever refuses tracking switches from a timer, Forager switches on your next key press after the delay instead, never on ability keys, and passes every key on to the game.
