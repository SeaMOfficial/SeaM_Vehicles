Config = {}

Config.Garages = {
    legion = { label = 'City Garage', kind = 'land',
        point = vector3(215.12, -810.45, 30.73),
        spawn = vector4(228.10, -804.80, 30.30, 158.0),
        storeRadius = 14.0 },
    marina = { label = 'Marina', kind = 'boat',
        point = vector3(-717.65, -1325.31, 1.60),
        spawn = vector4(-728.47, -1352.49, 0.10, 139.0),
        storeRadius = 30.0 },
}

Config.InteractDistance = 3.0
Config.StashDistance = 7.0
Config.MountAccessDistance = { land = 9.0, boat = 25.0 }
Config.VehicleStashesOwnerOnly = false
Config.AmmoInventory = 'seam'
Config.Weapons = {
    cannon = {
        item = 'seam_cannonball', label = 'Cannonball', capacity = 1,
        speed = 78.0, gravity = 9.81, range = 180.0,
        projectileModel = 'prop_bowling_ball', explosionType = 4,
        explosionScale = 0.75, yawLimit = 50.0, minPitch = -12.0, maxPitch = 28.0,
    },
    machinegun = {
        range = 125.0, damage = 12, yawLimit = 75.0,
        minPitch = -25.0, maxPitch = 35.0,
        boxes = {
            small = { item = 'seam_mg_box_small', label = 'Small box', rounds = 30 },
            medium = { item = 'seam_mg_box_medium', label = 'Medium box', rounds = 75 },
            large = { item = 'seam_mg_box_large', label = 'Large box', rounds = 150 },
        },
    },
}
-- Key: the exact vehicle spawn model. Each equipment key points to a bone
-- streamed with THAT vehicle model. Add as many cannons, guns or holds as needed.
-- This defines available positions; use /seamfit <vehicle ID> <equipment key>
-- to install one on an individual registration. No extra props are spawned.
-- Optional: heading (degrees from vehicle forward), cooldown (ms), label,
-- slots and maxWeight (grams) for holds, and spawnType for non-car land models.
Config.VehicleModels = {
    -- ['my_boat_spawn_name'] = {
    --     bow_cannon = { type = 'cannon', bone = 'bow_cannon' },
    --     port_cannon = { type = 'cannon', bone = 'port_cannon', heading = -90.0 },
    --     deck_gun = { type = 'machinegun', bone = 'deck_gun' },
    --     forward_hold = { type = 'stash', bone = 'forward_hold', slots = 40, maxWeight = 100000 },
    -- },
    -- ['my_bike_spawn_name'] = { spawnType = 'bike' },
}
