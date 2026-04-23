# Utilitarios geoespaciales compartidos.
#
# CRS de referencia para el proyecto:
#   EPSG:4326 — WGS 84 (entrada genérica)
#   EPSG:7844 — GDA2020 geográfico (dato oficial australiano moderno)
#   EPSG:3577 — GDA94 Australian Albers (CRS nacional para análisis de área)

suppressPackageStartupMessages({
  library(sf)
  library(terra)
  library(glue)
  library(here)
})

PROJ_ALBERS <- "EPSG:3577"
PROJ_GDA2020 <- "EPSG:7844"
PROJ_WGS84  <- "EPSG:4326"

# Convierte un sf o SpatRaster al CRS de análisis (Australian Albers).
to_albers <- function(x) {
  if (inherits(x, "sf") || inherits(x, "sfc")) {
    sf::st_transform(x, PROJ_ALBERS)
  } else if (inherits(x, "SpatRaster") || inherits(x, "SpatVector")) {
    terra::project(x, PROJ_ALBERS)
  } else {
    stop("to_albers(): tipo no soportado: ", class(x)[1])
  }
}

# Descarga un archivo a un path local solo si no existe aún.
# Retorna el path local. Útil para caché idempotente en data/raw/.
download_if_missing <- function(url, dest, mode = "wb", timeout = 1800) {
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(dest) && file.info(dest)$size > 0) {
    message(glue("[cache] {basename(dest)} ya existe ({round(file.info(dest)$size/1e6, 1)} MB)"))
    return(invisible(dest))
  }
  message(glue("[download] {url} → {dest}"))
  old_timeout <- getOption("timeout")
  options(timeout = timeout)
  on.exit(options(timeout = old_timeout), add = TRUE)
  utils::download.file(url, dest, mode = mode, quiet = FALSE)
  invisible(dest)
}

# Descomprime un zip en un directorio destino solo si el destino está vacío.
unzip_if_needed <- function(zip_path, exdir) {
  dir.create(exdir, recursive = TRUE, showWarnings = FALSE)
  if (length(list.files(exdir, recursive = TRUE)) == 0) {
    message(glue("[unzip] {basename(zip_path)} → {exdir}"))
    utils::unzip(zip_path, exdir = exdir)
  }
  invisible(exdir)
}

# Emite una instrucción de descarga manual cuando la fuente no expone URL directa estable.
# Verifica si ya hay un archivo con el patrón esperado en dir_destino; si no, imprime pasos.
expect_manual_download <- function(dir_destino, patron, portal_url, notas = NULL) {
  dir.create(dir_destino, recursive = TRUE, showWarnings = FALSE)
  archivos <- list.files(dir_destino, pattern = patron, recursive = TRUE, full.names = TRUE)
  if (length(archivos) > 0) {
    message(glue("[cache] encontrado en {dir_destino}: {basename(archivos[1])}"))
    return(archivos[1])
  }
  msg <- c(
    glue("[MANUAL] Se requiere descarga manual en: {dir_destino}"),
    glue("         Portal: {portal_url}"),
    glue("         Patrón de archivo esperado: {patron}")
  )
  if (!is.null(notas)) msg <- c(msg, glue("         Notas: {notas}"))
  stop(paste(msg, collapse = "\n"), call. = FALSE)
}

# Lector + caché: si `cache_path` existe lo lee; si no, aplica `fn()` y guarda el resultado.
# Soporta sf (GPKG) y SpatRaster (GeoTIFF).
read_or_cache <- function(cache_path, fn, overwrite = FALSE) {
  if (file.exists(cache_path) && !overwrite) {
    ext <- tools::file_ext(cache_path)
    if (ext %in% c("gpkg", "geojson", "shp")) {
      return(sf::st_read(cache_path, quiet = TRUE))
    } else if (ext %in% c("tif", "tiff")) {
      return(terra::rast(cache_path))
    } else {
      stop("read_or_cache(): extensión no soportada: ", ext)
    }
  }
  obj <- fn()
  dir.create(dirname(cache_path), recursive = TRUE, showWarnings = FALSE)
  ext <- tools::file_ext(cache_path)
  if (ext %in% c("gpkg", "geojson", "shp")) {
    sf::st_write(obj, cache_path, delete_dsn = TRUE, quiet = TRUE)
  } else if (ext %in% c("tif", "tiff")) {
    terra::writeRaster(obj, cache_path, overwrite = TRUE)
  }
  obj
}

# Recorta un sf al bounding box de NSW (en el CRS del sf).
# `nsw_boundary` debe ser el polígono STE de NSW ya leído.
crop_to_nsw <- function(x, nsw_boundary) {
  stopifnot(inherits(x, "sf"), inherits(nsw_boundary, "sf"))
  if (sf::st_crs(x) != sf::st_crs(nsw_boundary)) {
    nsw_boundary <- sf::st_transform(nsw_boundary, sf::st_crs(x))
  }
  sf::st_filter(x, nsw_boundary, .predicate = sf::st_intersects)
}
