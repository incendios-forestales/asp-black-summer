# Helpers y export stand-alone de los mapas exploratorios.
#
# El entregable principal es analysis/01_exploracion_nsw.qmd. Este script
# produce las mismas figuras como archivos sueltos en outputs/.
#
# Convención: mapas vectoriales se exportan en PNG (plot) + HTML (view).
# Mapas que contienen ráster se exportan SOLO en PNG: un raster nacional a 100 m
# (NVIS, FESM agregado) excede el límite de imagen que Leaflet embebe en HTML.

suppressPackageStartupMessages({
  library(here)
  library(sf)
  library(terra)
  library(tmap)
  library(dplyr)
})

source(here("R", "utils_geo.R"))

dir_processed <- here("data", "processed")
dir_figs      <- here("outputs", "figs")
dir_maps      <- here("outputs", "maps")
dir.create(dir_figs, recursive = TRUE, showWarnings = FALSE)
dir.create(dir_maps, recursive = TRUE, showWarnings = FALSE)

load_if_exists <- function(path, reader = sf::st_read) {
  if (!file.exists(path)) {
    message("[skip] ", basename(path), " no existe.")
    return(NULL)
  }
  reader(path, quiet = TRUE)
}

nsw     <- load_if_exists(file.path(dir_processed, "nsw_boundary.gpkg"))
niafed  <- load_if_exists(file.path(dir_processed, "nsw_niafed_black_summer.gpkg"))
capad   <- load_if_exists(file.path(dir_processed, "nsw_capad_2020.gpkg"))

# Versiones simplificadas para mapas interactivos (Leaflet embebe el GeoJSON
# crudo en el HTML; con NSW a escala estatal, la tolerancia de 200 m es
# imperceptible pero reduce vertices/tamaño del HTML en más de un orden de magnitud).
simplify_for_view <- function(x, keep = 0.05) {
  if (is.null(x)) return(NULL)
  rmapshaper::ms_simplify(x, keep = keep, keep_shapes = TRUE)
}
capad_view  <- simplify_for_view(capad,  keep = 0.05)
niafed_view <- simplify_for_view(niafed, keep = 0.10)
nvis    <- if (file.exists(file.path(dir_processed, "nsw_nvis_mvg.tif")))
             terra::rast(file.path(dir_processed, "nsw_nvis_mvg.tif")) else NULL
fesm    <- if (file.exists(file.path(dir_processed, "nsw_fesm_severity.tif")))
             terra::rast(file.path(dir_processed, "nsw_fesm_severity.tif")) else NULL

save_png <- function(tm, name, width = 2000, height = 1600) {
  png_path <- file.path(dir_figs, paste0(name, ".png"))
  tmap::tmap_save(tm, png_path, width = width, height = height, dpi = 200)
  message("[png]  ", png_path)
}

save_html <- function(tm, name) {
  html_path <- file.path(dir_maps, paste0(name, ".html"))
  tmap::tmap_save(tm, html_path)
  message("[html] ", html_path)
}

# Mapa 1: contexto (NSW + CAPAD por categoría IUCN) — vectorial, PNG + HTML
if (!is.null(nsw) && !is.null(capad)) {
  tmap::tmap_mode("plot")
  m1_plot <- tmap::tm_shape(nsw) + tmap::tm_borders() +
             tmap::tm_shape(capad) + tmap::tm_polygons(fill = "IUCN",
                                                        fill.legend = tmap::tm_legend(title = "IUCN")) +
             tmap::tm_title("NSW - Áreas silvestres protegidas (CAPAD 2020)")
  save_png(m1_plot, "01_contexto_asp_iucn")
  tmap::tmap_mode("view")
  m1_view <- tmap::tm_shape(nsw) + tmap::tm_borders() +
             tmap::tm_shape(capad_view) + tmap::tm_polygons(fill = "IUCN")
  save_html(m1_view, "01_contexto_asp_iucn")
}

# Mapa 2: amenaza (NIAFED Black Summer) — vectorial
if (!is.null(nsw) && !is.null(niafed)) {
  tmap::tmap_mode("plot")
  m2_plot <- tmap::tm_shape(nsw) + tmap::tm_borders() +
             tmap::tm_shape(niafed) + tmap::tm_polygons(fill = "firebrick",
                                                         fill_alpha = 0.6) +
             tmap::tm_title("NIAFED - Extensión Black Summer 2019-2020 en NSW")
  save_png(m2_plot, "02_amenaza_niafed")
  tmap::tmap_mode("view")
  m2_view <- tmap::tm_shape(nsw) + tmap::tm_borders() +
             tmap::tm_shape(niafed_view) + tmap::tm_polygons(fill = "firebrick",
                                                              fill_alpha = 0.5)
  save_html(m2_view, "02_amenaza_niafed")
}

# Mapa 3: intersección — vectorial
if (!is.null(nsw) && !is.null(capad) && !is.null(niafed)) {
  tmap::tmap_mode("plot")
  m3_plot <- tmap::tm_shape(nsw) + tmap::tm_borders() +
             tmap::tm_shape(capad) + tmap::tm_polygons(fill = "forestgreen",
                                                        fill_alpha = 0.4) +
             tmap::tm_shape(niafed) + tmap::tm_polygons(fill = "firebrick",
                                                         fill_alpha = 0.5) +
             tmap::tm_title("Intersección ASP (verde) x Black Summer (rojo)")
  save_png(m3_plot, "03_interseccion_amenaza_exposicion")
  tmap::tmap_mode("view")
  m3_view <- tmap::tm_shape(nsw) + tmap::tm_borders() +
             tmap::tm_shape(capad_view) + tmap::tm_polygons(fill = "forestgreen",
                                                             fill_alpha = 0.35) +
             tmap::tm_shape(niafed_view) + tmap::tm_polygons(fill = "firebrick",
                                                              fill_alpha = 0.5)
  save_html(m3_view, "03_interseccion_amenaza_exposicion")
}

# Mapa 4: NVIS — SOLO PNG (raster nacional excede límite Leaflet)
if (!is.null(nsw) && !is.null(nvis)) {
  tmap::tmap_mode("plot")
  m4 <- tmap::tm_shape(nvis) +
          tmap::tm_raster(col.scale = tmap::tm_scale_categorical(n.max = 33),
                          col.legend = tmap::tm_legend(title = "MVG", show = TRUE)) +
        tmap::tm_shape(nsw) + tmap::tm_borders() +
        tmap::tm_title("NVIS v7.0 - Major Vegetation Groups (NSW)")
  save_png(m4, "04_estructura_secundaria_nvis")
}

# Mapa 5: FESM — SOLO PNG
if (!is.null(nsw) && !is.null(fesm)) {
  tmap::tmap_mode("plot")
  m5 <- tmap::tm_shape(fesm) +
          tmap::tm_raster(col.scale = tmap::tm_scale_categorical(
                            values = c("#d9d9d9","#ffeda0","#feb24c","#fc4e2a","#800026")),
                          col.legend = tmap::tm_legend(title = "Severidad")) +
        tmap::tm_shape(nsw) + tmap::tm_borders() +
        tmap::tm_title("NSW FESM 2019/20 - Severidad (100 m agregado)")
  save_png(m5, "05_severidad_fesm")
}

message("\nMapas exportados en: ", dir_figs, "  y  ", dir_maps)
