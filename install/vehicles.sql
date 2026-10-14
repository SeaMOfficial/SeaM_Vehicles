CREATE TABLE IF NOT EXISTS `seam_vehicles` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `owner` VARCHAR(24) NOT NULL,
  `model` VARCHAR(40) NOT NULL,
  `plate` VARCHAR(8) NOT NULL,
  `label` VARCHAR(64) NOT NULL,
  `kind` ENUM('land','boat') NOT NULL,
  `spawn_type` VARCHAR(16) NOT NULL DEFAULT 'automobile',
  `properties` LONGTEXT DEFAULT NULL,
  `equipment` LONGTEXT DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `plate_unique` (`plate`),
  KEY `owner_kind` (`owner`, `kind`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
