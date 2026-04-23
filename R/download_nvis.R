# Descarga de estructura secundaria (vegetación) — NVIS v7.0 MVG Extant.
# National Vegetation Information System (DCCEEW).
#
# El producto viene como File Geodatabase de ráster (.gdb/) con dos subdatasets:
#   NVIS7_0_AUST_EXT_MVG_ALB   — Major Vegetation Groups (33 clases) — USAR ÉSTE
#   NVIS7_0_AUST_EXT_MVS_ALB   — Major Vegetation Subgroups (85+ clases)
# Ambos a 100 m, proyectados en Australian Albers (EPSG:3577).
#
# Portal: https://www.dcceew.gov.au/environment/environment-information-australia/national-vegetation-information-system/data-products
# Link directo (raster extant): "Australia - Present Major Vegetation Groups and
# Subgroups - NVIS Version 7.0 Rasters Download".
# Licencia: CC-BY 4.0.

source(here::here("R", "utils_geo.R"))

# Busca la File Geodatabase descargada y descomprimida dentro de data/raw/nvis/.
# Devuelve el path al directorio .gdb (no a un .tif).
download_nvis_mvg <- function(dir_raw = here::here("data", "raw", "nvis")) {
  gdbs <- list.files(dir_raw, pattern = "\\.gdb$", recursive = TRUE,
                     full.names = TRUE, include.dirs = TRUE)
  gdbs <- gdbs[dir.exists(gdbs)]
  if (length(gdbs) == 0) {
    expect_manual_download(
      dir_destino = dir_raw,
      patron = "\\.gdb$",
      portal_url = "https://www.dcceew.gov.au/environment/environment-information-australia/national-vegetation-information-system/data-products",
      notas = paste(
        "Bajar 'Australia - Present Major Vegetation Groups and Subgroups -",
        "NVIS Version 7.0 Rasters Download'. Descomprimir; debe quedar una",
        "carpeta .gdb dentro de data/raw/nvis/."
      )
    )
  }
  gdbs[1]
}

# Retorna la URI GDAL que terra::rast() usa para abrir el subdataset MVG dentro
# del FGDB. Se usa también para MVS si se quisiera la versión de subgrupos.
nvis_subdataset_uri <- function(gdb_path, layer = c("MVG", "MVS")) {
  layer <- match.arg(layer)
  subset_name <- switch(layer,
    MVG = "NVIS7_0_AUST_EXT_MVG_ALB",
    MVS = "NVIS7_0_AUST_EXT_MVS_ALB"
  )
  sprintf('OpenFileGDB:"%s":%s', gdb_path, subset_name)
}
