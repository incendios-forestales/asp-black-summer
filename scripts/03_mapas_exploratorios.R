# Helpers y export stand-alone de los mapas exploratorios.
#
# El entregable principal es analysis/01_exploracion_nsw.qmd. Este script
# produce las mismas figuras como archivos sueltos en outputs/.
#
# Convención: mapas vectoriales se exportan en PNG (plot) + HTML (view).
# Mapas que contienen ráster se exportan SOLO en PNG: un raster nacional a 100 m
# (NVIS, FESM agregado) excede el límite de imagen que Leaflet embebe en HTML.
# Excepción: el Mapa 6 está enmascarado a las ASP y se agrega a resolución más
# gruesa para la vista interactiva, por lo que sí se exporta también en HTML.

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

# Reclasifica NVIS MVG a la presencia de eucalipto según su ecología de fuego.
#   Eucalipto esclerófilo (bosque/woodland): MVG 2,3,4,5,11 — combustible del
#     fuego de copa de alta severidad descrito por Barker et al. (2022).
#   Mallee (eucalipto): MVG 14,32 — régimen de fuego distinto (matorral árido);
#     se distingue aparte para no confundir el argumento combustible→severidad.
#   Resto (incl. eucalipto tropical MVG 12, atípico de NSW) → NA.
reclass_eucalipto <- function(r) {
  rcl <- matrix(c(2,1, 3,1, 4,1, 5,1, 11,1, 14,2, 32,2), ncol = 2, byrow = TRUE)
  veg <- terra::classify(r, rcl, others = NA)
  levels(veg) <- data.frame(value = c(1, 2),
                            clase = c("Eucalipto esclerófilo", "Mallee (eucalipto)"))
  veg
}

# Mapa 6: presencia de eucalipto DENTRO de las ASP — PNG + HTML
# El ráster reclasificado se recorta y enmascara a los polígonos CAPAD, de modo
# que solo se ve la vegetación de eucalipto que cae en áreas protegidas. El
# perímetro Black Summer (rojo) se superpone para leer el solape combustible↔fuego.
# Reaplica las categorías tras una operación de terra que las descarta (modal).
set_euc_levels <- function(r) {
  levels(r) <- data.frame(value = c(1, 2),
                          clase = c("Eucalipto esclerófilo", "Mallee (eucalipto)"))
  r
}
if (!is.null(nsw) && !is.null(capad) && !is.null(nvis)) {
  veg_euc <- reclass_eucalipto(nvis)
  capad_v <- terra::project(terra::vect(capad), veg_euc)
  veg_asp <- terra::mask(terra::crop(veg_euc, capad_v), capad_v)
  euc_pal <- c("#1b7837", "#b8a038")

  tmap::tmap_mode("plot")
  m6 <- tmap::tm_shape(nsw) + tmap::tm_borders(col = "grey60") +
        tmap::tm_shape(veg_asp) +
          tmap::tm_raster(col.scale = tmap::tm_scale_categorical(values = euc_pal),
                          col.legend = tmap::tm_legend(title = "Eucalipto en ASP")) +
        tmap::tm_shape(capad) + tmap::tm_borders(col = "grey30", lwd = 0.3)
  if (!is.null(niafed)) {
    m6 <- m6 + tmap::tm_shape(niafed) +
            tmap::tm_polygons(fill = "firebrick", fill_alpha = 0.25,
                              col = "firebrick", col_alpha = 0.5, lwd = 0.3) +
            tmap::tm_add_legend(type = "polygons", labels = "Perímetro Black Summer",
                                fill = "firebrick", fill_alpha = 0.25,
                                col = "firebrick", col_alpha = 0.5)
  }
  m6 <- m6 + tmap::tm_title("Eucalipto en ASP de NSW (NVIS MVG) y perímetro Black Summer")
  save_png(m6, "06_eucalipto_en_asp")

  # Versión interactiva: el ráster enmascarado se agrega (modal, factor 5 ≈ 500 m)
  # para que el overlay de imagen que Leaflet embebe en el HTML quede liviano.
  tmap::tmap_mode("view")
  veg_view <- set_euc_levels(terra::aggregate(veg_asp, fact = 5, fun = "modal",
                                              na.rm = TRUE))
  m6_view <- tmap::tm_shape(veg_view) +
               tmap::tm_raster(col.scale = tmap::tm_scale_categorical(values = euc_pal),
                               col.legend = tmap::tm_legend(title = "Eucalipto en ASP")) +
             tmap::tm_shape(capad_view) + tmap::tm_borders(col = "grey30", lwd = 0.5)
  if (!is.null(niafed_view)) {
    m6_view <- m6_view + tmap::tm_shape(niafed_view) +
                 tmap::tm_polygons(fill = "firebrick", fill_alpha = 0.2,
                                   col = "firebrick", col_alpha = 0.5, lwd = 0.5)
  }
  save_html(m6_view, "06_eucalipto_en_asp")
}

message("\nMapas exportados en: ", dir_figs, "  y  ", dir_maps)
