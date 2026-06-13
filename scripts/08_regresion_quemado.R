# Regresión: ¿la estrictez de protección IUCN sigue asociada al fuego DESPUÉS de
# controlar por terreno y vegetación?
#
# Entrada : data/processed/{nsw_capad_2020, nsw_niafed_black_summer}.gpkg
#           data/processed/{nsw_dem, nsw_slope, nsw_nvis_mvg}.tif
# Salida  : outputs/regresion_quemado_coeficientes.csv
#           impresión en consola con el resumen de los modelos
#
# MOTIVACIÓN
# Los scripts 05 y 07 corren correlaciones a nivel de CATEGORÍA IUCN (n = 7).
# Con esa n el resultado es frágil y, sobre todo, NO controla por la confusión
# obvia: las reservas estrictas (p.ej. Ib Wilderness) están en la escarpa
# boscosa oriental, la más expuesta a Black Summer. Para separar "estrictez" de
# "ubicación" subimos la unidad de análisis al POLÍGONO ASP individual (n de
# cientos) y metemos el terreno como covariable.
#
# MODELO
# Respuesta: proporción de área quemada del polígono (pct_quemado ∈ [0, 1]).
# Familia  : quasibinomial con weights = área (maneja proporciones acotadas y la
#            sobredispersión sin necesitar betareg ni paquetes extra).
# Predictores (estandarizados): elevación media, pendiente media, % eucalipto
#            esclerófilo y rango de estrictez IUCN (1 = Ia ... 7 = VI).
# Se ajustan dos modelos anidados para ver cuánto del "efecto estrictez"
# sobrevive al control por terreno+vegetación:
#   M0: quemado ~ estrictez                       (cruda, análoga al script 07)
#   M1: quemado ~ estrictez + elevación + pendiente + %eucalipto
#
# Ejecutar:  Rscript scripts/08_regresion_quemado.R

suppressPackageStartupMessages({
  library(here); library(sf); library(terra); library(dplyr)
  library(exactextractr); library(readr); library(tidyr)
})

# --- Cargar capas procesadas ---
capad  <- sf::st_read(here::here("data/processed/nsw_capad_2020.gpkg"), quiet = TRUE)
niafed <- sf::st_read(here::here("data/processed/nsw_niafed_black_summer.gpkg"), quiet = TRUE)
dem    <- terra::rast(here::here("data/processed/nsw_dem.tif"))
slope  <- terra::rast(here::here("data/processed/nsw_slope.tif"))
nvis   <- terra::rast(here::here("data/processed/nsw_nvis_mvg.tif"))

# Eucalipto esclerófilo: misma definición que scripts 04/06 (MVG 2,3,4,5,11).
euc_codes <- c(2, 3, 4, 5, 11)

# Rango de estrictez IUCN: 1 = más estricta ... 7 = menos estricta. NAS no rankeable.
estrictez <- c(Ia = 1, Ib = 2, II = 3, III = 4, IV = 5, V = 6, VI = 7)

# --- Preparar polígonos ASP ---
# Reparar geometrías (como en script 04) y quedarnos con un polígono = una fila.
message("Reparando geometrías CAPAD ...")
capad <- capad |>
  sf::st_make_valid() |>
  sf::st_buffer(0) |>
  dplyr::filter(!sf::st_is_empty(geom))
capad$poly_id <- seq_len(nrow(capad))
capad$area_ha <- as.numeric(sf::st_area(capad)) / 1e4
capad <- dplyr::filter(capad, area_ha > 0)

# --- Área quemada por polígono (intersección con NIAFED Black Summer) ---
# NOTA sobre la definición de "% quemado": el proyecto tiene dos.
#   (a) NIAFED — extensión geométrica del fuego (la usan scripts 04/07/06d). ESTA.
#   (b) FESM   — % de celdas en clases de severidad ≥2 (la usa 06a/b por polígono).
# El 08 es el análogo por polígono del 07 (estrictez vs % quemado), así que usamos
# la MISMA definición que el 07 (NIAFED) para que la narrativa sea coherente. Una
# variante con el pct_burned de FESM (06) es posible pero mediría otra cosa.
message("Calculando área quemada por polígono (intersección con NIAFED) ...")
niafed_u <- sf::st_union(niafed)
inter <- sf::st_intersection(capad[, c("poly_id", "geom")], niafed_u) |>
  sf::st_make_valid()
inter$burned_ha <- as.numeric(sf::st_area(inter)) / 1e4
burned_by_poly <- inter |>
  sf::st_drop_geometry() |>
  dplyr::group_by(poly_id) |>
  dplyr::summarise(burned_ha = sum(burned_ha), .groups = "drop")

# --- Terreno medio por polígono (elevación, pendiente) ---
message("Extrayendo elevación y pendiente medias por polígono ...")
capad$elev_mean  <- exactextractr::exact_extract(dem,   capad, fun = "mean", progress = FALSE)
capad$slope_mean <- exactextractr::exact_extract(slope, capad, fun = "mean", progress = FALSE)

# --- % eucalipto esclerófilo por polígono (coverage-weighted, igual que 04) ---
message("Calculando % de eucalipto esclerófilo por polígono ...")
veg_list <- exactextractr::exact_extract(nvis, capad, progress = FALSE)
capad$pct_euc <- vapply(veg_list, function(df) {
  df <- df[!is.na(df$value), ]
  tot <- sum(df$coverage_fraction)
  if (tot <= 0) return(NA_real_)
  100 * sum(df$coverage_fraction[df$value %in% euc_codes]) / tot
}, numeric(1))

# --- Ensamblar tabla de modelado ---
dat <- capad |>
  sf::st_drop_geometry() |>
  dplyr::left_join(burned_by_poly, by = "poly_id") |>
  dplyr::mutate(
    burned_ha   = tidyr::replace_na(burned_ha, 0),
    pct_quemado = pmin(pmax(burned_ha / area_ha, 0), 1),   # proporción ∈ [0,1]
    rank_estrictez = estrictez[as.character(IUCN)]
  ) |>
  dplyr::filter(!is.na(rank_estrictez),                    # descarta NAS
                !is.na(elev_mean), !is.na(slope_mean), !is.na(pct_euc))

message(sprintf("Polígonos ASP en el modelo: %d (de %d, tras excluir NAS y NA)",
                nrow(dat), nrow(capad)))

# Estandarizar predictores para coeficientes comparables.
z <- function(x) as.numeric(scale(x))
dat <- dat |>
  dplyr::mutate(
    z_estrictez = z(rank_estrictez),
    z_elev      = z(elev_mean),
    z_slope     = z(slope_mean),
    z_euc       = z(pct_euc)
  )

# --- Modelos quasibinomiales, ponderados por área ---
# weights = área en ha: polígonos grandes pesan más (la proporción de un parche
# minúsculo es ruidosa). Signo esperado de z_estrictez bajo la hipótesis
# "más estricta -> más quemada": NEGATIVO (menor rango = más estricta = más fuego).
m0 <- glm(pct_quemado ~ z_estrictez,
          family = quasibinomial, weights = area_ha, data = dat)
m1 <- glm(pct_quemado ~ z_estrictez + z_elev + z_slope + z_euc,
          family = quasibinomial, weights = area_ha, data = dat)

# Pseudo-R² de devianza para cada modelo.
pseudo_r2 <- function(m) 1 - m$deviance / m$null.deviance

resumen_coef <- function(m, etiqueta) {
  s <- summary(m)$coefficients
  data.frame(
    modelo    = etiqueta,
    termino   = rownames(s),
    estimate  = round(s[, "Estimate"], 4),
    std_error = round(s[, "Std. Error"], 4),
    statistic = round(s[, 3], 3),
    p_value   = round(s[, 4], 4),
    row.names = NULL
  )
}

coef_tbl <- dplyr::bind_rows(
  resumen_coef(m0, "M0: solo estrictez"),
  resumen_coef(m1, "M1: estrictez + terreno + vegetación")
)

# --- Exportar ---
dir_out <- here::here("outputs")
dir.create(dir_out, recursive = TRUE, showWarnings = FALSE)
csv_path <- file.path(dir_out, "regresion_quemado_coeficientes.csv")
readr::write_csv(coef_tbl, csv_path)

# --- Consola ---
cat("\n=========================================================\n")
cat("Regresión % quemado por polígono ASP (quasibinomial, w = área)\n")
cat("=========================================================\n")
cat(sprintf("\nn polígonos = %d\n", nrow(dat)))

cat("\n--- M0: quemado ~ estrictez ---\n")
print(round(summary(m0)$coefficients, 4))
cat(sprintf("Pseudo-R² (devianza): %.3f\n", pseudo_r2(m0)))

cat("\n--- M1: quemado ~ estrictez + elevación + pendiente + %eucalipto ---\n")
print(round(summary(m1)$coefficients, 4))
cat(sprintf("Pseudo-R² (devianza): %.3f\n", pseudo_r2(m1)))

b0 <- coef(m0)["z_estrictez"]; b1 <- coef(m1)["z_estrictez"]
cat(sprintf("\nCoef. estandarizado de estrictez:  M0 = %+.3f   →   M1 = %+.3f\n", b0, b1))
cat(sprintf("Cambio al controlar por terreno+vegetación: %+.1f%%\n",
            100 * (b1 - b0) / abs(b0)))
cat("\nLectura: si |z_estrictez| cae fuerte y pierde significancia al pasar de M0",
    "\na M1, la 'estrictez' del 07 era en buena parte confusión por ubicación",
    "\n(terreno) y combustible. El signo negativo esperado apoya 'más estricta ->",
    "\nmás quemada' SOLO si sobrevive al control. Resultado a nivel polígono:",
    "\nmás robusto que las correlaciones por categoría (n = 7), pero sigue siendo",
    "\nobservacional, no causal.\n")
cat(sprintf("\nCSV de coeficientes: %s\n", csv_path))
