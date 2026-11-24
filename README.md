# PetDex

A collection log for hunters in World of Warcraft: Forever (interface `16001`). Find, tame and collect every beast, with rares and uniques as the headline collection.

## Development

The addon lives in `PetDex/`. Link it into the game so `/reload` picks up changes:

```powershell
New-Item -ItemType Junction `
  -Path "B:\Blizzard\World of Warcraft\_forever_\Interface\AddOns\PetDex" `
  -Target "$PWD\PetDex"
```

| File | Purpose |
|---|---|
| `Core.lua` | Namespace, event dispatch, saved variables, helpers |
| `Data/Beasts.lua` | Shipped beast data by NPC ID (seed data for now) |
| `Collection.lua` | Seen/tamed records, beasts discovered in game, stats |
| `Tracking.lua` | Sightings, tame detection, active pet and stable backfill |
| `BeastStage.lua` | A beast's 3D model on a lit stage in its dex state (tamed, seen, silhouette), auto-framed |
| `DexWindow.lua` | The dex window (`/petdex`): families, looks grouped by model, and a viewer |
| `Tooltip.lua` | Collection status on beast tooltips |
| `Probe.lua` | Debug probe: can the client read a unit's model (`/petdex probe`) |
| `ModelLab.lua` | Debug window: a beast in each dex state, plus turning, zoom, animations and a frame-rate test (`/petdex lab`) |
| `Slash.lua` | `/petdex` (`/pdex`) commands |

## Forever client notes

- Detect Forever by interface number (16000–19999), not `WOW_PROJECT_ID`.
- FrameXML lacks some old globals (`MouseIsOver`, `SetDesaturation`); use the widget methods.
- HD models; `SetCustomCamera(0)` portrait framing is ignored.
