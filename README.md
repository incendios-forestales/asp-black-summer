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
├── scripts/                          # orquestación (01_descargar, 02_procesar, 03_mapas, 04_tabla_IUCN, 05/07_correlacion, 06_bivariados)
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
| Relieve                 | GA 1-second DEM                  | Estructura primaria               |
| Límite estatal          | ABS ASGS Ed.3                    | Administrativo                    |

Marco teórico: Miklós, L. et al. (2019). *Landscape as a Geosystem*. Springer Nature.

## Productos

- `analysis/01_exploracion_nsw.html` — reporte Quarto con 6 mapas estáticos y la tabla cruzada IUCN × amenaza × exposición (incluye `% eucalipto`).
- `outputs/figs/0[1-6]_*.png` — 6 mapas estáticos sueltos: contexto ASP, amenaza, intersección, NVIS, FESM y eucalipto en ASP.
- `outputs/figs/06[a-d]_*.png` — 4 figuras de síntesis: bivariado Exposición × Severidad (`06a`), bivariado Eucalipto × Severidad (`06b`), heatmap IUCN × {%quemado, %eucalipto, severidad} (`06c`) y lollipop % quemado por estrictez IUCN (`06d`).
- `outputs/maps/*.html` — 4 mapas interactivos (Leaflet): 1, 2, 3 y 6 (eucalipto en ASP).
- `outputs/tabla_iucn_amenaza_exposicion.{csv,html}` — tabla cruzada por categoría IUCN.
- `data/processed/*.gpkg` y `*.tif` — capas listas para abrir en QGIS.

Los scripts `05` y `07` no escriben archivos: imprimen en consola correlaciones de Spearman/Pearson (eucalipto↔%quemado y estrictez IUCN↔%quemado). Ambas asociaciones resultan **débiles y no significativas** (n = 7 categorías); son exploratorias, no inferenciales.

## Pipeline

```r
source("scripts/01_descargar_datos.R")        # idempotente; orienta descargas manuales
source("scripts/02_procesar_nsw.R")           # recorta a NSW, reproyecta a EPSG:3577
source("scripts/03_mapas_exploratorios.R")    # exporta PNG + HTML interactivos
source("scripts/04_estadisticas_iucn.R")      # tabla cruzada IUCN × amenaza × exposición
source("scripts/05_correlacion_euc_quemado.R")# Spearman %eucalipto vs %quemado (exploratorio)
source("scripts/06_mapas_bivariados.R")       # mapas bivariados + heatmap-resumen IUCN
source("scripts/07_correlacion_estrictez_quemado.R") # Spearman estrictez IUCN vs %quemado (exploratorio)
quarto::quarto_render("analysis/01_exploracion_nsw.qmd")
```

## Próximos pasos / pendientes

- **Script 08 — regresión múltiple por polígono ASP (pendiente).** Las correlaciones
  bivariadas (`05` eucalipto, `07` estrictez) sugieren asociaciones débiles con el
  `% quemado`, pero son no significativas (n = 7 categorías) y probablemente
  **confundidas por la ubicación/relieve** de las ASP (las áreas Wilderness, Ib,
  están en la escarpa boscosa oriental, la más expuesta). El paso para pasar de
  "se asocia" a "aporta de forma independiente" es una **regresión múltiple por
  polígono** (n ≈ 1099, o solo los 392 quemados según se defina el outcome):
  `% quemado ~ % eucalipto + estrictez_IUCN + terreno`. Las covariables por polígono
  `pct_burned`, `pct_euc` e `IUCN` ya se calculan en `scripts/06_mapas_bivariados.R`
  (estadística zonal con `exactextractr`) y pueden reutilizarse.
- **Falta el DEM (estructura primaria / relieve).** Para incorporar el terreno como
  covariable hace falta el DEM, que está **declarado pero no descargado**:
  `R/download_dem.R` orienta la descarga manual desde ELVIS y `data/raw/dem/` está
  vacío. Una vez descargado: recortar a NSW en `scripts/02`, derivar pendiente y
  rugosidad con `terra::terrain()`, y extraer estadística zonal por polígono igual
  que el MVG/eucalipto. Esto cierra el 3.er nivel del marco Miklós (hoy solo se
  operacionalizan estructura secundaria y terciaria).
- **Integración de las figuras `06a–d`.** Son prototipos en `outputs/figs`; aún no
  están enlazadas en la portada (`index.html`) ni en el reporte Quarto. Decidir
  cuáles entran al póster antes de integrarlas.

## Reproducibilidad

- Imagen Docker fijada: `rocker/geospatial:4.5.3`.
- Paquetes R fijados: `renv.lock`.
- Line endings normalizados: `.gitattributes` (interop Linux ↔ Windows).
