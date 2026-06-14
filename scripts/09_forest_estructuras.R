# Figura de síntesis del póster: forest plot del modelo M1 (script 08), con los
# predictores AGRUPADOS por las tres estructuras del paisaje (Miklós et al. 2019).
#
# Entrada : outputs/regresion_quemado_coeficientes.csv  (producido por script 08)
# Salida  : outputs/figs/09_forest_estructuras.png
#
# Idea: cada coeficiente estandarizado de M1 se traduce a un "odds ratio" por
# 1 desviación estándar (OR = exp(coef)); OR > 1 = más fuego, OR < 1 = menos,
# OR ≈ 1 = sin efecto. Los predictores se agrupan en las tres estructuras:
#   Primaria (relieve)    : pendiente, elevación, orientación norte
#   Secundaria (vegetación): % eucalipto
#   Terciaria (manejo/ASP) : estrictez IUCN
# El forest plot deja leer de un vistazo qué estructura manda el fuego.
#
# NOTA: los IC 95% se calculan como exp(coef ± 1.96·EE) y NO corrigen por
# autocorrelación espacial (pendiente). Son indicativos, no inferenciales finales.
#
# Ejecutar:  Rscript scripts/09_forest_estructuras.R

suppressPackageStartupMessages({
  library(here); library(dplyr); library(readr); library(ggplot2)
})

dir_figs <- here::here("outputs", "figs")
dir.create(dir_figs, recursive = TRUE, showWarnings = FALSE)

coef <- readr::read_csv(here::here("outputs", "regresion_quemado_coeficientes.csv"),
                        show_col_types = FALSE)

# --- Diccionario término -> etiqueta + estructura ---
mapa <- tibble::tribble(
  ~termino,      ~etiqueta,            ~estructura,
  "z_slope",     "Pendiente",          "Primaria · relieve",
  "z_elev",      "Elevación",          "Primaria · relieve",
  "z_north",     "Orientación norte",  "Primaria · relieve",
  "z_euc",       "% eucalipto",        "Secundaria · vegetación",
  "z_estrictez", "Estrictez IUCN",     "Terciaria · manejo (ASP)"
)
est_order <- c("Primaria · relieve", "Secundaria · vegetación", "Terciaria · manejo (ASP)")
est_cols  <- c("Primaria · relieve"       = "#8c6d31",
               "Secundaria · vegetación"  = "#2e7d32",
               "Terciaria · manejo (ASP)" = "#5e3c99")

# --- Preparar M1: OR por 1 DE + IC 95% ---
fp <- coef |>
  dplyr::filter(grepl("^M1", modelo), termino != "(Intercept)") |>
  dplyr::inner_join(mapa, by = "termino") |>
  dplyr::mutate(
    or    = exp(estimate),
    lo    = exp(estimate - 1.96 * std_error),
    hi    = exp(estimate + 1.96 * std_error),
    sig   = p_value < 0.05,
    estructura = factor(estructura, levels = est_order)
  ) |>
  dplyr::arrange(estructura, or) |>
  dplyr::mutate(etiqueta = factor(etiqueta, levels = etiqueta))   # orden y-axis

# Etiqueta de texto tipo "×7.4" / "×0.40"
fp$lab_or <- sprintf("×%.2g", fp$or)

# --- Forest plot ---
g <- ggplot(fp, aes(x = or, y = etiqueta, color = estructura)) +
  geom_vline(xintercept = 1, linetype = "dashed", color = "grey45") +
  geom_errorbar(aes(xmin = lo, xmax = hi), orientation = "y", width = 0.22, linewidth = 0.7) +
  geom_point(aes(shape = sig, fill = estructura), size = 4.2, stroke = 0.9) +
  geom_text(aes(label = lab_or), vjust = -1.1, size = 3.4, show.legend = FALSE) +
  facet_grid(estructura ~ ., scales = "free_y", space = "free_y", switch = "y") +
  scale_x_log10(breaks = c(0.25, 0.5, 1, 2, 4, 8),
                labels = c("0.25", "0.5", "1", "2", "4", "8")) +
  scale_color_manual(values = est_cols, guide = "none") +
  scale_fill_manual(values = est_cols, guide = "none") +
  scale_shape_manual(values = c(`TRUE` = 21, `FALSE` = 1),
                     labels = c(`TRUE` = "Significativo (p<0.05)", `FALSE` = "No significativo"),
                     name = NULL) +
  # La leyenda de forma hereda color/fill de las estructuras; forzamos gris neutro
  # para distinguir relleno (significativo) vs hueco (no significativo). override.aes
  # se aplica POR POSICIÓN, y el orden de la leyenda es FALSE (no sig.) luego TRUE.
  guides(shape = guide_legend(override.aes = list(
    fill = c(NA, "grey30"), color = "grey30", size = 4.2))) +
  labs(
    title = "Las tres estructuras del paisaje frente al fuego",
    subtitle = "ASP de NSW · Black Summer 2019-2020 · efecto sobre la probabilidad de quemarse",
    x = "Factor de cambio en la probabilidad de quemarse · por 1 desviación estándar\n(escala log · 1 = sin efecto)",
    y = NULL,
    caption = paste(
      "Regresión logística cuasi-binomial (GLM) por polígono ASP, ponderada por área (M1, script 08).",
      "Factor = razón de momios (odds ratio) por 1 DE = exp(coef); IC 95% = exp(coef ± 1.96·EE), sin corregir por autocorrelación espacial.",
      "Lectura: relieve y combustible (primaria + secundaria) mueven el fuego; la categoría de protección (terciaria), por sí sola, no.",
      sep = "\n")
  ) +
  theme_minimal(base_size = 12) +
  theme(
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank(),
    strip.placement = "outside",
    strip.text.y.left = element_text(angle = 0, face = "bold", hjust = 0),
    legend.position = "top",
    plot.title = element_text(face = "bold", size = 15),
    plot.caption = element_text(size = 8, color = "grey30", hjust = 0),
    plot.background = element_rect(fill = "white", color = NA),
    plot.margin = margin(10, 16, 10, 10)
  )

out <- file.path(dir_figs, "09_forest_estructuras.png")
ggsave(out, g, width = 10, height = 6.5, dpi = 200)
message("[png] ", out)
