# Descarga de severidad de fuego NSW — FESM 2019/20.
# Fire Extent and Severity Mapping (NSW DPE + RFS).
#
# 5 clases (unburnt / low / moderate / high / extreme), raster 10 m derivado
# de Sentinel-2 por ML semi-automatizado.
#
# Portal: https://datasets.seed.nsw.gov.au/dataset/fire-extent-and-severity-mapping-fesm-2019-20
# Licencia: CC-BY 4.0.

source(here::here("R", "utils_geo.R"))

download_fesm_2019_20 <- function(dir_raw = here::here("data", "raw", "fesm")) {
  expect_manual_download(
    dir_destino = dir_raw,
    patron = "(?i)(fesm|cvmsre).*(2019|20192020).*\\.tif$",
    portal_url = "https://datasets.seed.nsw.gov.au/dataset/fire-extent-and-severity-mapping-fesm-2019-20",
    notas = paste(
      "Bajar el raster de severidad completo (GeoTIFF o IMG) desde el",
      "enlace 'Download' del portal SEED. Guardar en data/raw/fesm/."
    )
  )
}
