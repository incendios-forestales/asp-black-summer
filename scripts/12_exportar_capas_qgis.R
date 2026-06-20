# Exporta capas (base + derivadas) listas para abrir y superponer en QGIS.
#
# Las capas base ya están en data/processed/ en formatos nativos de QGIS
# (GeoPackage y GeoTIFF, CRS GDA94 / Australian Albers EPSG:3577). Este script
# añade las capas DERIVADAS que hoy solo existen como PNG dentro de las figuras:
#
#   1. asp_bivariado.gpkg            -> polígonos ASP (CAPAD) con estadística zonal
#                                       por polígono: % quemado, % severidad
#                                       alta+extrema, % eucalipto esclerófilo, y
#                                       las clases bivariadas (terciles) de las
#                                       figuras 06a (exposición×severidad) y
#                                       06b (eucalipto×severidad).
#   2. asp_quemado_interseccion.gpkg -> intersección geométrica ASP × perímetro
#                                       Black Summer = la porción de cada área
#                                       protegida que efectivamente ardió.
#   3. eucalipto_en_asp.tif          -> NVIS reclasificado a presencia de
#                                       eucalipto (esclerófilo / mallee) y
#                                       recortado a las ASP (figura 06_eucalipto).
#
# Reusa la MISMA lógica que scripts/03 y scripts/06 para que las capas coincidan
# exactamente con lo que muestran las figuras.
#
# Ejecutar en el Docker del proyecto (paquetes en la imagen):
#   docker run --rm -v "$PWD":/home/rstudio/project -w /home/rstudio/project \
#     asp-black-summer:local Rscript --vanilla scripts/12_exportar_capas_qgis.R

suppressPackageStartupMessages({
  library(here); library(sf); library(terra); library(dplyr); library(exactextractr)
})

dp <- here::here("data", "processed")
stopifnot(dir.exists(dp))

# Eucalipto esclerófilo (combustible clave, Barker et al. 2022): MVG 2,3,4,5,11.
euc_codes <- c(2, 3, 4, 5, 11)

# Paleta bivariada 3x3 ("x-y"); idéntica a scripts/06.
biv_pal <- c(
  "1-1" = "#e8e8e8", "2-1" = "#ace4e4", "3-1" = "#5ac8c8",
  "1-2" = "#dfb0d6", "2-2" = "#a5add3", "3-2" = "#5698b9",
  "1-3" = "#be64ac", "2-3" = "#8c62aa", "3-3" = "#3b4994"
)

# --- Datos base ---
message("Cargando capas base ...")
capad <- sf::st_read(file.path(dp, "nsw_capad_2020.gpkg"), quiet = TRUE) |>
  sf::st_make_valid() |>
  sf::st_buffer(0)
capad <- capad[!sf::st_is_empty(capad), ]
niafed <- sf::st_read(file.path(dp, "nsw_niafed_black_summer.gpkg"), quiet = TRUE) |>
  sf::st_transform(sf::st_crs(capad)) |>
  sf::st_make_valid()
fesm <- terra::rast(file.path(dp, "nsw_fesm_severity.tif"))
nvis <- terra::rast(file.path(dp, "nsw_nvis_mvg.tif"))

# ============================================================================
# 1) Estadística zonal por polígono + clases bivariadas (figuras 06a/06b)
# ============================================================================
message("Extrayendo severidad por polígono (FESM) ...")
vf <- exactextractr::exact_extract(fesm, capad, progress = FALSE)
fstats <- do.call(rbind, lapply(vf, function(df) {
  v <- df$value; w <- df$coverage_fraction; ok <- !is.na(v)
  tot <- sum(w[ok]); b <- sum(w[ok & v >= 2]); he <- sum(w[ok & v >= 4])
  c(pct_burned = if (tot > 0) 100 * b / tot else NA_real_,
    sev_he     = if (b   > 0) 100 * he / b else NA_real_)
}))
rm(vf)

message("Extrayendo % eucalipto por polígono (NVIS) ...")
vn <- exactextractr::exact_extract(nvis, capad, progress = FALSE)
pct_euc <- vapply(vn, function(df) {
  v <- df$value; w <- df$coverage_fraction; ok <- !is.na(v); tot <- sum(w[ok])
  if (tot > 0) 100 * sum(w[ok & v %in% euc_codes]) / tot else NA_real_
}, numeric(1))
rm(vn)

capad$pct_burned <- fstats[, "pct_burned"]
capad$sev_he     <- fstats[, "sev_he"]
capad$pct_euc    <- pct_euc

# Clases bivariadas por terciles (ntile), igual que bivariate_map() en scripts/06.
add_biv <- function(d, xv, yv, prefix) {
  x <- d[[xv]]; y <- d[[yv]]; ok <- !is.na(x) & !is.na(y)
  tx <- ty <- rep(NA_integer_, nrow(d))
  tx[ok] <- dplyr::ntile(x[ok], 3)
  ty[ok] <- dplyr::ntile(y[ok], 3)
  key <- ifelse(ok, paste(tx, ty, sep = "-"), NA_character_)
  d[[paste0(prefix, "_key")]] <- key
  d[[paste0(prefix, "_col")]] <- unname(ifelse(is.na(key), NA_character_, biv_pal[key]))
  d
}
capad <- add_biv(capad, "pct_burned", "sev_he", "biv_expsev")  # fig 06a
capad <- add_biv(capad, "pct_euc",    "sev_he", "biv_eucsev")  # fig 06b

out1 <- file.path(dp, "asp_bivariado.gpkg")
sf::st_write(capad, out1, delete_dsn = TRUE, quiet = TRUE)
message(sprintf("[gpkg] %s  (%d polígonos, %d con área quemada)",
                basename(out1), nrow(capad), sum(!is.na(capad$sev_he))))

# ============================================================================
# 2) Intersección ASP × Black Summer (porción quemada de cada ASP)
# ============================================================================
message("Calculando intersección ASP × perímetro Black Summer ...")
fire <- sf::st_union(sf::st_geometry(niafed))
inter <- suppressWarnings(sf::st_intersection(capad, fire))
inter <- inter[!sf::st_is_empty(inter), ]
inter <- sf::st_make_valid(inter)
inter$area_quemada_ha <- as.numeric(sf::st_area(inter)) / 1e4
out2 <- file.path(dp, "asp_quemado_interseccion.gpkg")
sf::st_write(inter, out2, delete_dsn = TRUE, quiet = TRUE)
message(sprintf("[gpkg] %s  (%d fragmentos, %.0f ha)",
                basename(out2), nrow(inter), sum(inter$area_quemada_ha)))

# ============================================================================
# 3) Eucalipto dentro de las ASP (ráster, igual que scripts/03 mapa 6)
# ============================================================================
message("Reclasificando NVIS a eucalipto y recortando a ASP ...")
rcl <- matrix(c(2,1, 3,1, 4,1, 5,1, 11,1, 14,2, 32,2), ncol = 2, byrow = TRUE)
veg <- terra::classify(nvis, rcl, others = NA)
capad_v <- terra::project(terra::vect(capad), veg)
veg_asp <- terra::mask(terra::crop(veg, capad_v), capad_v)
levels(veg_asp) <- data.frame(value = c(1, 2),
                              clase = c("Eucalipto esclerófilo", "Mallee (eucalipto)"))
out3 <- file.path(dp, "eucalipto_en_asp.tif")
terra::writeRaster(veg_asp, out3, overwrite = TRUE, datatype = "INT1U", NAflag = 255)
message("[tif]  ", basename(out3))

message("\nCapas derivadas exportadas en: ", dp)
