#!/usr/bin/env node
// Generates PetDex/Data/Beasts.lua from a CMaNGOS classic-db dump.
//
// Source: https://github.com/cmangos/classic-db (GPL v3), file
// Full_DB/ClassicDB_*.sql.gz. The beast list is original Classic (1.12);
// WoW Forever changes (new families, newly tameable beasts) are learned in
// game by the addon.
//
// Usage: node tools/import-classic-db.mjs <ClassicDB.sql[.gz]> [--out PetDex/Data/Beasts.lua] [--stats]
//
// Reads creature_template (who is tameable, family, levels, rank, display IDs,
// attack speed, damage school) and creature (spawn count and one spawn point
// per NPC; the addon turns the point into a zone name in game).

import { createReadStream, writeFileSync } from "node:fs";
import { createGunzip } from "node:zlib";
import { createInterface } from "node:readline";

const args = process.argv.slice(2);
const input = args.find((a) => !a.startsWith("--") && args[args.indexOf(a) - 1] !== "--out");
const outIndex = args.indexOf("--out");
const output = outIndex >= 0 ? args[outIndex + 1] : "PetDex/Data/Beasts.lua";
const statsOnly = args.includes("--stats");
if (!input) {
  console.error("Usage: node tools/import-classic-db.mjs <ClassicDB.sql[.gz]> [--out file] [--stats]");
  process.exit(1);
}

// CreatureFamily IDs in the 1.12 client for hunter-tameable families.
const FAMILIES = {
  1: "Wolf", 2: "Cat", 3: "Spider", 4: "Bear", 5: "Boar", 6: "Crocolisk",
  7: "Carrion Bird", 8: "Crab", 9: "Gorilla", 11: "Raptor", 12: "Tallstrider",
  20: "Scorpid", 21: "Turtle", 24: "Bat", 25: "Hyena", 26: "Bird of Prey", 27: "Wind Serpent",
}; // 26 was "Owl" in Classic; WoW Forever renamed the family Bird of Prey.
const CREATURE_TYPE_BEAST = 1;
const TYPEFLAG_TAMEABLE = 0x1;
// Rank: 0 normal, 1 elite, 2 rare elite, 3 boss, 4 rare.
const RARE_RANKS = new Set([2, 4]);
const ELITE_RANKS = new Set([1, 2, 3]);
const SCHOOLS = { 1: "holy", 2: "fire", 3: "nature", 4: "frost", 5: "shadow", 6: "arcane" };

// --- SQL dump parsing -------------------------------------------------------

// Splits "(1,'a,b',NULL),(2,...)" into rows of raw values (strings unescaped,
// NULL as null, numbers as strings).
function* parseTuples(text, start) {
  let i = start;
  const n = text.length;
  while (i < n) {
    while (i < n && text[i] !== "(") {
      if (text[i] === ";") return;
      i++;
    }
    if (i >= n) return;
    i++; // (
    const row = [];
    let value = "";
    let quoted = false;
    let wasQuoted = false;
    for (; i < n; i++) {
      const c = text[i];
      if (quoted) {
        if (c === "\\") {
          const next = text[++i];
          value += next === "n" ? "\n" : next === "r" ? "\r" : next === "0" ? "\0" : next;
        } else if (c === "'") {
          if (text[i + 1] === "'") {
            value += "'";
            i++;
          } else {
            quoted = false;
          }
        } else {
          value += c;
        }
      } else if (c === "'") {
        quoted = true;
        wasQuoted = true;
      } else if (c === "," || c === ")") {
        row.push(!wasQuoted && value === "NULL" ? null : value);
        value = "";
        wasQuoted = false;
        if (c === ")") {
          i++;
          break;
        }
      } else {
        value += c;
      }
    }
    yield row;
  }
}

async function readTables(path, wanted) {
  let stream = createReadStream(path);
  if (path.endsWith(".gz")) stream = stream.pipe(createGunzip());
  const lines = createInterface({ input: stream, crlfDelay: Infinity });
  const columns = {};
  const rows = Object.fromEntries(wanted.map((t) => [t, []]));
  let creating = null;
  for await (const line of lines) {
    const create = line.match(/^CREATE TABLE `([^`]+)`/);
    if (create) {
      creating = wanted.includes(create[1]) ? create[1] : null;
      if (creating) columns[creating] = [];
      continue;
    }
    if (creating) {
      const column = line.match(/^\s+`([^`]+)`/);
      if (column) columns[creating].push(column[1]);
      else if (/^\)/.test(line)) creating = null;
      continue;
    }
    const insert = line.match(/^INSERT INTO `([^`]+)`/);
    if (insert && wanted.includes(insert[1])) {
      const table = insert[1];
      const names = columns[table];
      const valuesAt = line.indexOf("VALUES") + 6;
      for (const raw of parseTuples(line, valuesAt)) {
        const row = {};
        names.forEach((name, k) => (row[name] = raw[k]));
        rows[table].push(row);
      }
    }
  }
  return rows;
}

// --- Build ------------------------------------------------------------------

const tables = await readTables(input, [
  "creature_template", "creature", "creature_spawn_entry", "spawn_group_entry", "spawn_group_spawn",
]);
for (const [name, rows] of Object.entries(tables)) console.error(`${name}: ${rows.length} rows`);

// Leftovers in the client data that never appear in the game.
const UNUSED = /\[UNUSED\]|\btest\b/i;

const beasts = new Map();
for (const t of tables.creature_template) {
  const family = FAMILIES[Number(t.Family)];
  if (!family || Number(t.CreatureType) !== CREATURE_TYPE_BEAST) continue;
  if ((Number(t.CreatureTypeFlags) & TYPEFLAG_TAMEABLE) === 0) continue;
  if (UNUSED.test(t.Name)) continue;
  const looks = [t.ModelId1, t.ModelId2, t.ModelId3, t.ModelId4].map(Number).filter((id) => id > 0);
  beasts.set(Number(t.Entry), {
    id: Number(t.Entry),
    name: t.Name,
    subName: t.SubName || null,
    family,
    minLevel: Number(t.MinLevel),
    maxLevel: Number(t.MaxLevel),
    rank: Number(t.Rank),
    attackTime: Number(t.MeleeBaseAttackTime),
    school: Number(t.DamageSchool),
    looks: [...new Set(looks)],
    spawns: 0,
    spawn: null,
    respawnMin: Infinity,
    respawnMax: 0,
  });
}

// Count a spawn point for a beast. The first open-world point (maps 0 and 1)
// becomes its representative point, else the first point anywhere.
function addSpawn(entry, c) {
  const beast = beasts.get(entry);
  if (!beast || !c) return;
  beast.spawns++;
  beast.respawnMin = Math.min(beast.respawnMin, Number(c.spawntimesecsmin));
  beast.respawnMax = Math.max(beast.respawnMax, Number(c.spawntimesecsmax));
  const map = Number(c.map);
  const openWorld = map === 0 || map === 1;
  if (!beast.spawn || (openWorld && !beast.spawn.openWorld)) {
    beast.spawn = { map, x: Number(c.position_x), y: Number(c.position_y), openWorld };
  }
}

const spawnByGuid = new Map();
for (const c of tables.creature) {
  spawnByGuid.set(Number(c.guid), c);
  addSpawn(Number(c.id), c); // id 0: the creature is picked from the tables below
}
// A spawn point that picks one of several creatures.
for (const e of tables.creature_spawn_entry) {
  addSpawn(Number(e.entry), spawnByGuid.get(Number(e.guid)));
}
// Spawn groups: any creature of the group can appear at any of its points.
const groupGuids = new Map();
for (const s of tables.spawn_group_spawn) {
  if (!groupGuids.has(s.Id)) groupGuids.set(s.Id, []);
  groupGuids.get(s.Id).push(Number(s.Guid));
}
for (const e of tables.spawn_group_entry) {
  for (const guid of groupGuids.get(e.Id) ?? []) {
    addSpawn(Number(e.Entry), spawnByGuid.get(guid));
  }
}

const list = [...beasts.values()].sort((a, b) => a.family.localeCompare(b.family) || a.name.localeCompare(b.name) || a.id - b.id);

if (statsOnly) {
  const byFamily = {};
  for (const b of list) {
    const f = (byFamily[b.family] ??= { npcs: 0, spawned: 0, rare: 0, looks: new Set() });
    f.npcs++;
    if (b.spawns > 0) f.spawned++;
    if (RARE_RANKS.has(b.rank)) f.rare++;
    b.looks.forEach((l) => f.looks.add(l));
  }
  for (const [family, f] of Object.entries(byFamily)) {
    console.log(`${family.padEnd(14)} npcs ${String(f.npcs).padStart(4)}  spawned ${String(f.spawned).padStart(4)}  rare ${String(f.rare).padStart(3)}  looks ${f.looks.size}`);
  }
  console.log(`total ${list.length} tameable NPCs, ${list.filter((b) => b.spawns > 0).length} with spawns`);
  process.exit(0);
}

// --- Lua output -------------------------------------------------------------

const lua = (s) => '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n") + '"';
const num = (n) => (Number.isInteger(n) ? String(n) : n.toFixed(1));

// Respawn times worth showing (rares and other slow spawns), in seconds.
const RESPAWN_WORTH_SHOWING = 15 * 60;

// Unique (summoned) beasts can't be told apart from unspawned leftovers here,
// so they are marked by hand in Data/Overrides.lua.
function rarityFor(b) {
  return RARE_RANKS.has(b.rank) ? "rare" : "common";
}

const out = [];
out.push(`-- GENERATED by tools/import-classic-db.mjs. Do not edit by hand; put
-- corrections in Data/Overrides.lua.
--
-- Source: CMaNGOS classic-db (https://github.com/cmangos/classic-db), GPL v3.
-- World of Warcraft content is copyright Blizzard Entertainment.
-- Original Classic (1.12) tameable beasts; WoW Forever additions are learned
-- in game.
--
-- ns.Beasts[npcID] = {
--   name, sub     creature name and <subname> (enUS)
--   family        pet family
--   level         level, or { min, max }
--   rarity        "rare" (rare spawn) or "common"; Overrides.lua marks
--                 summoned beasts "unique"
--   elite         true for elites and bosses
--   speed         attack speed in seconds, when not the usual 2.0
--   school        damage school, when not physical
--   respawn       { min, max } respawn in seconds, for slow spawns (15 min+)
--   spawns        number of spawn points (0: summoned, scripted, or not
--                 spawned in the source database)
--   map, x, y     one spawn point (world coordinates); the addon works out
--                 the zone in game
--   looks         creature display IDs this NPC can appear with
-- }
local _, ns = ...

ns.Beasts = {`);
let family = null;
for (const b of list) {
  if (b.family !== family) {
    family = b.family;
    out.push(`    -- ${family}`);
  }
  const fields = [`name = ${lua(b.name)}`];
  if (b.subName) fields.push(`sub = ${lua(b.subName)}`);
  fields.push(`family = ${lua(b.family)}`);
  fields.push(b.minLevel === b.maxLevel ? `level = ${b.minLevel}` : `level = { ${b.minLevel}, ${b.maxLevel} }`);
  fields.push(`rarity = ${lua(rarityFor(b))}`);
  if (ELITE_RANKS.has(b.rank)) fields.push("elite = true");
  if (b.attackTime && b.attackTime !== 2000) fields.push(`speed = ${(b.attackTime / 1000).toFixed(2).replace(/0$/, "")}`);
  if (SCHOOLS[b.school]) fields.push(`school = ${lua(SCHOOLS[b.school])}`);
  fields.push(`spawns = ${b.spawns}`);
  if (b.spawns > 0 && b.respawnMax >= RESPAWN_WORTH_SHOWING) {
    fields.push(`respawn = { ${b.respawnMin}, ${b.respawnMax} }`);
  }
  if (b.spawn) fields.push(`map = ${b.spawn.map}, x = ${num(b.spawn.x)}, y = ${num(b.spawn.y)}`);
  fields.push(`looks = { ${b.looks.join(", ")} }`);
  out.push(`    [${b.id}] = { ${fields.join(", ")} },`);
}
out.push("}");
out.push("");
out.push("ns.Looks = {}");
out.push("");
writeFileSync(output, out.join("\n"));
console.error(`wrote ${list.length} beasts to ${output}`);
