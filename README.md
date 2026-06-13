# Amenaza y exposición en áreas protegidas de NSW — Black Summer 2019-2020

Análisis geoespacial en R de la interacción amenaza-exposición en áreas silvestres protegidas (ASP) de Nueva Gales del Sur, Australia, durante el evento "Black Summer" 2019-2020.

**Productos en línea:**  
<https://incendios-forestales.github.io/asp-black-summer/>

## Estructura

```text
├── docker-compose.yml / Dockerfile   # entorno R + RStudio Server + stack geoespacial
├── .env.example                      # plantilla de variables de entorno
├── data/{raw,processed,external}/    # datos (no versionados)
├── R/                                # funciones reutilizables
├── scripts/                          # orquestación (01_descargar, 02_procesar, 03_mapas, 04_tabla_IUCN, 05/07_correlacion, 06_bivariados, 08_regresion)
├── analysis/01_exploracion_nsw.qmd   # reporte Quarto con mapas
└── outputs/{figs,maps}/              # productos finales
```

## Cómo correrlo — Linux + Docker (recomendado)

Prerrequisitos: Docker Engine + plugin Compose. El usuario debe estar en el grupo `docker`.

```bash
# 1. Configurar password de RStudio
cp .env.example .env
$EDITOR .env   # cambiar RSTUDIO_PASSWORD

# 2. Construir imagen y levantar el contenedor
docker compose up -d --build

# 3. Abrir RStudio Server
xdg-open http://localhost:8787
# Usuario: rstudio   Password: el definido en .env
```

Primera vez dentro de RStudio:

```r
renv::restore()   # instala paquetes fijados en renv.lock
```

Para apagar el contenedor sin perder datos:

```bash
docker compose down
```

Los archivos editados, datos descargados y outputs persisten en el host (bind-mount `.:/home/rstudio/project`).

## Cómo consumirlo — Windows

**No se necesita R ni Docker** para ver los resultados.

- Abrir los mapas interactivos en cualquier navegador (Edge, Firefox, Chrome): `outputs/maps/*.html`.
- Abrir los mapas estáticos: `outputs/figs/*.png`.
- Explorar los datos procesados en **QGIS**: `data/processed/*.gpkg` (capas vectoriales) y `*.tif` (rásters).

## Cómo ejecutar el pipeline en Windows (opcional)

Dos rutas posibles si eventualmente se quiere correr el análisis desde Windows:

### A. Docker Desktop + WSL2 (mismo contenedor que en Linux)

1. Instalar Docker Desktop con backend WSL2.
2. Clonar el repositorio dentro de WSL o del filesystem Windows.
3. `docker compose up -d --build` y abrir `http://localhost:8787`.

### B. R for Windows nativo

1. Instalar [R ≥ 4.5](https://cran.r-project.org/bin/windows/base/) y [Rtools45](https://cran.r-project.org/bin/windows/Rtools/).
2. Clonar el repositorio, abrir `asp-black-summer.Rproj` en RStudio.
3. Ejecutar `renv::restore()`. Los paquetes geoespaciales (`sf`, `terra`, `stars`) se instalan como binarios pre-compilados desde CRAN — no hace falta GDAL/PROJ del sistema.

## Fuentes de datos

Todas las fuentes son oficiales y de licencia abierta (CC-BY 4.0 salvo indicación). Se acreditan en cada mapa y en el reporte Quarto.

| Capa                    | Fuente                           | Estructura (Miklós et al. 2019)   |
| ----------------------- | -------------------------------- | --------------------------------- |
| Perímetros Black Summer | NIAFED — DCCEEW                  | Amenaza                           |
| Severidad FESM 2019/20  | NSW SEED                         | Amenaza                           |
| Áreas protegidas        | CAPAD 2020 Terrestrial — DCCEEW  | Estructura terciaria (normativa)  |
| Vegetación mayor (MVG)  | NVIS v7.0 — DCCEEW               | Estructura secundaria             |
| Relieve                 | DEM SRTM vía `elevatr` (≈ GA 1-sec) | Estructura primaria            |
| Límite estatal          | ABS ASGS Ed.3                    | Administrativo                    |

Marco teórico: Miklós, L. et al. (2019). *Landscape as a Geosystem*. Springer Nature.

## Productos

- `analysis/01_exploracion_nsw.html` — reporte Quarto con 6 mapas estáticos y la tabla cruzada IUCN × amenaza × exposición (incluye `% eucalipto`).
- `outputs/figs/0[1-6]_*.png` — 6 mapas estáticos sueltos: contexto ASP, amenaza, intersección, NVIS, FESM y eucalipto en ASP.
- `outputs/figs/06[a-d]_*.png` — 4 figuras de síntesis: bivariado Exposición × Severidad (`06a`), bivariado Eucalipto × Severidad (`06b`), heatmap IUCN × {%quemado, %eucalipto, severidad} (`06c`) y lollipop % quemado por estrictez IUCN (`06d`).
- `outputs/maps/*.html` — 4 mapas interactivos (Leaflet): 1, 2, 3 y 6 (eucalipto en ASP).
- `outputs/tabla_iucn_amenaza_exposicion.{csv,html}` — tabla cruzada por categoría IUCN.
- `outputs/regresion_quemado_coeficientes.csv` — coeficientes de la regresión por polígono ASP (script `08`).
- `outputs/figs/09_forest_estructuras.png` — forest plot de síntesis: efecto de cada estructura del paisaje (relieve, vegetación, manejo) sobre la probabilidad de quemarse (script `09`).
- `data/processed/*.gpkg` y `*.tif` — capas listas para abrir en QGIS (incluye `nsw_dem.tif`, `nsw_slope.tif` y `nsw_northness.tif`).

Los scripts `05` y `07` no escriben archivos: imprimen en consola correlaciones de Spearman/Pearson (eucalipto↔%quemado y estrictez IUCN↔%quemado). Ambas asociaciones resultan **débiles y no significativas** (n = 7 categorías); son exploratorias, no inferenciales. El script `08` sube la unidad de análisis al **polígono ASP** (n de cientos) y ajusta un GLM cuasibinomial que controla por terreno (elevación, pendiente, orientación) y vegetación; el `09` lo resume en un forest plot agrupado por las tres estructuras de Miklós.

## Pipeline

```r
source("scripts/01_descargar_datos.R")        # idempotente; orienta descargas manuales
source("scripts/02_procesar_nsw.R")           # recorta a NSW, reproyecta a EPSG:3577
source("scripts/03_mapas_exploratorios.R")    # exporta PNG + HTML interactivos
source("scripts/04_estadisticas_iucn.R")      # tabla cruzada IUCN × amenaza × exposición
source("scripts/05_correlacion_euc_quemado.R")# Spearman %eucalipto vs %quemado (exploratorio)
source("scripts/06_mapas_bivariados.R")       # mapas bivariados + heatmap-resumen IUCN
source("scripts/07_correlacion_estrictez_quemado.R") # Spearman estrictez IUCN vs %quemado (exploratorio)
source("scripts/08_regresion_quemado.R")      # GLM cuasibinomial por polígono ASP, controla por terreno
source("scripts/09_forest_estructuras.R")     # forest plot de síntesis agrupado por estructura (póster)
quarto::quarto_render("analysis/01_exploracion_nsw.qmd")
```

## Próximos pasos / pendientes

- **DEM (estructura primaria / relieve) — implementado.** `R/download_dem.R` baja el
  DEM por código con `elevatr::get_elev_raster()` (ya fijado en `renv.lock`); `scripts/02`
  reproyecta a Albers, recorta a NSW y deriva **pendiente** y **northness** (orientación
  N-S de la ladera) con `terra::terrain()`, produciendo `data/processed/{nsw_dem,nsw_slope,nsw_northness}.tif`.
  Cierra el 3.er nivel del marco Miklós (antes solo estructura secundaria y terciaria).
- **Scripts 08 + 09 — regresión por polígono ASP y forest plot — implementados.** El `08`
  sube la unidad de análisis de categoría IUCN (n = 7) al **polígono** (n de cientos) y
  ajusta un GLM cuasibinomial ponderado por área: `% quemado ~ estrictez + elevación +
  pendiente + northness + % eucalipto`, comparando M0 (solo estrictez) vs M1 (con
  terreno+vegetación). El `09` resume M1 en un forest plot agrupado por estructura
  (figura de síntesis del póster). **Pendiente:** corregir los IC por **autocorrelación
  espacial** (errores estándar cluster-robustos por bioregión IBRA, o modelo mixto/espacial)
  antes de los números finales.
- **Diseño del póster (marco Miklós).** Tres paneles-mapa = las tres estructuras
  (primaria/DEM, secundaria/vegetación, terciaria/ASP, esta última con la severidad del
  fuego encima) + panel de síntesis = forest plot `09`. El fuego (NIAFED + FESM) es el
  *evento* que actúa sobre las estructuras, no una cuarta estructura.
- **Integración de las figuras `06a–d` y `09`.** Son prototipos en `outputs/figs`; aún no
  están enlazadas en la portada (`index.html`) ni en el reporte Quarto. Decidir cuáles
  entran al póster antes de integrarlas.

## Reproducibilidad

- Imagen Docker fijada: `rocker/geospatial:4.5.3`.
- Paquetes R fijados: `renv.lock`.
- Line endings normalizados: `.gitattributes` (interop Linux ↔ Windows).
