# Descarga de áreas silvestres protegidas — CAPAD 2020 Terrestrial.
# Collaborative Australian Protected Area Database (DCCEEW).
#
# Se usa la versión 2020 porque refleja el estado legal/espacial de las ASP
# durante el evento Black Summer. Las versiones más recientes (2022, 2024)
# introducirían desfase temporal.
#
# Portal: https://fed.dcceew.gov.au/datasets/erin::capad-2020-terrestrial
# Licencia: CC-BY 4.0.

source(here::here("R", "utils_geo.R"))

download_capad_2020 <- function(dir_raw = here::here("data", "raw", "capad")) {
  expect_manual_download(
    dir_destino = dir_raw,
    patron = "CAPAD.*2020.*\\.(shp|gpkg)$",
    portal_url = "https://fed.dcceew.gov.au/datasets/18fa96882848426cb1b778703f8137ab",
    notas = paste(
      "Bajar como 'Shapefile' desde el botón 'Download' del portal.",
      "Descomprimir en data/raw/capad/. Conservar el archivo .shp."
    )
  )
}
