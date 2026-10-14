## 1.12.3 - 2026-10-14

- Fixed: Forager could get stuck switching only on your next key press. It falls back to key presses when the game refuses switches on a timer, but it also did so when three switches in a row merely looked ignored: on a slow connection, where a switch can take more than a second to land, and with Find Treasure on before 1.9.1. That choice was saved, so it stayed after updating.
  - A switch now gets a few more seconds to land before it counts as ignored, so a slow server no longer looks like a refusal.
  - Key press mode saved by an older version is cleared once: you go back to the timer at your next login, with a note in chat.
  - If switches only seemed ignored, the timer gets another try at each login. Only a real refusal from the game keeps key press mode until you type /forager retest.
- In key press mode, the status line (in the options and the tooltips) says how to try the timer again: /forager retest, or "Try the timer again" in the options.
