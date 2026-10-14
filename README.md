# SeaM_Vehicles 1.0.0

A separate garage and per-vehicle equipment resource for the supplied SeaM_Core, SeaM_Target and SeaM_Inventory versions. The UI source is Svelte; `html/index.html` is the ready-to-use FiveM build. The garage follows the supplied parchment/ledger reference.

## Install

1. Back up your database. SeaM_Vehicles uses the SeaM_Inventory included in this pack for vessel holds (`OpenVehicleStash`, `GetStashItems`, `CloseVehicleStashes`) and for ammunition (`RemoveItem`, `AddItem`).
2. Import `SeaM_Vehicles/install/vehicles.sql` on a fresh install. For an existing install created before mounted weapons, import `SeaM_Vehicles/install/weapons.sql`. The resource also creates the ammunition table automatically if your DB user has CREATE permission. Existing vehicle rows are retained. Keep the existing `seam_inventories` table; installed vehicle holds use it.
3. Put `SeaM_Vehicles` in your resources folder. Configure garage locations, vehicle spawn model names, and exact equipment bones in `SeaM_Vehicles/shared/config.lua`.
4. Start in this order: `oxmysql`, `SeaM_Core`, `SeaM_Target`, `SeaM_Inventory`, `SeaM_Vehicles`. Start **SeaM_Vehicles** last.
5. In `Config.VehicleModels`, add your streamed vehicle model and its equipment bone names. These bones must exist in that vehicle's model; there are no spawned cannon, gun or box props and no offset fallback. A missing bone makes that equipment inaccessible from third-eye.
6. The four ammunition items below are already registered in `SeaM_Inventory/shared/items.lua`; `install/ammo_items.lua` is only a reference for ox_inventory users. Set `Config.AmmoInventory = 'ox'` only if you actually use ox_inventory; otherwise leave `seam`.

| Item name | Use | Shots per item |
| --- | --- | ---: |
| `seam_cannonball` | One cannon load | 1 |
| `seam_mg_box_small` | Small machine gun box | 30 |
| `seam_mg_box_medium` | Medium machine gun box | 75 |
| `seam_mg_box_large` | Large machine gun box | 150 |

The bundled SeaM_Inventory exposes `RemoveItem(source, itemName, 1)` and `AddItem(source, itemName, 1)`, which `server/ammo_inventory.lua` uses. If you swap in a different inventory, change only that file. An unavailable API refuses the load and leaves saved ammo untouched.

## Use

- Third-eye the garage point to open the Svelte register. Search/filter your vehicles, select a registration, launch it or store it nearby.
- `seamgive [player ID] [model] [land|boat] [optional label]` registers one vehicle to the loaded character. Requires Core admin group. Example: `/seamgive 12 marquis boat The Peregrine`.
- `seamfit [vehicle ID] [equipment key] [remove]` installs or removes equipment on *only that specific car or boat*. Examples: `/seamfit 24 deck_gun`, `/seamfit 24 forward_hold`, `/seamfit 24 forward_hold remove`. The equipment key and bone must first be configured under that vehicle's model. The ID is on its garage detail card. Removing a nonempty hold is blocked.
- Third-eye an installed cannon to load one `seam_cannonball`, then third-eye it again to aim. Move the mouse to aim, left mouse to fire and Backspace to leave. The cannonball has a visible local projectile, ballistic drop and an explosion at the collision point. Cannon charges are one per cannon mount.
- Third-eye a mounted machine gun to load one small, medium or large box. Each mount holds exactly one box at once; its remaining rounds and box type are saved for that specific vehicle and mount. Third-eye again to aim. Press **G** to toggle semi/automatic, hold left mouse in automatic mode, and press Backspace to leave. A partly used box stays loaded when the vehicle is stored or the resource restarts; load a new box once it is empty.
- Mount owners can load and fire. The server checks ownership, installed mount, vehicle entity, range, firing arc, aiming session, cooldown and saved rounds. The database decrements rounds before a shot event is sent. Removing a mount that still holds rounds is blocked.
- Cargo uses inventory IDs `vessel:<vehicle id>:<mount key>` for both cars and boats, preserving existing boat inventory IDs. Closing or storing a vehicle terminates open hold sessions. Every item move rechecks that vehicle, mount and proximity on the server. The default is owner-only cargo; `Config.VehicleStashesOwnerOnly` can be changed.

## Custom model bones

Use the vehicle's exact spawn name as the key in `Config.VehicleModels`, then give each available cannon, machine gun and hold a unique equipment key and its real vehicle bone name. Defining a position does not install it for every registration. Gun projectiles start at the bone; third-eye options appear when you stand near the configured bone on a vehicle with that equipment installed. The weapon or hold should already be part of the streamed vehicle model if you want it visible.

For example, add a custom boat in `shared/config.lua`:

```lua
Config.VehicleModels = {
    ['my_boat_spawn_name'] = {
        bow_cannon = { type = 'cannon', bone = 'bow_cannon' },
        port_cannon = { type = 'cannon', bone = 'port_cannon', heading = -90.0 },
        deck_gun = { type = 'machinegun', bone = 'deck_gun', cooldown = 160 },
        forward_hold = { type = 'stash', bone = 'forward_hold', slots = 40, maxWeight = 100000 },
    },
    ['my_custom_bike'] = { spawnType = 'bike' },
}
```

`heading` sets the firing direction relative to the vehicle's forward direction, in degrees. If omitted it is `0`. Default cooldowns are 3000 ms for cannons and 160 ms for machine guns. Holds default to 40 slots and 100000 grams. `spawnType` applies to land vehicles that need a server spawn type other than `automobile`.

Then grant two boats of the same model and fit only one registration:

```text
/seamgive 12 my_boat_spawn_name boat Red boat
/seamgive 12 my_boat_spawn_name boat Blue boat
/seamfit 24 deck_gun
```

Only ID `24` receives the machine gun. Replace every example bone with the exact name in your own streamed model. If an old registration already has equipment saved under a matching key, it will use the bone in the new model config; old saved per-vehicle bone overrides are ignored. Other saved keys remain in the database but are not available until you configure them for that model.

## Existing vehicle shop integration

From another **server** resource:

```lua
local id, plate = exports.SeaM_Vehicles:GrantVehicle(citizenid, 'marquis', 'boat', 'My boat')
local ok, err = exports.SeaM_Vehicles:InstallMount(id, 'forward_hold')
-- exports.SeaM_Vehicles:RemoveMount(id, 'forward_hold')
```

The ID is the identity. Cars and boats of the same model have separate installed equipment lists, ammunition and inventories. Registrations use unique plates, but holds are *never* keyed by plate. To add ten places to one vehicle, add ten different equipment keys and install those keys on that vehicle ID.

## Svelte development

```sh
cd SeaM_Vehicles/ui
npm ci
npm run build
```

The build embeds CSS and JavaScript in `html/index.html`; no Node runtime is needed on the game server. The browser-only `?preview=1` query string shows sample data for UI work. In FiveM the NUI is transparent until opened.

## Verification and limits

The Svelte production build and garage UI are carried over unchanged. This workspace has no running FiveM server, your SeaM_Inventory source or streamed custom vehicle models. Verify the item export contract, four item definitions, your exact bone names and firing headings, and impact behaviour in-game. The default ball model is GTA's `prop_bowling_ball`; set `Config.Weapons.cannon.projectileModel` to a streamed cannonball model for a more authentic shape. If the model is missing, a dark sphere marker is drawn. Vanilla `SeaM_Inventory` trunks still key by plate; installed holds and ammunition use the immutable vehicle ID. The garage saves common condition, colours, extras, mods, livery and fuel, but not every GTA damage decal or custom paint RGB value.
