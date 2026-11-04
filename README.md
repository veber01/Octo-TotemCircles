# TotemCircles v0.4.2

## Range precedence

1. Slot override (`/tcr slot`) then global radius (`/tcr radius`)
2. Saved per-spell override (`/tcr spell <ID> <yards>`)
3. Saved per-name override (`/tcr name <slot> <yards>`)
4. Parsed explicit radius in the summon spell description (including Stoneskin 8071)
5. Totemic Mastery heuristic, only if no description radius found
6. Vanilla-oriented fallback table; then DBC fallback; then 20-yard unknown default


## Old overrides / enabling automatic selection

Run `/tcr overrides` to see any saved per-spell or per-name overrides. If 8071 was overridden earlier, clear it:

```
/tcr clear spell 8071
/tcr clear name 2
/tcr clear slot 2
/tcr clear global
/tcr auto
/tcr rangecheck
```

Only use `clear name 2` while Stoneskin is currently in the Earth slot, and only if you want to remove its stored name override. `/tcr auto` clears slot and global radius overrides, **not** saved spell/name values.

## Saved settings

All `/tcr` configured colors, ring geometry, terrain setting, enable state, mastery preference, and per-name/per-spell overrides are stored in `TotemCirclesDB` via `## SavedVariables: TotemCirclesDB` in the TOC. Settings are loaded on addon initialization and re-applied to the native DLL via periodic sync and game events. WoW writes SavedVariables on logout/exit or `/reload`, **not** necessarily on an unexpected crash. Do not delete `WTF/Account/<account>/SavedVariables/TotemCircles.lua` if you want to keep settings.

Per-slot/default order: Fire=1, Earth=2, Water=3, Air=4. Set colors with `/tcr color <1-4> <RRGGBB|AARRGGBB>`.
