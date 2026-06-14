# Tres paneles-mapa para el póster: las tres estructuras del paisaje (Miklós),
# en el MISMO estilo que el forest plot de síntesis (script 09) para que formen
# un set coherente arriba de él.
#
# Entrada : data/processed/{nsw_boundary, nsw_capad_2020}.gpkg
#           data/processed/{nsw_dem, nsw_nvis_mvg, nsw_fesm_severity}.tif
# Salida  : outputs/figs/10a_primaria_relieve.png      (DEM)
#           outputs/figs/10b_secundaria_vegetacion.png (eucalipto esclerófilo)
#           outputs/figs/10c_terciaria_asp_severidad.png (ASP × severidad del fuego)
#
# El fuego (severidad FESM) NO es una estructura: es el EVENTO que actúa sobre el
# paisaje. Aparece en el panel terciario porque ahí está la pregunta (ASP × fuego).
#
# Ejecutar:  Rscript scripts/10_paneles_estructuras.R

suppressPackageStartupMessages({
  library(here); library(sf); library(terra); library(ggplot2); library(tidyterra)
})

dir_processed <- here::here("data", "processed")
dir_figs      <- here::here("outputs", "figs")
dir.create(dir_figs, recursive = TRUE, showWarnings = FALSE)

# Colores de estructura, idénticos al script 09.
col_prim <- "#8c6d31"   # primaria · relieve
col_sec  <- "#2e7d32"   # secundaria · vegetación
col_terc <- "#5e3c99"   # terciaria · manejo (ASP)

# --- Datos ---
nsw    <- sf::st_read(file.path(dir_processed, "nsw_boundary.gpkg"), quiet = TRUE)
capad  <- sf::st_read(file.path(dir_processed, "nsw_capad_2020.gpkg"), quiet = TRUE)
niafed <- sf::st_read(file.path(dir_processed, "nsw_niafed_black_summer.gpkg"), quiet = TRUE)
dem   <- terra::rast(file.path(dir_processed, "nsw_dem.tif"))
nvis  <- terra::rast(file.path(dir_processed, "nsw_nvis_mvg.tif"))
fesm  <- terra::rast(file.path(dir_processed, "nsw_fesm_severity.tif"))

euc_codes <- c(2, 3, 4, 5, 11)   # eucalipto esclerófilo (igual que scripts 04/06/08)

# --- Tema y capa base compartidos ---
tema_panel <- function(accent) {
  theme_void(base_size = 12) +
    theme(
      plot.title    = element_text(face = "bold", size = 15, color = accent),
      plot.subtitle = element_text(size = 11, color = "grey25"),
      plot.caption  = element_text(size = 8, color = "grey35", hjust = 0),
      legend.position = "right",
      legend.title  = element_text(size = 10),
      legend.text   = element_text(size = 9),
      plot.background = element_rect(fill = "white", color = NA),
      plot.margin   = margin(8, 8, 8, 8)
    )
}
capa_nsw <- geom_sf(data = nsw, fill = "grey97", color = "grey60", linewidth = 0.3)

# Perímetro Black Summer (NIAFED) como contorno carbón, idéntico en los tres
# paneles: el mismo "evento" recurre sobre las tres estructuras. Carbón (no rojo)
# para no confundir con la severidad del panel terciario.
#
# NIAFED es la huella AGREGADA del evento: miles de parches pequeños cuyo contorno
# crudo se ve como ruido a escala estatal. Aplicamos un CIERRE MORFOLÓGICO
# (buffer +1.5 km -> union -> buffer -1.5 km) para fusionar parches cercanos en un
# perímetro legible, y simplificamos. Es una generalización para visualización, no
# cambia ningún análisis.
niafed_perim <- niafed |>
  sf::st_union() |>
  sf::st_buffer(1500) |>
  sf::st_buffer(-1500) |>
  sf::st_simplify(dTolerance = 400)

capa_perimetro <- list(
  geom_sf(data = niafed_perim, aes(color = "Perímetro Black Summer"),
          fill = NA, linewidth = 0.4),
  scale_color_manual(values = c("Perímetro Black Summer" = "#1a1a1a"), name = NULL)
)

guardar <- function(g, name, w = 8, h = 7) {
  out <- file.path(dir_figs, paste0(name, ".png"))
  ggsave(out, g, width = w, height = h, dpi = 200)
  message("[png] ", out)
}

# ============================================================
# Panel A — PRIMARIA · relieve (DEM)
# ============================================================
ramp_dem <- c("#2e5e3a", "#5e8c4e", "#a7c17f", "#e8d9a0", "#c9a05a",
              "#9c6b3f", "#7a5230", "#f2f2f2")
gA <- ggplot() +
  capa_nsw +
  tidyterra::geom_spatraster(data = dem, maxcell = 6e5) +
  geom_sf(data = nsw, fill = NA, color = "grey55", linewidth = 0.3) +
  capa_perimetro +
  scale_fill_gradientn(colours = ramp_dem, na.value = "transparent",
                       name = "Elevación\n(m s.n.m.)") +
  labs(title = "Primaria · relieve",
       subtitle = "Modelo de elevación (DEM) de Nueva Gales del Sur",
       caption = "Fuente: DEM SRTM vía elevatr (~600 m, zoom 8). EPSG:3577 (Australian Albers).") +
  tema_panel(col_prim)
guardar(gA, "10a_primaria_relieve")

# ============================================================
# Panel B — SECUNDARIA · vegetación (eucalipto esclerófilo)
# ============================================================
# Reclasifica NVIS MVG en dos clases: eucalipto esclerófilo vs otra vegetación.
is_euc <- terra::ifel(nvis %in% euc_codes, 1L, 0L)
levels(is_euc) <- data.frame(value = c(0L, 1L),
                             clase = c("Otra vegetación", "Eucalipto esclerófilo"))
names(is_euc) <- "clase"
gB <- ggplot() +
  capa_nsw +
  tidyterra::geom_spatraster(data = is_euc, maxcell = 6e5) +
  geom_sf(data = nsw, fill = NA, color = "grey55", linewidth = 0.3) +
  capa_perimetro +
  scale_fill_manual(values = c("Eucalipto esclerófilo" = col_sec,
                               "Otra vegetación" = "grey85"),
                    na.value = "transparent", name = NULL,
                    na.translate = FALSE) +
  labs(title = "Secundaria · vegetación",
       subtitle = "Eucalipto esclerófilo (combustible clave)",
       caption = paste("Fuente: NVIS v7.0 MVG (DCCEEW). Eucalipto esclerófilo =",
                       "grupos MVG 2, 3, 4, 5 y 11.")) +
  tema_panel(col_sec)
guardar(gB, "10b_secundaria_vegetacion")

# ============================================================
# Panel C — TERCIARIA · manejo (ASP) × severidad del fuego
# ============================================================
# La estructura terciaria (ASP) confrontada con el EVENTO (severidad FESM).
# Severidad: 0 = no quemado/NoData -> NA; 2..5 = baja..extrema.
sev <- terra::ifel(fesm < 2, NA, fesm)
levels(sev) <- data.frame(value = c(2L, 3L, 4L, 5L),
                          clase = c("Baja", "Moderada", "Alta", "Extrema"))
names(sev) <- "Severidad"
sev_cols <- c("Baja" = "#fed976", "Moderada" = "#fd8d3c",
              "Alta" = "#e31a1c", "Extrema" = "#800026")
gC <- ggplot() +
  capa_nsw +
  geom_sf(data = capad, fill = col_terc, color = NA, alpha = 0.18) +
  tidyterra::geom_spatraster(data = sev, maxcell = 6e5) +
  geom_sf(data = capad, fill = NA, color = col_terc, linewidth = 0.12) +
  geom_sf(data = nsw, fill = NA, color = "grey55", linewidth = 0.3) +
  capa_perimetro +
  scale_fill_manual(values = sev_cols, na.value = "transparent",
                    name = "Severidad\ndel fuego", na.translate = FALSE) +
  labs(title = "Terciaria · manejo (ASP) × fuego",
       subtitle = "Áreas protegidas y severidad de Black Summer 2019-2020",
       caption = paste("Fuente: ASP = CAPAD 2020 (morado). Severidad = FESM 2019-20",
                       "(NSW SEED). El fuego es el evento, no una estructura.")) +
  tema_panel(col_terc)
guardar(gC, "10c_terciaria_asp_severidad")

message("\nTres paneles de estructura exportados en: ", dir_figs)
