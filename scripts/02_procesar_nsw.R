# Procesamiento: recorte a NSW y reproyección a EPSG:3577 (Australian Albers).
#
# Entrada: data/raw/<fuente>/ (ya descargado por 01_descargar_datos.R).
# Salida : data/processed/nsw_*.gpkg y data/processed/nsw_*.tif.
#
# Se ejecuta capa por capa con tryCatch para que el script completo avance
# aunque alguna fuente manual aún no esté descargada.

suppressPackageStartupMessages({
  library(here)
  library(sf)
  library(terra)
  library(glue)
})

source(here("R", "utils_geo.R"))
source(here("R", "download_asgs.R"))
source(here("R", "download_niafed.R"))
source(here("R", "download_capad.R"))
source(here("R", "download_nvis.R"))
source(here("R", "download_fesm.R"))

dir_processed <- here("data", "processed")
dir.create(dir_processed, recursive = TRUE, showWarnings = FALSE)

# 1. Límite NSW ----
message("Cargando y reproyectando límite NSW a EPSG:3577 ...")
nsw <- load_nsw_boundary() |> to_albers()
sf::st_write(nsw, file.path(dir_processed, "nsw_boundary.gpkg"),
             delete_dsn = TRUE, quiet = TRUE)
nsw_bbox <- sf::st_bbox(nsw)
message(glue("  NSW bbox (EPSG:3577): {paste(round(nsw_bbox, 0), collapse = ', ')}"))

# 2. NIAFED ---- Black Summer ----
# NIAFED v20200623 viene con geometrías 3D Measured (XYZM); hay que hacer st_zm()
# antes de st_make_valid. La versión es un MultiPolygon único que representa
# toda la extensión agregada del evento Black Summer (sin atributos per-evento).
# La recortamos geométricamente a NSW con st_intersection.
message("Procesando NIAFED (Black Summer 2019-2020) ...")
tryCatch({
  path_niafed <- download_niafed()
  niafed <- sf::st_read(path_niafed, quiet = TRUE) |>
    sf::st_zm() |>
    sf::st_make_valid() |>
    to_albers()
  niafed <- sf::st_intersection(niafed, nsw)
  niafed <- filter_black_summer(niafed)
  sf::st_write(niafed, file.path(dir_processed, "nsw_niafed_black_summer.gpkg"),
               delete_dsn = TRUE, quiet = TRUE)
  area_km2 <- round(as.numeric(sum(sf::st_area(niafed))) / 1e6)
  message(glue("  NIAFED NSW Black Summer: {nrow(niafed)} features, {format(area_km2, big.mark=',')} km²"))
}, error = function(e) message("  [SKIP] ", conditionMessage(e)))

# 3. CAPAD 2020 ----
message("Procesando CAPAD 2020 Terrestrial ...")
tryCatch({
  path_capad <- download_capad_2020()
  capad <- sf::st_read(path_capad, quiet = TRUE) |>
    sf::st_zm() |>
    sf::st_make_valid() |>
    to_albers() |>
    crop_to_nsw(nsw)
  keep_cols <- intersect(c("NAME", "TYPE", "IUCN", "GAZ_DATE", "AREA_KM2", "STATE"),
                        names(capad))
  capad <- capad[, keep_cols]
  sf::st_write(capad, file.path(dir_processed, "nsw_capad_2020.gpkg"),
               delete_dsn = TRUE, quiet = TRUE)
  message(glue("  CAPAD NSW: {nrow(capad)} features"))
}, error = function(e) message("  [SKIP] ", conditionMessage(e)))

# 4. NVIS MVG ----
message("Procesando NVIS MVG (recorte a NSW, 100 m) ...")
tryCatch({
  gdb_path <- download_nvis_mvg()
  uri <- nvis_subdataset_uri(gdb_path, layer = "MVG")
  nvis <- terra::rast(uri)
  # NVIS ya está en EPSG:3577 (_ALB). Solo recortar + enmascarar a NSW.
  if (terra::crs(nvis, describe = TRUE)$code != "3577") {
    nvis <- terra::project(nvis, PROJ_ALBERS, method = "near")
  }
  nvis_nsw <- terra::crop(nvis, terra::vect(nsw))
  nvis_nsw <- terra::mask(nvis_nsw, terra::vect(nsw))
  terra::writeRaster(nvis_nsw,
                     file.path(dir_processed, "nsw_nvis_mvg.tif"),
                     overwrite = TRUE, datatype = "INT1U")
  message("  NVIS NSW guardado.")
}, error = function(e) message("  [SKIP] ", conditionMessage(e)))

# 5. FESM severidad ----
# FESM viene a 10 m en GDA94 NSW Lambert (11 GB). Para los mapas exploratorios
# agregamos a 100 m (factor 10, clase modal) antes de reproyectar a Albers;
# el raster resultante pesa ~100 MB en vez de ~12 GB.
message("Procesando FESM 2019/20 (severidad: agregación 10 m → 100 m, reproj a Albers) ...")
tryCatch({
  path_fesm <- download_fesm_2019_20()
  fesm <- terra::rast(path_fesm)
  fesm_100 <- terra::aggregate(fesm, fact = 10, fun = "modal", na.rm = TRUE)
  fesm_alb <- terra::project(fesm_100, PROJ_ALBERS, method = "near")
  fesm_nsw <- terra::crop(fesm_alb, terra::vect(nsw))
  fesm_nsw <- terra::mask(fesm_nsw, terra::vect(nsw))
  terra::writeRaster(fesm_nsw,
                     file.path(dir_processed, "nsw_fesm_severity.tif"),
                     overwrite = TRUE, datatype = "INT1U")
  message("  FESM NSW (100 m) guardado.")
}, error = function(e) message("  [SKIP] ", conditionMessage(e)))

message("\nProcesamiento completado. Archivos en: ", dir_processed)
