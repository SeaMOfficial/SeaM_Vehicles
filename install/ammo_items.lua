-- Reference only; not loaded by fxmanifest.lua.
-- These four items are already registered in SeaM_Inventory/shared/items.lua
-- (bottom of the Items table), so nothing needs copying for the bundled inventory.
-- Only use this list if you run Config.AmmoInventory = 'ox' with ox_inventory.
return {
['seam_cannonball'] = { label = 'Cannonball', weight = 5000, stack = true, close = true },
['seam_mg_box_small'] = { label = 'Small machine gun box', weight = 2000, stack = true, close = true },
['seam_mg_box_medium'] = { label = 'Medium machine gun box', weight = 4000, stack = true, close = true },
['seam_mg_box_large'] = { label = 'Large machine gun box', weight = 8000, stack = true, close = true },
}
