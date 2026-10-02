# Changelog

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
