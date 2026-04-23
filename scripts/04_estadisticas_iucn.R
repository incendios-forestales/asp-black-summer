# Tabla cruzada IUCN × amenaza/exposición para ASP de NSW durante Black Summer.
#
# Entrada : data/processed/{nsw_capad_2020, nsw_niafed_black_summer}.gpkg y
#           nsw_{fesm_severity, nvis_mvg}.tif
# Salida  : outputs/tabla_iucn_amenaza_exposicion.csv
#           outputs/tabla_iucn_amenaza_exposicion.html
#
# Por cada categoría IUCN reporta: nº ASP, área total, hectáreas quemadas,
# % quemado, severidad modal, distribución de severidad (Low/Moderate/High/
# Extreme) y grupo de vegetación dominante (NVIS MVG).

suppressPackageStartupMessages({
  library(here); library(sf); library(terra); library(dplyr); library(tidyr)
  library(knitr); library(kableExtra); library(exactextractr); library(readr)
  library(purrr)
})

capad  <- sf::st_read(here::here("data/processed/nsw_capad_2020.gpkg"), quiet = TRUE)
niafed <- sf::st_read(here::here("data/processed/nsw_niafed_black_summer.gpkg"), quiet = TRUE)
fesm   <- terra::rast(here::here("data/processed/nsw_fesm_severity.tif"))
nvis   <- terra::rast(here::here("data/processed/nsw_nvis_mvg.tif"))

# --- Diccionarios ---
iucn_order <- c("Ia","Ib","II","III","IV","V","VI","NAS")
iucn_label <- c(
  Ia  = "Ia – Strict Nature Reserve",
  Ib  = "Ib – Wilderness Area",
  II  = "II – National Park",
  III = "III – Natural Monument",
  IV  = "IV – Habitat/Species Mgmt",
  V   = "V – Protected Landscape",
  VI  = "VI – Sustainable Use",
  NAS = "NAS – No asignado"
)
# FESM 2019/20 recoded: 0=unburnt/nodata, 2=low, 3=moderate, 4=high, 5=extreme
sev_label <- c("0" = "Unburnt/NoData", "2" = "Low", "3" = "Moderate",
               "4" = "High", "5" = "Extreme")

# --- Disolver CAPAD por IUCN ---
# Algunas geometrías CAPAD traen holes mal orientados; hacemos make_valid +
# buffer(0) por polígono antes de la unión para evitar TopologyException.
message("Reparando geometrías CAPAD antes de la unión ...")
capad <- capad |>
  sf::st_make_valid() |>
  sf::st_buffer(0)

message("Disolviendo CAPAD por categoría IUCN ...")
n_by_iucn <- capad |> sf::st_drop_geometry() |> count(IUCN, name = "n_features")
capad_by_iucn <- capad |>
  dplyr::group_by(IUCN) |>
  dplyr::summarise(.groups = "drop") |>
  sf::st_make_valid()
capad_by_iucn <- capad_by_iucn |>
  dplyr::left_join(n_by_iucn, by = "IUCN") |>
  dplyr::mutate(area_ha = as.numeric(sf::st_area(geom)) / 1e4)

# --- Intersección con NIAFED (Black Summer) ---
message("Calculando intersección con Black Summer ...")
burned_by_iucn <- sf::st_intersection(capad_by_iucn, niafed) |>
  sf::st_make_valid()
burned_by_iucn$burned_ha <- as.numeric(sf::st_area(burned_by_iucn)) / 1e4

# --- Distribución de severidad por clase (solo valores 2-5, excluye 0=NoData) ---
message("Calculando distribución de severidad ...")
sev_vals_list <- exactextractr::exact_extract(fesm, burned_by_iucn, progress = FALSE)
sev_long <- purrr::map2_dfr(sev_vals_list, burned_by_iucn$IUCN,
                             function(df, iuc) {
  df |>
    dplyr::filter(!is.na(value), value > 0) |>
    dplyr::group_by(value) |>
    dplyr::summarise(w = sum(coverage_fraction, na.rm = TRUE),
                     .groups = "drop") |>
    dplyr::mutate(IUCN = iuc)
}) |>
  dplyr::mutate(class = sev_label[as.character(value)]) |>
  dplyr::group_by(IUCN, class) |>
  dplyr::summarise(w = sum(w), .groups = "drop") |>
  dplyr::group_by(IUCN) |>
  dplyr::mutate(pct = round(100 * w / sum(w), 1)) |>
  dplyr::ungroup()

# Severidad modal = clase con mayor proporción dentro del área quemada (no 0)
sev_modal_tbl <- sev_long |>
  dplyr::group_by(IUCN) |>
  dplyr::slice_max(pct, n = 1, with_ties = FALSE) |>
  dplyr::ungroup() |>
  dplyr::select(IUCN, sev_modal = class)

sev_dist_wide <- sev_long |>
  dplyr::select(IUCN, class, pct) |>
  tidyr::pivot_wider(names_from = class, values_from = pct, values_fill = 0)

# --- MVG modal sobre el área total de cada categoría ---
message("Extrayendo MVG dominante (NVIS) ...")
mvg_modal_num <- exactextractr::exact_extract(nvis, capad_by_iucn,
                                               fun = "mode", progress = FALSE)
mvg_cats <- terra::cats(nvis)[[1]]
mvg_lookup <- setNames(mvg_cats$MVG_NAME, mvg_cats$Value)
mvg_modal <- mvg_lookup[as.character(mvg_modal_num)]

# --- Ensamblar ---
totales <- capad_by_iucn |>
  sf::st_drop_geometry() |>
  dplyr::mutate(mvg_modal = mvg_modal) |>
  dplyr::select(IUCN, n_features, area_ha, mvg_modal)

burned_stats <- burned_by_iucn |>
  sf::st_drop_geometry() |>
  dplyr::select(IUCN, burned_ha) |>
  dplyr::left_join(sev_modal_tbl, by = "IUCN")

tabla <- totales |>
  dplyr::left_join(burned_stats, by = "IUCN") |>
  dplyr::mutate(burned_ha = tidyr::replace_na(burned_ha, 0),
                pct_quemado = round(100 * burned_ha / area_ha, 1)) |>
  dplyr::left_join(sev_dist_wide, by = "IUCN") |>
  dplyr::mutate(IUCN_lbl = iucn_label[IUCN]) |>
  dplyr::arrange(factor(IUCN, levels = iucn_order))

# Columnas de severidad que existen
sev_cols <- intersect(c("Low", "Moderate", "High", "Extreme"), names(tabla))

tabla_out <- tabla |>
  dplyr::select(IUCN = IUCN_lbl,
                `N ASP` = n_features,
                `Área (ha)` = area_ha,
                `Quemado (ha)` = burned_ha,
                `% quemado` = pct_quemado,
                `Severidad modal` = sev_modal,
                dplyr::any_of(sev_cols),
                `MVG dominante` = mvg_modal)

# --- Exportar ---
dir_out <- here::here("outputs")
dir.create(dir_out, recursive = TRUE, showWarnings = FALSE)

csv_path <- file.path(dir_out, "tabla_iucn_amenaza_exposicion.csv")
readr::write_csv(tabla_out, csv_path)
message("CSV : ", csv_path)

html_path <- file.path(dir_out, "tabla_iucn_amenaza_exposicion.html")
fmt_num <- function(x) formatC(round(as.numeric(x)), format = "d", big.mark = ",")
tabla_fmt <- tabla_out |>
  dplyr::mutate(dplyr::across(c(`Área (ha)`, `Quemado (ha)`), fmt_num))
html_tbl <- knitr::kable(
  tabla_fmt, format = "html",
  caption = "NSW · ASP por categoría IUCN × Black Summer 2019-2020"
) |>
  kableExtra::kable_styling(
    bootstrap_options = c("striped", "hover", "condensed"),
    full_width = FALSE, position = "left"
  )
writeLines(as.character(html_tbl), html_path)
message("HTML: ", html_path)

cat("\n")
print(tabla_out)
