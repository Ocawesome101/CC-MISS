# M.I.S.S.

The Mediocre Item Storage System, my attempt at an item storage system for ComputerCraft.  Features parallelization of peripheral operations and real-time type-to-search!

This should be fairly conducive to larger stack sizes and larger chest sizes (e.g. caches or iron chests).  These have not yet been tested.

Type to search in any menu.  MISS will automatically filter the available options, matching the search query as a Lua pattern.  Whether an option will show up is more or less equivalent to `option:lower():match(searchTerm:lower())`.

## Setup
You need one input/output chests and a whole bunch of storage chests on the same network, [like this](https://i.imgur.com/L5D1cAI.png).  Edit line 12, and change its ID to that of the input chest - with my setup, it's `minecraft:chest_21`.

## Pitfalls
MISS would benefit from not rebuilding the chest index as often as it does - with a lot of chests/items it takes a while.
