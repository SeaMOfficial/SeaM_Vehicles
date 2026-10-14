-- Import on existing installs created before mounted weapons; no vehicle data is changed.
CREATE TABLE IF NOT EXISTS `seam_vehicle_ammo` (
  `vehicle_id` BIGINT UNSIGNED NOT NULL,
  `mount_key` VARCHAR(40) NOT NULL,
  `ammo_type` VARCHAR(40) NOT NULL,
  `rounds` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`vehicle_id`, `mount_key`),
  CONSTRAINT `seam_vehicle_ammo_vehicle_fk` FOREIGN KEY (`vehicle_id`)
    REFERENCES `seam_vehicles` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
