# Descarga de estructura primaria (relieve) — DEM para NSW.
#
# Estrategia: descarga PROGRAMÁTICA con elevatr::get_elev_raster(), que arma un
# mosaico de elevación (AWS Terrain Tiles, derivado de SRTM/3DEP) recortado al
# área de interés. Esto evita la descarga manual interactiva del GA 1-second DEM
# en ELVIS y hace el pipeline reproducible e idempotente.
#
# Nota sobre la fuente: NO es el GA 1-second DEM oficial, sino un mosaico SRTM
# equivalente en resolución (~30 m en el nivel de zoom máximo). Para nuestro uso
# —derivar elevación y pendiente medias por polígono ASP— es funcionalmente
# equivalente. El nivel de zoom `z` controla la resolución/peso:
#   z = 7  ≈ 1 km   ·  z = 8 ≈ 600 m  ·  z = 9 ≈ 300 m  ·  z = 10 ≈ 150 m
# Para covariables agregadas a polígono, z = 8 basta y mantiene el archivo
# manejable sobre los ~800.000 km² de NSW.
#
# Fuente original equivalente: Geoscience Australia 1-second SRTM-derived DEM
# (ELVIS, https://elevation.fsdf.org.au/). Licencia: CC-BY 4.0.

source(here::here("R", "utils_geo.R"))
source(here::here("R", "download_asgs.R"))

# Descarga el DEM de NSW vía elevatr y lo cachea en data/raw/dem/.
# Retorna el path local del GeoTIFF (en EPSG:4326, sin recortar a NSW todavía;
# el recorte/reproyección a Albers ocurre en 02_procesar_nsw.R).
download_dem_nsw <- function(dir_raw = here::here("data", "raw", "dem"),
                             z = 8) {
  dir.create(dir_raw, recursive = TRUE, showWarnings = FALSE)
  dest <- file.path(dir_raw, glue::glue("nsw_dem_elevatr_z{z}.tif"))

  if (file.exists(dest) && file.info(dest)$size > 0) {
    message(glue::glue("[cache] {basename(dest)} ya existe ",
                       "({round(file.info(dest)$size/1e6, 1)} MB)"))
    return(dest)
  }

  if (!requireNamespace("elevatr", quietly = TRUE)) {
    stop("Falta el paquete 'elevatr'. Instalar con renv::install(\"elevatr\") ",
         "y registrarlo en renv.lock (ver README; evitar renv::snapshot() ",
         "completo por el gotcha de poda del lock).", call. = FALSE)
  }

  message(glue::glue("[elevatr] Descargando DEM de NSW (z = {z}) ..."))
  nsw <- load_nsw_boundary()                      # ASGS STE, GDA2020
  nsw_wgs <- sf::st_transform(nsw, PROJ_WGS84)    # elevatr trabaja mejor en 4326

  dem <- elevatr::get_elev_raster(
    locations = nsw_wgs,
    z         = z,
    clip      = "locations",                      # recorta al polígono de NSW
    verbose   = FALSE
  )

  # get_elev_raster() retorna un RasterLayer (paquete raster); lo pasamos a terra
  # y lo guardamos como Float32 (la elevación es continua, en metros).
  dem <- terra::rast(dem)
  names(dem) <- "elevation"
  terra::writeRaster(dem, dest, overwrite = TRUE, datatype = "FLT4S")
  message(glue::glue("[elevatr] DEM guardado: {dest}"))
  dest
}
