# Prototipo de mapas bivariados y heatmap-resumen para ASP de NSW (Black Summer).
#
# Entrada : data/processed/{nsw_capad_2020, nsw_boundary}.gpkg,
#           nsw_{fesm_severity, nvis_mvg}.tif y
#           outputs/tabla_iucn_amenaza_exposicion.csv (de scripts/04)
# Salida  : outputs/figs/06a_bivariado_exposicion_severidad.png
#           outputs/figs/06b_bivariado_eucalipto_severidad.png
#           outputs/figs/06c_heatmap_iucn_severidad.png
#
# Decisión de diseño (ver discusión): IUCN es una categoría de manejo (nominal),
# no una magnitud, así que NO se usa como eje de un bivariado. Los dos mapas
# bivariados cruzan magnitudes por polígono ASP (exposición/severidad/eucalipto);
# la relación IUCN×severidad e IUCN×eucalipto se resume en un heatmap categórico.
#
# Bivariado hecho a mano con ggplot2 (sin biscale, para no añadir dependencias):
# cada eje se parte en TERCILES (ntile) y la grilla 3x3 se mapea a 9 colores.
#
# Ejecutar:  Rscript scripts/06_mapas_bivariados.R

suppressPackageStartupMessages({
  library(here); library(sf); library(terra); library(dplyr)
  library(tidyr); library(readr); library(ggplot2); library(exactextractr)
})

dir_figs <- here::here("outputs", "figs")
dir.create(dir_figs, recursive = TRUE, showWarnings = FALSE)

# Eucalipto esclerófilo (combustible clave, Barker et al. 2022): MVG 2,3,4,5,11.
euc_codes <- c(2, 3, 4, 5, 11)

# Paleta bivariada 3x3 ("x-y"): x crece →, y crece ↑; esquina 3-3 = alto-alto.
biv_pal <- c(
  "1-1" = "#e8e8e8", "2-1" = "#ace4e4", "3-1" = "#5ac8c8",
  "1-2" = "#dfb0d6", "2-2" = "#a5add3", "3-2" = "#5698b9",
  "1-3" = "#be64ac", "2-3" = "#8c62aa", "3-3" = "#3b4994"
)

# --- Datos ---
capad <- sf::st_read(here::here("data/processed/nsw_capad_2020.gpkg"), quiet = TRUE) |>
  sf::st_make_valid() |>
  sf::st_buffer(0)
capad <- capad[!sf::st_is_empty(capad), ]
nsw   <- sf::st_read(here::here("data/processed/nsw_boundary.gpkg"), quiet = TRUE) |>
  sf::st_transform(sf::st_crs(capad))
fesm  <- terra::rast(here::here("data/processed/nsw_fesm_severity.tif"))
nvis  <- terra::rast(here::here("data/processed/nsw_nvis_mvg.tif"))

# --- Estadística zonal por POLÍGONO (no por categoría disuelta) ---
# FESM: % del polígono quemado (clases 2-5 sobre celdas válidas) y, dentro de lo
# quemado, % en severidad alta+extrema (clases 4-5). sev_he = NA si no ardió.
message("Extrayendo severidad por polígono (FESM) ...")
vf <- exactextractr::exact_extract(fesm, capad, progress = FALSE)
fstats <- do.call(rbind, lapply(vf, function(df) {
  v <- df$value; w <- df$coverage_fraction; ok <- !is.na(v)
  tot <- sum(w[ok]); b <- sum(w[ok & v >= 2]); he <- sum(w[ok & v >= 4])
  c(pct_burned = if (tot > 0) 100 * b / tot else NA_real_,
    sev_he     = if (b   > 0) 100 * he / b else NA_real_)
}))
rm(vf)

# NVIS: % de eucalipto esclerófilo sobre celdas válidas del polígono.
message("Extrayendo % eucalipto por polígono (NVIS) ...")
vn <- exactextractr::exact_extract(nvis, capad, progress = FALSE)
pct_euc <- vapply(vn, function(df) {
  v <- df$value; w <- df$coverage_fraction; ok <- !is.na(v); tot <- sum(w[ok])
  if (tot > 0) 100 * sum(w[ok & v %in% euc_codes]) / tot else NA_real_
}, numeric(1))
rm(vn)

capad$pct_burned <- fstats[, "pct_burned"]
capad$sev_he     <- fstats[, "sev_he"]
capad$pct_euc    <- pct_euc
message(sprintf("Polígonos: %d (con área quemada: %d)",
                nrow(capad), sum(!is.na(capad$sev_he))))

# --- Constructor de mapa bivariado a mano ---
# xvar/yvar continuos -> terciles -> grilla 3x3. Los polígonos sin las dos
# variables (p. ej. no quemados, sev_he = NA) se dibujan como contexto gris.
make_legend <- function(xlab, ylab) {
  dd <- expand.grid(x = 1:3, y = 1:3)
  dd$key <- paste(dd$x, dd$y, sep = "-")
  ggplot(dd, aes(x, y, fill = key)) +
    geom_tile(color = "white", linewidth = 0.4) +
    scale_fill_manual(values = biv_pal) +
    labs(x = xlab, y = ylab) + coord_fixed() +
    theme(legend.position = "none", panel.background = element_blank(),
          panel.grid = element_blank(), axis.text = element_blank(),
          axis.ticks = element_blank(), axis.title = element_text(size = 9),
          axis.title.y = element_text(angle = 90),
          plot.background = element_rect(fill = "white", color = NA),
          plot.margin = margin(3, 3, 3, 3))
}

bivariate_map <- function(data, xvar, yvar, xlab, ylab, title, caption, file) {
  d <- data
  d$.x <- d[[xvar]]; d$.y <- d[[yvar]]
  ok  <- !is.na(d$.x) & !is.na(d$.y)
  biv <- d[ok, ]; ctx <- d[!ok, ]
  biv$key <- paste(dplyr::ntile(biv$.x, 3), dplyr::ntile(biv$.y, 3), sep = "-")

  bb <- sf::st_bbox(nsw); w <- bb["xmax"] - bb["xmin"]; h <- bb["ymax"] - bb["ymin"]
  leg <- make_legend(xlab, ylab)
  g <- ggplot() +
    geom_sf(data = nsw, fill = "white", color = "grey75", linewidth = 0.25) +
    geom_sf(data = ctx, fill = "grey88", color = NA) +
    geom_sf(data = biv, aes(fill = key), color = NA) +
    scale_fill_manual(values = biv_pal, guide = "none") +
    annotation_custom(ggplot2::ggplotGrob(leg),
                      xmin = bb["xmin"], xmax = bb["xmin"] + 0.32 * w,
                      ymin = bb["ymin"], ymax = bb["ymin"] + 0.32 * h) +
    labs(title = title, caption = caption) +
    theme_void() +
    theme(plot.title = element_text(face = "bold", size = 13),
          plot.caption = element_text(size = 8, color = "grey30", hjust = 0),
          plot.background = element_rect(fill = "white", color = NA),
          plot.margin = margin(8, 8, 8, 8))
  ggsave(file.path(dir_figs, file), g, width = 9, height = 8, dpi = 200)
  message("[png] ", file)
}

# 06a: Exposición (% quemado) × Severidad (% alta+extrema). Gris = no ardió.
bivariate_map(
  capad, "pct_burned", "sev_he",
  xlab = "Exposición (% quemado) →", ylab = "Severidad (% alta+extrema) →",
  title = "ASP de NSW: Exposición × Severidad (Black Summer 2019-2020)",
  caption = paste("Terciles por polígono ASP. Gris = sin área quemada.",
                  "Esquina oscura = mucho quemado y muy severo."),
  file = "06a_bivariado_exposicion_severidad.png")

# 06b: Eucalipto (% esclerófilo) × Severidad. Solo ASP que ardieron.
bivariate_map(
  capad, "pct_euc", "sev_he",
  xlab = "Eucalipto esclerófilo (%) →", ylab = "Severidad (% alta+extrema) →",
  title = "ASP de NSW: Eucalipto × Severidad (solo ASP quemadas)",
  caption = paste("Terciles por polígono ASP quemado. Gris = sin área quemada.",
                  "Muestra co-ocurrencia combustible↔severidad, no correlación."),
  file = "06b_bivariado_eucalipto_severidad.png")

# --- 06c: heatmap-resumen IUCN × {exposición/combustible, severidad} ---
message("Construyendo heatmap IUCN ...")
csv <- readr::read_csv(here::here("outputs", "tabla_iucn_amenaza_exposicion.csv"),
                       show_col_types = FALSE)
sev_cols <- intersect(c("Low", "Moderate", "High", "Extreme"), names(csv))
cols <- c("% quemado", "% eucalipto", sev_cols)
orden_iucn <- csv[["IUCN"]]   # ya viene ordenada Ia..VI,NAS desde script 04

hm <- csv |>
  dplyr::select(IUCN, dplyr::all_of(cols)) |>
  tidyr::pivot_longer(-IUCN, names_to = "var", values_to = "val") |>
  dplyr::mutate(
    IUCN = factor(IUCN, levels = rev(orden_iucn)),
    var  = factor(var, levels = cols),
    grupo = ifelse(var %in% c("% quemado", "% eucalipto"),
                   "Exposición / combustible\n(% del área total)",
                   "Severidad (% del área quemada)"),
    grupo = factor(grupo, levels = c("Exposición / combustible\n(% del área total)",
                                     "Severidad (% del área quemada)")))

g3 <- ggplot(hm, aes(var, IUCN, fill = val)) +
  geom_tile(color = "white", linewidth = 0.6) +
  geom_text(aes(label = ifelse(is.na(val), "–", sprintf("%.0f", val)),
                color = val > 55), size = 3, show.legend = FALSE) +
  facet_grid(~ grupo, scales = "free_x", space = "free_x") +
  scale_fill_gradient(low = "#fff5eb", high = "#99000d", na.value = "grey90",
                      name = "%", limits = c(0, 100)) +
  scale_color_manual(values = c("FALSE" = "grey20", "TRUE" = "white")) +
  labs(title = "Resumen IUCN × amenaza/exposición — ASP de NSW",
       subtitle = "Black Summer 2019-2020",
       x = NULL, y = NULL,
       caption = paste("Severidad: % del área QUEMADA en cada clase.",
                       "% quemado y % eucalipto: % del área TOTAL de la categoría.")) +
  theme_minimal(base_size = 11) +
  theme(panel.grid = element_blank(),
        axis.text.x = element_text(angle = 30, hjust = 1),
        strip.text = element_text(face = "bold", size = 9),
        plot.title = element_text(face = "bold"),
        plot.caption = element_text(size = 8, color = "grey30", hjust = 0),
        plot.background = element_rect(fill = "white", color = NA))
ggsave(file.path(dir_figs, "06c_heatmap_iucn_severidad.png"), g3,
       width = 9, height = 5.5, dpi = 200)
message("[png] 06c_heatmap_iucn_severidad.png")

message("\nFiguras bivariadas exportadas en: ", dir_figs)
