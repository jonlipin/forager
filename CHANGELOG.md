# Changelog

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
