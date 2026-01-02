---
title: Minecraft Java Edition
date: 2023-12-28 12:00:00
icon: minecraft
background: bg-[#5B8C5A]
tags:
  - minecraft
  - java
  - commands
  - cheats
  - game
categories:
  - Game
intro: A comprehensive reference for Minecraft Java Edition (1.20.x) commands.
---

## Target Selectors

| Selector | Description |
| :--- | :--- |
| `@p` | Nearest player |
| `@r` | Random player |
| `@a` | All players |
| `@e` | All entities (includes mobs, items, etc.) |
| `@s` | The entity executing the command (Self) |

### Selector Arguments

| Argument | Example | Description |
| :--- | :--- | :--- |
| `type` | `@e[type=skeleton]` | Selects entities of a specific type |
| `distance` | `@a[distance=..10]` | Selects within a radius (10 blocks) |
| `limit` | `@e[limit=1]` | Limits the number of targets selected |
| `sort` | `@a[sort=nearest]` | Sorts selection (nearest, furthest, random, arbitrary) |
| `gamemode` | `@a[gamemode=creative]` | Selects players in a specific gamemode |
| `level` | `@a[level=30..]` | Selects players with XP level 30 or higher |

## Core Commands

### Teleport (/tp)

Used to teleport entities to specific locations or other entities.

```mcfunction
# Teleport yourself to coordinates
/tp @s 100 64 -200

# Teleport yourself to another player
/tp @s PlayerName

# Teleport a specific player to you
/tp PlayerName @s

# Teleport relative to current position (~ is relative)
/tp @s ~ ~10 ~  (Moves 10 blocks up)

# Teleport with rotation (yaw pitch)
/tp @s ~ ~ ~ 90 0 (Faces South)
```

### Game Mode (/gamemode)

Changes the player's game mode.

```mcfunction
# Survival Mode
/gamemode survival

# Creative Mode
/gamemode creative

# Adventure Mode
/gamemode adventure

# Spectator Mode
/gamemode spectator

# Apply to other players
/gamemode creative @a[distance=..20]
```

### Give Items (/give)

Gives items to players.

```mcfunction
# Give a diamond sword
/give @s diamond_sword

# Give 64 stone
/give @s stone 64

# Give item with NBT data (Unbreakable diamond pickaxe)
/give @s diamond_pickaxe{Unbreakable:1b}
```

### Experience (/xp or /experience)

Adds or removes experience points/levels.

```mcfunction
# Add 5 levels
/xp add @s 5 levels

# Add 100 points
/xp add @s 100 points

# Query current level
/xp query @s levels
```

## World Management

### Time (/time)

Sets or queries the world time.

```mcfunction
# Set to day (1000 ticks)
/time set day

# Set to night (13000 ticks)
/time set night

# Set to noon (6000 ticks)
/time set noon

# Set to midnight (18000 ticks)
/time set midnight

# Add time (skip forward)
/time add 5000
```

### Weather (/weather)

Changes the weather.

```mcfunction
# Clear weather
/weather clear

# Rain
/weather rain

# Thunderstorm
/weather thunder

# Set duration (in seconds)
/weather clear 600
```

### Gamerules (/gamerule)

Sets various rules for the world.

| Rule | Description |
| :--- | :--- |
| `keepInventory` | If true, players keep items on death |
| `doDaylightCycle` | If false, time is frozen |
| `doMobSpawning` | If false, mobs won't spawn naturally |
| `mobGriefing` | If false, creepers/endermen won't destroy blocks |
| `doWeatherCycle` | If false, weather never changes |
| `commandBlockOutput` | If false, command blocks don't spam chat |

```mcfunction
# Enable keep inventory
/gamerule keepInventory true

# Disable phantom spawning
/gamerule doInsomnia false
```

## Entity & Block Manipulation

### Effect (/effect)

Manages status effects on entities.

```mcfunction
# Give Speed II for 30 seconds
/effect give @s speed 30 1

# Give Night Vision infinitely (hide particles)
/effect give @s night_vision infinite 0 true

# Clear all effects
/effect clear @s
```

### Fill (/fill)

Fills a region with a specific block.

```mcfunction
# Fill a 10x10x10 cube with stone
/fill ~ ~ ~ ~10 ~10 ~10 stone

# Replace only water with air (drain)
/fill ~-5 ~-5 ~-5 ~5 ~5 ~5 air replace water

# Create a hollow box of glass
/fill ~ ~ ~ ~5 ~5 ~5 glass outline
```

### Setblock (/setblock)

Changes a single block.

```mcfunction
# Place a torch at current location
/setblock ~ ~ ~ torch

# Destroy the block (drop item) and place stone
/setblock ~ ~-1 ~ stone destroy
```

### Enchant (/enchant)

Enchants the item currently held.

```mcfunction
# Add Sharpness V
/enchant @s sharpness 5

# Add Fortune III
/enchant @s fortune 3
```

## Utility Commands

### Locate (/locate)

Finds the nearest structure or biome.

```mcfunction
# Find nearest village
/locate structure village

# Find nearest cherry grove
/locate biome cherry_grove
```

### Kill (/kill)

Removes entities.

```mcfunction
# Kill yourself
/kill @s

# Kill all slimes
/kill @e[type=slime]

# Kill all items on the ground (cleanup)
/kill @e[type=item]
```

### Seed (/seed)

Displays the world seed.

```mcfunction
/seed
```
