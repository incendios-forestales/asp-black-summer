# Correlación entre estrictez de protección (IUCN) y exposición al fuego.
#
# Entrada : outputs/tabla_iucn_amenaza_exposicion.csv  (producido por script 04)
# Salida  : impresión en consola (no escribe archivos)
#
# Pregunta: ¿las categorías IUCN más estrictas presentan mayor proporción (o
# cantidad) de área quemada en Black Summer? Se ordena la estrictez de protección
# (Ia = más estricta ... VI = menos estricta) y se correlaciona con el fuego.
# La unidad de análisis es la CATEGORÍA IUCN (n = 7; NAS "No asignado" se excluye
# porque no tiene un nivel de protección rankeable).
#
# Interpretación del signo: la hipótesis "más estricta -> más quemada" implica una
# correlación NEGATIVA (a menor rango de estrictez, mayor % quemado).
#
# ADVERTENCIA METODOLÓGICA: con n = 7 el resultado es frágil y NO inferencial.
# Además, la asociación está probablemente MEDIADA POR LA UBICACIÓN: las áreas
# Wilderness (Ib) están en la escarpa boscosa oriental, la más expuesta a Black
# Summer; el análisis aún no controla por terreno ni vegetación (DEM sin usar).
# La categoría MÁS estricta (Ia) no sigue el patrón (arde poco). Resultado
# exploratorio: describe, no valida.
#
# Ejecutar:  Rscript scripts/07_correlacion_estrictez_quemado.R

suppressPackageStartupMessages(library(readr))

csv_path <- here::here("outputs", "tabla_iucn_amenaza_exposicion.csv")
tabla <- readr::read_csv(csv_path, show_col_types = FALSE)

# Rango de estrictez IUCN: 1 = más estricta ... 7 = menos estricta.
# (Ia > Ib [ambas categoría I] > II > III > IV > V > VI; NAS no rankeable.)
estrictez <- c(Ia = 1, Ib = 2, II = 3, III = 4, IV = 5, V = 6, VI = 7)

# El CSV trae etiquetas largas ("Ia – Strict Nature Reserve"): extraer el código.
codigo <- sub("^([^ ]+) .*", "\\1", tabla[["IUCN"]])
rank_estrictez <- estrictez[codigo]

keep    <- !is.na(rank_estrictez)            # descarta NAS
rk      <- rank_estrictez[keep]
pct_q   <- tabla[["% quemado"]][keep]
ha_q    <- tabla[["Quemado (ha)"]][keep]

correr <- function(x, y, etiqueta) {
  sp <- suppressWarnings(cor.test(x, y, method = "spearman"))
  pe <- suppressWarnings(cor.test(x, y, method = "pearson"))
  cat(sprintf("\n%s  (n = %d)\n", etiqueta, length(x)))
  cat(sprintf("  Spearman : rho = %+.3f   p = %.3f\n", sp$estimate, sp$p.value))
  cat(sprintf("  Pearson  : r   = %+.3f   p = %.3f\n", pe$estimate, pe$p.value))
}

cat("Estrictez de protección IUCN  vs  exposición al fuego")
cat("\n=====================================================")
cat("\n(rho NEGATIVO = a mayor estrictez, mayor fuego => apoya la hipótesis)\n")
correr(rk, pct_q, "Estrictez vs % quemado (proporción del área)")
correr(rk, ha_q,  "Estrictez vs hectáreas quemadas (cantidad absoluta)")

cat("\nLectura: asociación negativa moderada (apunta a 'más estricta -> más",
    "\nquemada') pero NO significativa (p > 0.05, n = 7). La sostienen sobre todo",
    "\nIb (Wilderness, 79 % quemado) y las categorías bajas (V, VI); la MÁS",
    "\nestricta (Ia) la contradice (8.9 %). Probable confusión por ubicación de",
    "\nlas reservas estrictas en terreno boscoso. Exploratorio, no inferencial.\n")
