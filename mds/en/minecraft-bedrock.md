---
title: Minecraft Bedrock Edition
date: 2023-12-28 12:00:00
icon: minecraft
background: bg-[#3C3C3C]
tags:
  - minecraft
  - bedrock
  - pe
  - commands
  - cheats
  - game
categories:
  - Game
intro: A comprehensive reference for Minecraft Bedrock Edition (1.20.x) commands.
---

## Target Selectors

| Selector | Description |
| :--- | :--- |
| `@p` | Nearest player |
| `@r` | Random player |
| `@a` | All players |
| `@e` | All entities (mobs, items, etc.) |
| `@s` | The entity executing the command (Self) |
| `@c` | The player's agent (Education Edition/Code Builder) |

### Selector Arguments

| Argument | Example | Description |
| :--- | :--- | :--- |
| `type` | `@e[type=creeper]` | Selects entities of a specific type |
| `r` / `rm` | `@a[r=10]` | Selects within a max radius (`r`) or min radius (`rm`) |
| `c` | `@e[c=1]` | Limits the count of targets (nearest first) |
| `m` | `@a[m=creative]` | Selects players by gamemode |
| `l` / `lm` | `@a[lm=30]` | Selects by level max (`l`) or min (`lm`) |
| `name` | `@e[name="Bob"]` | Selects entities with a specific name tag |

## Core Commands

### Teleport (/tp)

Teleport entities to locations or other entities.

```mcfunction
# Teleport yourself to coordinates
/tp @s 100 64 -200

# Teleport yourself to another player
/tp @s "Player Name"

# Teleport relative to current position
/tp @s ~ ~10 ~

# Teleport with facing direction
/tp @s ~ ~ ~ facing @p
```

### Game Mode (/gamemode)

Changes the player's game mode.

```mcfunction
# Survival Mode (0)
/gamemode s
# or
/gamemode survival

# Creative Mode (1)
/gamemode c
# or
/gamemode creative

# Adventure Mode (2)
/gamemode a
# or
/gamemode adventure

# Spectator Mode (Experimental/New)
/gamemode spectator
```

### Give Items (/give)

Gives items to players.

```mcfunction
# Give a diamond sword
/give @s diamond_sword

# Give 64 stone
/give @s stone 64

# Give item with data value (Legacy/Some items)
# Syntax: /give <target> <item> [amount] [data] [components]
/give @s wool 1 14 (Red Wool)

# Give item with CanPlaceOn (Adventure mode)
/give @s stone 1 0 {"minecraft:can_place_on":{"blocks":["grass"]}}
```

### Experience (/xp)

Adds or levels up experience.

```mcfunction
# Add 5 levels
/xp 5L @s

# Add 100 points
/xp 100 @s
```

## World Management

### Time (/time)

Sets the world time.

```mcfunction
# Set to day
/time set day

# Set to night
/time set night

# Set specific tick
/time set 0
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
```

### Gamerules (/gamerule)

Sets global world rules.

| Rule | Description |
| :--- | :--- |
| `keepinventory` | Keep items on death (true/false) |
| `dodaylightcycle` | Toggle sun movement (true/false) |
| `domobspawning` | Toggle mob spawning (true/false) |
| `mobgriefing` | Toggle mob destruction (true/false) |
| `doweathercycle` | Toggle weather changes (true/false) |
| `commandblockoutput` | Toggle command block chat (true/false) |
| `showcoordinates` | Show coordinates on screen (true/false) |

```mcfunction
# Enable keep inventory
/gamerule keepinventory true

# Show coordinates
/gamerule showcoordinates true
```

## Entity & Block Manipulation

### Effect (/effect)

Manages status effects.

```mcfunction
# Give Speed II for 30 seconds
/effect @s speed 30 2

# Give Night Vision (hide particles)
/effect @s night_vision 10000 0 true

# Clear all effects
/effect @s clear
```

### Fill (/fill)

Fills a volume with blocks.

```mcfunction
# Fill region with dirt
/fill ~ ~ ~ ~5 ~5 ~5 dirt

# Replace only air with water
/fill ~-5 ~-5 ~-5 ~5 ~5 ~5 water 0 replace air

# Fill using block states
/fill ~ ~ ~ ~10 ~1 ~10 stone ["stone_type"="granite"]
```

### Setblock (/setblock)

Changes a specific block.

```mcfunction
# Place a redstone block
/setblock ~ ~-1 ~ redstone_block

# Destroy block and place air
/setblock 100 64 100 air 0 destroy
```

### Enchant (/enchant)

Enchants the held item.

```mcfunction
# Add Sharpness V
/enchant @s sharpness 5

# Add Unbreaking III
/enchant @s unbreaking 3
```

## Utility Commands

### Locate (/locate)

Finds the nearest biome or structure.

```mcfunction
# Find nearest village
/locate structure village

# Find nearest ancient city
/locate structure ancient_city
```

### Kill (/kill)

Removes entities.

```mcfunction
# Kill yourself
/kill @s

# Kill specific entity type
/kill @e[type=zombie]
```

### Ticking Area (/tickingarea)

Keeps chunks loaded even when no players are nearby.

```mcfunction
# Add a ticking area (radius 4 chunks)
/tickingarea add circle ~ ~ ~ 4 MyArea

# List all areas
/tickingarea list

# Remove an area
/tickingarea remove MyArea
```
