# NPC Appearance Patcher - xEdit Script

**Turn NPC replacer mods into conflict-free SkyPatcher runtime patches, with full leveled list support.**

NPC replacer mods change NPC appearances by overriding the original NPC records. Overrides conflict with every other mod touching the same NPCs, and generic NPCs spawned from leveled lists often end up with invisible faces (only floating hair and teeth) or crash the game.

NPC Appearance Patcher moves the replacer's appearance into new NPC records and generates the configuration files that apply it at runtime:

- **Unique NPCs** get their new face, skin, race, gender and voice through [SkyPatcher](https://www.nexusmods.com/skyrimspecialedition/mods/106659).
- **Generic NPCs from leveled lists** (bandits, guards, soldiers...) are replaced *inside the leveled lists* by the new NPC, keeping the original level and count. No more invisible faces.
- **More visual diversity**: run it on several replacer mods that edit the same generic NPCs, and every variant is added to the leveled lists alongside the others.

---

## Requirements

- [SSEEdit (xEdit)](https://github.com/TES5Edit/TES5Edit) 4.1 or later
- [SkyPatcher](https://www.nexusmods.com/skyrimspecialedition/mods/106659)
- A mod manager. Instructions below use Mod Organizer 2.

## Installation

Copy the content of this repository into your xEdit `Edit Scripts` folder, keeping the `AP` subfolder:

```
Edit Scripts\
├── NPC Appearance Patcher.pas
├── NPC Appearance Isolator.pas
└── AP\
    ├── AP_Utils.pas
    ├── AP_Isolator.pas
    └── AP_LeveledLists.pas
```

## Usage

1. Start from the **original** replacer plugin(s), and preferably a **new game** (see [Save games](#save-games)).
2. Launch SSEEdit from your mod manager with your full load order.
3. Select one or more replacer plugins, right-click, **Apply Script**, then pick **NPC Appearance Patcher**.
4. Answer the questions:
   - **Integration Mode**: *Yes* isolates the NPCs, then generates the configs. *No* only generates the configs, for plugins already isolated.
   - **Prefix** (Integration Mode only): letters and digits, e.g. `RD`. Isolated NPCs are named `RD_<original EditorID>`. The same prefix is used for all selected plugins.
5. Save the config files when prompted. With several files, a single confirmation saves them all to their default path.
6. Close SSEEdit and **save the modified plugins**.
7. In MO2, move the content of `overwrite\NPC Appearance Patcher\` into a new mod and enable it.
8. Keep the replacer plugins enabled: the isolated NPCs live in them. The replacer's own FaceGen files can stay installed.

The xEdit log lists, for each NPC, the detected changes and how they are applied, followed by a summary.

### NPC Appearance Isolator

`NPC Appearance Isolator` runs the isolation step alone. Run **NPC Appearance Patcher** afterwards without Integration Mode to generate the configs.

## How it works

### 1. Isolation

For each NPC override of the selected plugins:

- the override is copied as a new record `<prefix>_<EditorID>` in the same plugin, then the override is removed. The original NPC is no longer modified by the plugin;
- the replacer's FaceGen files (`FaceGeom` .nif, `FaceTint` .dds), loose or packed in a BSA, are copied to the new FormID. The .nif is not edited;
- NPCs with the *Use Traits* template flag are left untouched: their appearance comes from their template;
- official masters are never edited.

**ESL plugins**: the Next Object ID is fixed automatically if needed. A plugin that does not have enough ESL FormIDs left for its isolated NPCs is skipped (remove its ESL flag to process it). Regular ESP plugins are left as they are.

### 2. Change detection

Each isolated NPC is compared with the original NPC. Only real changes produce a line:

| Change | Detected when |
|---|---|
| Face | the isolated NPC has a FaceGen |
| Skin | `WNAM` (worn armor) differs |
| Race | `RNAM` differs |
| Gender | the female flag differs |
| Voice | `VTCK` differs |

### 3. Output

| NPC | Result |
|---|---|
| In a leveled list, with FaceGen | SkyPatcher `leveledList`: the original NPC is removed from each list, the isolated NPC is added with the same level and count |
| Unique | SkyPatcher `npc`: `copyVisualStyle`, `skin`, `race`, gender, `voiceType` |
| In a leveled list, without FaceGen | SkyPatcher `npc` on the original NPC, to avoid a faceless NPC |

References always use FormIDs. Files are written to `Data\NPC Appearance Patcher\` (MO2: `overwrite\NPC Appearance Patcher\`), one set per plugin:

```
NPC Appearance Patcher\
├── SKSE\Plugins\SkyPatcher\npc\<plugin>.ini
├── SKSE\Plugins\SkyPatcher\leveledList\<plugin>.ini
├── meshes\actors\character\FaceGenData\FaceGeom\<plugin>\<FormID>.nif
└── textures\actors\character\FaceGenData\FaceTint\<plugin>\<FormID>.dds
```

Examples:

```ini
; SkyPatcher leveledList
filterByLLNPCs=Skyrim.esm|3DF08:removeFromLLs=Skyrim.esm|1A2B3
filterByLLNPCs=Skyrim.esm|3DF08:addToLLs=MyReplacer.esp|801~1~1, MyReplacer.esp|801~12~1

; SkyPatcher npc
filterByNpcs=Skyrim.esm|13BBB:copyVisualStyle=MyReplacer.esp|802
filterByNpcs=Skyrim.esm|13BBB:race=Skyrim.esm|13748
```

FaceGen files extracted from a BSA go through an `_extract` folder next to their destination. The empty `_extract` folders left behind can be deleted.

## Save games

Isolation creates new NPC records, and **their FormIDs are part of your save games**: generic NPCs already spawned from leveled lists are stored in the save with a copy of their NPC data.

- Isolate a plugin **once per playthrough**, then keep the saved plugin.
- To regenerate the configs (fixed script...), run NPC Appearance Patcher **without Integration Mode** on the already isolated plugin: no FormID changes.
- Never isolate again from the original plugin during a playthrough. Old saves may crash on face morphs (`BSFaceGenMorphDataHead`) near NPCs spawned before the change. Waiting for the area to reset (10+ in-game days elsewhere) usually fixes it.

## Limitations

- NPCs both in a leveled list and placed directly in the world keep their original look for the placed references (a warning is logged).
- Use Traits NPCs are not converted.
- Name and outfit changes are not converted.
- RDF (Race Distribution Framework) is not supported.

## Troubleshooting

- **Invisible faces**: the content of `overwrite\NPC Appearance Patcher\` is not installed as an active mod, so the isolated NPCs have no FaceGen.
- **Crash on an old save only**: see [Save games](#save-games).
- **Script error in xEdit**: send the full xEdit log in an issue.

---

## Development

### Layout

| File | Role |
|---|---|
| `NPC Appearance Patcher.pas` | Main script: change detection, config output |
| `NPC Appearance Isolator.pas` | Runs the isolation alone |
| `AP/AP_Utils.pas` | Dialogs, SkyPatcher record IDs, record queries, resources, config saving |
| `AP/AP_Isolator.pas` | Isolation, ESL checks, FaceGen copy |
| `AP/AP_LeveledLists.pas` | Leveled list index (winning overrides) and SkyPatcher leveledList rules |

`uses` paths are relative to the `Edit Scripts` folder.

### xEdit scripting pitfalls

The scripts run in JvInterpreter, which has some quirks:

- `InputQuery` does not return the typed text: use `AskInputDialog`.
- `TStrings.SaveToFile` only accepts one argument (no encoding). UTF-8 can be obtained through `TJsonObject.SaveToFile`, then `LoadFromFile` / `SaveToFile`.
- Built-in xEdit functions take precedence over script functions with the same name (e.g. `CanBeESL`, `ResourceExists`). Check new names against `xEdit/JvI/xejviScriptAdapter*.pas` in the xEdit repository.
- Pass plain variables to `PChar`, never an expression: `CopyFile(PChar(DataPath + relPath), ...)` silently copies nothing.
- Char comparisons are unreliable: use `Pos` / `Copy`.
- Avoid `Break` / `Exit` inside `repeat` loops.
- Errors are often reported at the end of the enclosing `try` block, not at the faulty line.

### Branches

- `main`: released versions.
- `develop`: integration branch.
- `feature/v1`: v1 development. Squash-merged into `develop` as a single commit when finished, then merged into `main`.

## Credits

Huge thanks to **mmsk4989**, author of [SkyPatcher RDF NPC Replacer Converter / NPC Replacer Converter](https://www.nexusmods.com/skyrimspecialedition/mods/141105). The idea of isolating replacer NPCs and converting them into runtime patches is theirs, and the isolation, ESL checks and config generation of this script are based on their code.

- **mmsk4989**: original idea and base code.
- **sanchofyah**: NPC Appearance Patcher (leveled list support, automatic change detection).
- Authors of [SkyPatcher](https://www.nexusmods.com/skyrimspecialedition/mods/106659) and [xEdit](https://github.com/TES5Edit/TES5Edit).
