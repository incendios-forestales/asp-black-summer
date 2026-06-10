# Correlación entre combustible (% eucalipto) y exposición (% quemado) por IUCN.
#
# Entrada : outputs/tabla_iucn_amenaza_exposicion.csv  (producido por script 04)
# Salida  : impresión en consola (no escribe archivos)
#
# Pregunta: ¿el % de eucalipto esclerófilo de cada categoría IUCN predice su
# % de área quemada en Black Summer? Se usa Spearman (rangos) porque la
# relación no es monótona limpia y n es pequeño; Pearson se reporta solo como
# contraste. La unidad de análisis es la CATEGORÍA IUCN (n = 7, u 8 con el
# residual "No asignado"), no el píxel ni el polígono.
#
# ADVERTENCIA METODOLÓGICA: con n = 7 categorías el resultado es frágil. El
# eucalipto es ubicuo (≈35–90 % en toda categoría) ⇒ condición necesaria pero
# no suficiente; la exposición la domina la geografía de la huella Black Summer,
# no el combustible. NO presentar esto como "correlación" central en el póster.
#
# Ejecutar:  Rscript scripts/05_correlacion_euc_quemado.R

suppressPackageStartupMessages(library(readr))

csv_path <- here::here("outputs", "tabla_iucn_amenaza_exposicion.csv")
tabla <- readr::read_csv(csv_path, show_col_types = FALSE)

euc     <- tabla[["% eucalipto"]]
quemado <- tabla[["% quemado"]]
iucn    <- tabla[["IUCN"]]
es_nas  <- grepl("^NAS", iucn)

correr <- function(x, y, etiqueta) {
  sp <- suppressWarnings(cor.test(x, y, method = "spearman"))
  pe <- suppressWarnings(cor.test(x, y, method = "pearson"))
  cat(sprintf("\n%s  (n = %d)\n", etiqueta, length(x)))
  cat(sprintf("  Spearman : rho = %+.3f   p = %.3f\n", sp$estimate, sp$p.value))
  cat(sprintf("  Pearson  : r   = %+.3f   p = %.3f\n", pe$estimate, pe$p.value))
}

cat("Correlación  % eucalipto  vs  % quemado  por categoría IUCN")
cat("\n===========================================================\n")
correr(euc[!es_nas], quemado[!es_nas], "7 categorías IUCN (Ia-VI, sin NAS)")
correr(euc,          quemado,          "8 categorías (incluye NAS)")
cat("\nLectura: correlación positiva moderada pero NO significativa (p > 0.05).",
    "\nEl eucalipto es necesario pero no suficiente; la exposición la manda la",
    "\ngeografía. Resultado exploratorio, no inferencial.\n")
