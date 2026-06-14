# Tríptico de la estructura primaria (relieve): las TRES derivadas del DEM que
# alimentan el modelo —elevación, pendiente y northness— en una fila 1×3.
#
# Es una alternativa más completa al panel 10a (que solo muestra la elevación):
# expone las tres covariables de terreno del forest plot (script 09). Pensado
# para la sección "Relieve" del reporte, donde hay espacio para verlas grandes.
#
# Entrada : data/processed/{nsw_boundary, nsw_niafed_black_summer}.gpkg
#           data/processed/{nsw_dem, nsw_slope, nsw_northness}.tif
# Salida  : outputs/figs/10a2_relieve_triptico.png
#
# Ejecutar:  Rscript scripts/11_relieve_triptico.R

suppressPackageStartupMessages({
  library(here); library(sf); library(terra); library(ggplot2)
  library(tidyterra); library(grid)
})

dir_processed <- here::here("data", "processed")
dir_figs      <- here::here("outputs", "figs")
dir.create(dir_figs, recursive = TRUE, showWarnings = FALSE)

col_prim <- "#8c6d31"   # acento de la estructura primaria (idéntico a 09/10)

# --- Datos ---
nsw    <- sf::st_read(file.path(dir_processed, "nsw_boundary.gpkg"), quiet = TRUE)
niafed <- sf::st_read(file.path(dir_processed, "nsw_niafed_black_summer.gpkg"), quiet = TRUE)
dem   <- terra::rast(file.path(dir_processed, "nsw_dem.tif"))
slope <- terra::rast(file.path(dir_processed, "nsw_slope.tif"))
north <- terra::rast(file.path(dir_processed, "nsw_northness.tif"))

# --- Preparación de escalas robustas y suavizado ---
# Muestra REGULAR (determinista, sin RNG) para cuantiles de recorte.
muestra <- function(r, n = 2e5)
  terra::spatSample(r, n, method = "regular", na.rm = TRUE)[, 1]

# Pendiente: tope al percentil 98 para que el oeste plano quede pálido y la
# escarpa oriental (la cola de valores altos) ocupe el extremo oscuro del color.
slope_cap <- as.numeric(stats::quantile(muestra(slope), 0.98, na.rm = TRUE))

# Northness: el raw oscila ±1 ladera a ladera -> moteado a escala estatal. Lo
# promediamos en una ventana de 15×15 celdas (~9 km) para revelar la TENDENCIA
# regional N-S del terreno. La media atenúa el rango, así que la escala se
# centra en su propio percentil 98 (no en ±1) para que el patrón sea visible.
north_s   <- terra::focal(north, w = 15, fun = "mean", na.rm = TRUE)
north_cap <- as.numeric(stats::quantile(abs(muestra(north_s)), 0.98, na.rm = TRUE))

# --- Capas base compartidas (mismo estilo que script 10) ---
capa_nsw <- geom_sf(data = nsw, fill = "grey97", color = "grey60", linewidth = 0.3)

# Perímetro Black Summer (NIAFED) con el mismo cierre morfológico que el set 10,
# para que el evento recurra también sobre las tres derivadas del relieve.
niafed_perim <- niafed |>
  sf::st_union() |>
  sf::st_buffer(1500) |>
  sf::st_buffer(-1500) |>
  sf::st_simplify(dTolerance = 400)
capa_perimetro <- list(
  geom_sf(data = niafed_perim, color = "#1a1a1a", fill = NA, linewidth = 0.35)
)

# Tema de cada sub-mapa: leyenda abajo, título de la variable en el acento primario.
tema_sub <- theme_void(base_size = 11) +
  theme(
    plot.title      = element_text(face = "bold", size = 12, color = col_prim, hjust = 0.5),
    legend.position = "bottom",
    legend.title    = element_text(size = 8),
    legend.text     = element_text(size = 7),
    legend.key.height = unit(0.25, "cm"),
    legend.key.width  = unit(0.9, "cm"),
    plot.margin     = margin(4, 6, 4, 6)
  )
guia_h <- guides(fill = guide_colorbar(title.position = "top", title.hjust = 0.5))

# --- Sub-mapa 1: ELEVACIÓN (gradiente de terreno, igual que 10a) ---
ramp_dem <- c("#2e5e3a", "#5e8c4e", "#a7c17f", "#e8d9a0", "#c9a05a",
              "#9c6b3f", "#7a5230", "#f2f2f2")
p_elev <- ggplot() +
  capa_nsw +
  tidyterra::geom_spatraster(data = dem, maxcell = 4e5) +
  geom_sf(data = nsw, fill = NA, color = "grey55", linewidth = 0.3) +
  capa_perimetro +
  scale_fill_gradientn(colours = ramp_dem, na.value = "transparent",
                       name = "Elevación (m s.n.m.)") +
  labs(title = "Elevación") + tema_sub + guia_h

# --- Sub-mapa 2: PENDIENTE (secuencial cálido; más pendiente = más oscuro) ---
p_slope <- ggplot() +
  capa_nsw +
  tidyterra::geom_spatraster(data = slope, maxcell = 4e5) +
  geom_sf(data = nsw, fill = NA, color = "grey55", linewidth = 0.3) +
  capa_perimetro +
  scale_fill_gradientn(colours = rev(grDevices::hcl.colors(7, "YlOrBr")),
                       limits = c(0, slope_cap), oob = scales::squish,
                       na.value = "transparent", name = "Pendiente (°)") +
  labs(title = "Pendiente") + tema_sub + guia_h

# --- Sub-mapa 3: NORTHNESS (DIVERGENTE: Sur ↔ Norte, centrada en 0) ---
# northness = cos(aspect): -1 = ladera al Sur, +1 = ladera al Norte. En el
# hemisferio sur las laderas al norte son más secas -> color cálido.
p_north <- ggplot() +
  capa_nsw +
  tidyterra::geom_spatraster(data = north_s, maxcell = 4e5) +
  geom_sf(data = nsw, fill = NA, color = "grey55", linewidth = 0.3) +
  capa_perimetro +
  scale_fill_gradient2(low = "#4575b4", mid = "grey95", high = "#b35806",
                       midpoint = 0, limits = c(-north_cap, north_cap),
                       oob = scales::squish,
                       breaks = c(-north_cap, 0, north_cap),
                       labels = c("Sur", "0", "Norte"),
                       na.value = "transparent", name = "Northness (media ~9 km)") +
  labs(title = "Orientación (northness)") + tema_sub + guia_h

# --- Ensamblar 1×3 con grid base (sin dependencias extra) ---
# Título y subtítulo arriba, los tres mapas en una banda central, fuente abajo.
out <- file.path(dir_figs, "10a2_relieve_triptico.png")
grDevices::png(out, width = 12, height = 5, units = "in", res = 200)
grid::grid.newpage()
grid::grid.rect(gp = grid::gpar(fill = "white", col = NA))
grid::grid.text("Primaria · relieve · derivadas del DEM",
                x = 0.012, y = 0.955, just = c("left", "top"),
                gp = grid::gpar(fontface = "bold", cex = 1.35, col = col_prim))
grid::grid.text(paste("Elevación, pendiente y orientación de las laderas (Nueva Gales del Sur).",
                      "Northness suavizado a ~9 km para mostrar la tendencia regional."),
                x = 0.012, y = 0.885, just = c("left", "top"),
                gp = grid::gpar(cex = 0.9, col = "grey25"))
grid::grid.text("Fuente: DEM SRTM vía elevatr (~600 m, zoom 8). EPSG:3577 (Australian Albers).",
                x = 0.012, y = 0.02, just = c("left", "bottom"),
                gp = grid::gpar(cex = 0.7, col = "grey35"))
grid::pushViewport(grid::viewport(x = 0.5, y = 0.45, width = 1, height = 0.80))
grid::pushViewport(grid::viewport(layout = grid::grid.layout(1, 3)))
print(p_elev,  vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 1))
print(p_slope, vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 2))
print(p_north, vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 3))
grDevices::dev.off()
message("[png] ", out)
