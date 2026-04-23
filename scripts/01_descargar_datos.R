# Orquestación de descargas para el análisis NSW / Black Summer 2019-2020.
#
# Uso (dentro de RStudio en el contenedor):
#   source(here::here("scripts", "01_descargar_datos.R"))
#
# Este script es idempotente: cada función de descarga verifica si el archivo
# ya existe y lo reutiliza. Para fuentes con portal dinámico (NIAFED, CAPAD,
# NVIS, FESM, DEM) el script se detiene con instrucciones de descarga manual
# la primera vez, y reanuda automáticamente cuando los archivos ya están en
# data/raw/<fuente>/.

suppressPackageStartupMessages({
  library(here)
  library(glue)
})

source(here("R", "utils_geo.R"))
source(here("R", "download_asgs.R"))
source(here("R", "download_niafed.R"))
source(here("R", "download_capad.R"))
source(here("R", "download_nvis.R"))
source(here("R", "download_fesm.R"))
source(here("R", "download_dem.R"))

message("=== ASGS STE (límite estatal NSW) ===")
download_asgs_ste()

message("=== NIAFED (perímetros Black Summer) ===")
tryCatch(download_niafed(), error = function(e) message(conditionMessage(e)))

message("=== CAPAD 2020 Terrestrial (áreas protegidas) ===")
tryCatch(download_capad_2020(), error = function(e) message(conditionMessage(e)))

message("=== NVIS v7.0 MVG Extant (vegetación) ===")
tryCatch(download_nvis_mvg(), error = function(e) message(conditionMessage(e)))

message("=== NSW FESM 2019/20 (severidad) ===")
tryCatch(download_fesm_2019_20(), error = function(e) message(conditionMessage(e)))

message("=== GA 1-second DEM (relieve) ===")
tryCatch(download_dem_nsw(), error = function(e) message(conditionMessage(e)))

message("\nDescargas completadas (o instrucciones manuales emitidas para lo que falte).")
