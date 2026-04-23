# Descarga de perímetros de incendios — NIAFED
# National Indicative Aggregated Fire Extent Dataset (DCCEEW).
#
# Portal: https://fed.dcceew.gov.au/datasets/erin::national-indicative-aggregated-fire-extent-dataset
# Licencia: CC-BY 4.0.
#
# El dataset está publicado como ArcGIS Hub item; la descarga directa de la
# geodatabase completa se hace desde el botón "Download" del portal.

source(here::here("R", "utils_geo.R"))

download_niafed <- function(dir_raw = here::here("data", "raw", "niafed")) {
  # El portal expone el archivo como FGDB o Shapefile. Si la URL directa del
  # portal cambia, el usuario descarga manualmente y este código lo reutiliza.
  expect_manual_download(
    dir_destino = dir_raw,
    patron = "NIAFED.*\\.(shp|gpkg)$",
    portal_url = "https://fed.dcceew.gov.au/datasets/erin::national-indicative-aggregated-fire-extent-dataset",
    notas = paste(
      "Bajar como 'Shapefile' o 'File Geodatabase'. Descomprimir en",
      "data/raw/niafed/. El pipeline busca cualquier .shp/.gpkg que",
      "haga match con 'NIAFED*'."
    )
  )
}

# Filtro para Black Summer 2019-2020 (ignición entre 1 jul 2019 y 31 mar 2020).
# Los campos típicos de NIAFED incluyen 'fire_season', 'ignition_date' o similares;
# el nombre exacto se detecta en tiempo de ejecución.
filter_black_summer <- function(niafed_sf) {
  nms <- tolower(names(niafed_sf))
  # Preferencia: campo de fecha/temporada; fallback a filtro por año
  date_col <- names(niafed_sf)[nms %in% c("ignition_d", "ignition_date", "start_date", "date_start")][1]
  season_col <- names(niafed_sf)[nms %in% c("fire_seaso", "fire_season", "season")][1]
  if (!is.na(date_col)) {
    d <- suppressWarnings(as.Date(niafed_sf[[date_col]]))
    keep <- !is.na(d) & d >= as.Date("2019-07-01") & d <= as.Date("2020-03-31")
    return(niafed_sf[keep, ])
  }
  if (!is.na(season_col)) {
    keep <- grepl("2019|2020", niafed_sf[[season_col]])
    return(niafed_sf[keep, ])
  }
  warning("NIAFED: no se encontró campo de fecha/temporada; devolviendo todo el dataset.")
  niafed_sf
}
