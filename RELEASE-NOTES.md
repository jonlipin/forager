## 1.12.4 - 2026-10-14

- Every reload and login starts on the timer. If the game refuses switches on a timer, Forager falls back to key presses for that session only, and its message about it isn't repeated after every reload.
- New "Switch only on key presses" checkbox under Switching. It's ticked whenever Forager is in key press mode, with a note underneath when Forager turned it on by itself and why. Untick it to go back to the timer at once. Tick it yourself to switch only when you press a key; your own choice stays across reloads. Also /forager keys on or off.
- In key press mode, these keys never make a switch: Ctrl, Shift, Alt and the Windows key on their own, Tab, Escape, Enter and Caps Lock, and any key pressed while Ctrl, Alt or Shift is held. Ability keys stay left alone as before.
