# Descarga de límites administrativos de Australia (ABS ASGS Edition 3, 2021-2026).
# Nivel STE (State/Territory).
#
# Fuente:
#   Australian Bureau of Statistics — Australian Statistical Geography Standard (ASGS) Ed.3
#   https://www.abs.gov.au/statistics/standards/australian-statistical-geography-standard-asgs-edition-3
#
# Licencia: Creative Commons Attribution 4.0 International (CC-BY 4.0).

source(here::here("R", "utils_geo.R"))

download_asgs_ste <- function(dir_raw = here::here("data", "raw", "asgs")) {
  url <- paste0(
    "https://www.abs.gov.au/statistics/standards/australian-statistical-geography-standard-asgs-edition-3/",
    "jul2021-jun2026/access-and-downloads/digital-boundary-files/",
    "STE_2021_AUST_SHP_GDA2020.zip"
  )
  zip_path <- file.path(dir_raw, basename(url))
  download_if_missing(url, zip_path)
  exdir <- file.path(dir_raw, "STE_2021_AUST_SHP_GDA2020")
  unzip_if_needed(zip_path, exdir)
  shp <- list.files(exdir, pattern = "\\.shp$", full.names = TRUE)
  if (length(shp) == 0) stop("No se encontró el shapefile STE en ", exdir)
  shp[1]
}

# Carga el polígono de NSW. Idempotente.
load_nsw_boundary <- function() {
  shp <- download_asgs_ste()
  aust <- sf::st_read(shp, quiet = TRUE)
  nsw <- aust[aust$STE_NAME21 == "New South Wales", ]
  if (nrow(nsw) == 0) {
    stop("No se encontró 'New South Wales' en STE_NAME21. Campos disponibles: ",
         paste(names(aust), collapse = ", "))
  }
  nsw
}
