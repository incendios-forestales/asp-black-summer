# Descarga de estructura primaria (relieve) — GA 1 second SRTM-derived DEM.
# Geoscience Australia / Elevation Information System (ELVIS).
#
# DEM ~30 m nacional. Para NSW solo necesitamos una ventana recortada al
# bounding box estatal.
#
# Portal: https://elevation.fsdf.org.au/  o  https://data.gov.au (dataset 9a9284b6-eb45-4a13-97d0-91bf25f1187b)
# Licencia: CC-BY 4.0.

source(here::here("R", "utils_geo.R"))

download_dem_nsw <- function(dir_raw = here::here("data", "raw", "dem")) {
  expect_manual_download(
    dir_destino = dir_raw,
    patron = "(?i)(1sec|SRTM|DEM).*\\.(tif|vrt)$",
    portal_url = "https://elevation.fsdf.org.au/",
    notas = paste(
      "Desde ELVIS seleccionar el área de NSW y bajar 'Australia 1 Second",
      "DEM' en GeoTIFF. Guardar en data/raw/dem/. Para una primera",
      "iteración se puede usar solo un subset del bounding box de NSW."
    )
  )
}
