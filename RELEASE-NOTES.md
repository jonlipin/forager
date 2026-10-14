## 1.9.1 - 2026-10-14

- Fixed for dwarves: Find Treasure stays on alongside other tracking on WoW Forever, and Forager now knows it.
  - With Find Treasure on but not ticked, the rotation no longer waits saying it isn't in the rotation. Forager leaves Find Treasure alone and rotates the rest.
  - With Find Treasure ticked, the rotation no longer gets stuck on it. Forager keeps Find Treasure on (and puts it back if it drops off) while the other ticked trackers take turns. Its icon glows while it's on, and the options list marks it "kept on".
- The rotation follows the tracker it last switched to, so a tracker that stays on unexpectedly can't hold it up either.
- The status line shows what is on alongside the rotation, for example "Find Herbs, plus Find Treasure".
