# Changelog

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
