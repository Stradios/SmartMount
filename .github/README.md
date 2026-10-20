# SmartMount – WoW 3.3.5a (WotLK)

<img src="https://raw.githubusercontent.com/Stradios/SmartMount/refs/heads/main/smartmount-demo.webp" alt="SmartMount – WoW 3.3.5a (WotLK) V2" width="350">

**One button. One macro. Always the right mount.**

SmartMount picks a **random mount from your fastest tier** for where you are right now:

- **Swimming** → Sea Turtle / Riding Turtle (if you own one)
- **Flyable area** → your fastest flying mount (280% or 310%)
- **Anywhere else** → your fastest ground mount

Click again while mounted to **dismount**. If you're in a vehicle, it **exits the vehicle** first.

You can trigger it three ways:

1. Click the button on the **Companions / Mounts** tab
2. Type `/smartmount` (or `/smount`)
3. Drag the auto-created **SmartMount** macro to your action bar

## Compatibility

- **Client:** World of Warcraft 3.3.5a (Wrath of the Lich King)
- **Interface:** `30300`
- **Version:** 2.0
- No dependencies, no libraries.

## Installation

1. Download or `git clone` this repo.
2. Copy the `SmartMount` folder into:
   `World of Warcraft\Interface\AddOns\SmartMount\`

   It must contain:
   ```
   SmartMount/
     SmartMount.toc
     SmartMount.lua
     icon.tga
   ```
3. **Fully restart WoW** (close the game completely — not just `/reload`) so `icon.tga` loads.
4. Enable it on the **AddOns** screen at character select.

## Usage

- Open **Companions** (`C` → Mounts tab) and click the SmartMount button (top-right, 22px by default).
- Or press your `SmartMount` macro / type `/smartmount`.
- **Put it on your bars:** open `/macro`, drag the `SmartMount` macro onto an action bar — or Shift-drag the Companions-tab button onto a bar.

## Common Fixes

- **Button icon is a green box / missing** → run `/smartmount debug`, verify `icon.tga` exists, then do a **full game restart**.
- **Macro not created** → macro slots are full. Delete one, then run `/smartmount macro`.
- **Won't fly where you expect** → that zone isn't flyable, or you're in Wintergrasp (forced ground).
- **Wrong mount type or speed** → run `/smartmount list`, then fix it with `/smartmount set`.

---

## Advanced / Technical Details

<details>
<summary><strong>📋 Full command reference</strong></summary>

`/smartmount` or `/smount`

| Command | What it does |
|---|---|
| `/smartmount` | Mount / dismount |
| `/smartmount list` | Show how each of your mounts is classified: `name (spell ID): kind, speed%` |
| `/smartmount set <spellID> <fly\|ground\|water\|ignore> [speed%]` | Fix a misclassified mount. Ex: `/smartmount set 12345 fly 310` |
| `/smartmount reset` | Clear all manual overrides |
| `/smartmount macro` | (Re)create the `SmartMount` macro, blue icon |
| `/smartmount macro pin` | Remember the macro's current icon as the default for future recreates |
| `/smartmount button <x> <y>` | Move the Companions-tab button (default `310 -50`) |
| `/smartmount button size <12-64>` | Resize the button (default `22`) |
| `/smartmount button reset` | Reset button position + size |
| `/smartmount debug` | Show addon folder, icon in use, and which `icon.*` files the client can see |

</details>

<details>
<summary><strong>⚙️ How it works</strong></summary>

1. Scans `GetNumCompanions("MOUNT")` and classifies each mount:
   - Hardcoded water list + flying list with speeds (280% drakes/proto-drakes/Netherwing/Ashes of Al'ar, 310% Invincible, etc.)
   - Fallback: parses the spell tooltip `%` speed and `fly/flight/flying` wording
   - Manual `SmartMountDB.overrides` win over everything
2. Checks context: `IsSwimming()` → water, `IsFlyableArea()` (with Wintergrasp excluded) → fly, else ground.
3. Picks uniformly at random **among ties for fastest speed** in that pool — variety without ever picking a slow mount.
4. `CallCompanion("MOUNT", index)` to summon.

Settings persist per-account in `SavedVariables: SmartMountDB` (button position/size, overrides, macro icon pin).

</details>

<details>
<summary><strong>🧩 3.3.5a quirks handled</strong></summary>

- Mount spells aren't in the spellbook, so `IsUsableSpell()` is not used.
- Macro icons must be Blizzard built-ins — macros use a blue drake/charger icon; the custom `icon.tga` is button-only.
- Folder-rename safe: icon path uses the real addon folder name, with `SmartMount` fallback.
- Safe RNG seeding on clients without `math.randomseed`.
- New mounts learned (`COMPANION_LEARNED`) clear the classification cache.

</details>

<details>
<summary><strong>📁 Files</strong></summary>

- `SmartMount.toc` – metadata (`## Interface: 30300`, `## Version: 2.0`)
- `SmartMount.lua` – all logic (~500 lines)
- `icon.tga` – 64x64 button art (16,402 bytes)

</details>

---

## License

Copyright © Stradios 2026. All rights reserved.
