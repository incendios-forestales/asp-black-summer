#!/usr/bin/env python3
"""Construye estilos QML + un proyecto QGIS (.qgs/.qgz) para las capas del
proyecto ASP Black Summer, listo para abrir y superponer en QGIS.

Genera, dentro de data/processed/:
  - <capa>.qml         estilos que QGIS aplica solo al arrastrar la capa.
  - asp_black_summer.qgs / .qgz  proyecto con todas las capas precargadas
                          y estilizadas, en CRS GDA94 / Australian Albers
                          (EPSG:3577).

No requiere QGIS instalado: arma el XML directamente. Lee extensión, nombre de
capa y estadísticas con gdalinfo/ogrinfo.

Uso:  python3 scripts/13_construir_proyecto_qgis.py
"""
import json
import os
import subprocess
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
DP = os.path.normpath(os.path.join(HERE, "..", "data", "processed"))
# Plantillas estáticas versionadas (data/processed/ está en .gitignore).
ASSETS = os.path.normpath(os.path.join(HERE, "..", "assets"))

# Bloque CRS idéntico al que escribe QGIS 3.40 para EPSG:3577 (WKT2 + srsid 1535,
# el id estable en la srs.db incorporada). Así QGIS lo lee nativo, sin avisos de
# "CRS desconocido". srsid=0 / WKT1 hacían que QGIS no resolviera el authid.
WKT3577 = ('PROJCRS["GDA94 / Australian Albers",BASEGEOGCRS["GDA94",DATUM["Geocentric Datum of Australia 1994",'
           'ELLIPSOID["GRS 1980",6378137,298.257222101,LENGTHUNIT["metre",1]]],PRIMEM["Greenwich",0,'
           'ANGLEUNIT["degree",0.0174532925199433]],ID["EPSG",4283]],CONVERSION["Australian Albers",'
           'METHOD["Albers Equal Area",ID["EPSG",9822]],PARAMETER["Latitude of false origin",0,'
           'ANGLEUNIT["degree",0.0174532925199433],ID["EPSG",8821]],PARAMETER["Longitude of false origin",132,'
           'ANGLEUNIT["degree",0.0174532925199433],ID["EPSG",8822]],PARAMETER["Latitude of 1st standard parallel",-18,'
           'ANGLEUNIT["degree",0.0174532925199433],ID["EPSG",8823]],PARAMETER["Latitude of 2nd standard parallel",-36,'
           'ANGLEUNIT["degree",0.0174532925199433],ID["EPSG",8824]],PARAMETER["Easting at false origin",0,'
           'LENGTHUNIT["metre",1],ID["EPSG",8826]],PARAMETER["Northing at false origin",0,LENGTHUNIT["metre",1],'
           'ID["EPSG",8827]]],CS[Cartesian,2],AXIS["(E)",east,ORDER[1],LENGTHUNIT["metre",1]],'
           'AXIS["(N)",north,ORDER[2],LENGTHUNIT["metre",1]],USAGE[SCOPE["Statistical analysis."],'
           'AREA["Australia - Australian Capital Territory; New South Wales; Northern Territory; Queensland; '
           'South Australia; Tasmania; Western Australia; Victoria."],BBOX[-43.7,112.85,-9.86,153.69]],ID["EPSG",3577]]')
PROJ4 = ("+proj=aea +lat_0=0 +lon_0=132 +lat_1=-18 +lat_2=-36 +x_0=0 +y_0=0 "
         "+ellps=GRS80 +units=m +no_defs")

SRS = f"""<spatialrefsys nativeFormat="Wkt">
      <wkt>{WKT3577}</wkt>
      <proj4>{PROJ4}</proj4>
      <srsid>1535</srsid><srid>3577</srid><authid>EPSG:3577</authid>
      <description>GDA94 / Australian Albers</description>
      <projectionacronym>aea</projectionacronym>
      <ellipsoidacronym>EPSG:7019</ellipsoidacronym>
      <geographicflag>false</geographicflag>
    </spatialrefsys>"""


# ---------------------------------------------------------------- helpers gdal
def gdalinfo_json(path):
    out = subprocess.check_output(["gdalinfo", "-json", "-stats", path],
                                  stderr=subprocess.DEVNULL)
    return json.loads(out)


def ogr_layer_name(path):
    out = subprocess.check_output(["ogrinfo", "-ro", "-so", path],
                                  stderr=subprocess.DEVNULL).decode()
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("1:"):
            # "1: layername (Polygon)"
            return line.split(":", 1)[1].strip().split(" ")[0]
    return os.path.splitext(os.path.basename(path))[0]


def ogr_extent(path):
    out = subprocess.check_output(["ogrinfo", "-ro", "-so", "-al", path],
                                  stderr=subprocess.DEVNULL).decode()
    for line in out.splitlines():
        if line.strip().startswith("Extent:"):
            s = line.split("Extent:")[1].strip()
            a, b = s.split(" - ")
            xmin, ymin = [float(v) for v in a.strip("() ").split(",")]
            xmax, ymax = [float(v) for v in b.strip("() ").split(",")]
            return xmin, ymin, xmax, ymax
    raise RuntimeError("sin extent: " + path)


def raster_extent_stats(path):
    j = gdalinfo_json(path)
    cc = j["cornerCoordinates"]
    xs = [cc["upperLeft"][0], cc["lowerRight"][0]]
    ys = [cc["upperLeft"][1], cc["lowerRight"][1]]
    band = j["bands"][0]
    mn = band.get("minimum")
    mx = band.get("maximum")
    return (min(xs), min(ys), max(xs), max(ys)), mn, mx


def hex_to_rgba(h, a=255):
    h = h.lstrip("#")
    return f"{int(h[0:2],16)},{int(h[2:4],16)},{int(h[4:6],16)},{a}"


# ------------------------------------------------------------- renderer XML
def simple_fill(name, fill_rgba, outline_rgba="50,50,50,255", outline_w="0.1",
                style="solid"):
    return (f'<symbol name="{name}" type="fill">'
            f'<layer class="SimpleFill">'
            f'<prop k="color" v="{fill_rgba}"/>'
            f'<prop k="style" v="{style}"/>'
            f'<prop k="outline_color" v="{outline_rgba}"/>'
            f'<prop k="outline_width" v="{outline_w}"/>'
            f'<prop k="outline_style" v="solid"/>'
            f'</layer></symbol>')


def categorized_renderer(attr, cats):
    """cats: list of (value, hex_or_rgba, label). '' value => default/última."""
    categories, symbols = [], []
    for i, (val, col, lab) in enumerate(cats):
        rgba = col if "," in col else hex_to_rgba(col, 150)
        categories.append(f'<category value="{val}" symbol="{i}" label="{lab}" render="true"/>')
        symbols.append(simple_fill(str(i), rgba))
    return ('<renderer-v2 type="categorizedSymbol" attr="' + attr +
            '" forceraster="0" symbollevels="0" enableorderby="0">'
            '<categories>' + "".join(categories) + '</categories>'
            '<symbols>' + "".join(symbols) + '</symbols></renderer-v2>')


def single_symbol_fill(fill_rgba, outline_rgba, outline_w="0.4", style="solid"):
    return ('<renderer-v2 type="singleSymbol" forceraster="0" symbollevels="0" enableorderby="0">'
            '<symbols>' + simple_fill("0", fill_rgba, outline_rgba, outline_w, style) +
            '</symbols></renderer-v2>')


def paletted_renderer(entries):
    """entries: list of (value, hex, label, alpha)."""
    pe = "".join(
        f'<paletteEntry value="{v}" color="{c}" label="{lab}" alpha="{a}"/>'
        for (v, c, lab, a) in entries)
    return ('<rasterrenderer type="paletted" band="1" opacity="1" alphaBand="-1" nodataColor="">'
            '<colorPalette>' + pe + '</colorPalette></rasterrenderer>')


def singlebandgray_renderer(mn, mx):
    return (f'<rasterrenderer type="singlebandgray" band="1" opacity="1" alphaBand="-1" '
            f'grayBand="1" gradient="BlackToWhite" nodataColor="">'
            f'<contrastEnhancement><minValue>{mn}</minValue><maxValue>{mx}</maxValue>'
            f'<algorithm>StretchToMinimumMaximum</algorithm></contrastEnhancement>'
            f'</rasterrenderer>')


def pseudocolor_renderer(mn, mx, ramp):
    """ramp: list of (value, hex)."""
    items = "".join(f'<item value="{v}" color="{c}" alpha="255" label="{v:.0f}"/>'
                    for (v, c) in ramp)
    return (f'<rasterrenderer type="singlebandpseudocolor" band="1" opacity="1" '
            f'alphaBand="-1" classificationMin="{mn}" classificationMax="{mx}" nodataColor="">'
            f'<rastershader><colorrampshader colorRampType="INTERPOLATED" '
            f'classificationMode="1" minimumValue="{mn}" maximumValue="{mx}">'
            f'{items}</colorrampshader></rastershader></rasterrenderer>')


# ------------------------------------------------------------------ paletas
IUCN_CATS = [
    ("Ia",  "#2166ac", "Ia — Reserva natural estricta"),
    ("Ib",  "#4393c3", "Ib — Área silvestre"),
    ("II",  "#92c5de", "II — Parque nacional"),
    ("III", "#d1e5f0", "III — Monumento natural"),
    ("IV",  "#fddbc7", "IV — Manejo de hábitat/especies"),
    ("V",   "#f4a582", "V — Paisaje protegido"),
    ("VI",  "#d6604d", "VI — Uso sostenible de recursos"),
    ("NAS", "#bdbdbd", "NAS — No asignada"),
]

BIV_PAL = {
    "1-1": "#e8e8e8", "2-1": "#ace4e4", "3-1": "#5ac8c8",
    "1-2": "#dfb0d6", "2-2": "#a5add3", "3-2": "#5698b9",
    "1-3": "#be64ac", "2-3": "#8c62aa", "3-3": "#3b4994",
}
BIV_LABELS = {
    "1-1": "exp baja · sev baja", "2-1": "exp media · sev baja", "3-1": "exp alta · sev baja",
    "1-2": "exp baja · sev media", "2-2": "exp media · sev media", "3-2": "exp alta · sev media",
    "1-3": "exp baja · sev alta", "2-3": "exp media · sev alta", "3-3": "exp alta · sev alta",
}


def biv_cats(prefix_labels):
    cats = [(k, hex_to_rgba(c, 220), prefix_labels.get(k, k)) for k, c in BIV_PAL.items()]
    cats.append(("", "200,200,200,120", "(sin las dos variables)"))
    return cats


# --------------------------------------------------------------- definición
def build():
    layers = []

    def vec(fname, name, renderer, checked):
        path = os.path.join(DP, fname)
        lyr = ogr_layer_name(path)
        ext = ogr_extent(path)
        layers.append(dict(kind="vector", file=fname, lyr=lyr, name=name,
                           renderer=renderer, ext=ext, checked=checked,
                           id=fname.replace(".", "_")))

    def ras(fname, name, renderer, checked):
        path = os.path.join(DP, fname)
        ext, mn, mx = raster_extent_stats(path)
        r = renderer(mn, mx) if callable(renderer) else renderer
        layers.append(dict(kind="raster", file=fname, name=name, renderer=r,
                           ext=ext, checked=checked, id=fname.replace(".", "_")))

    # --- orden TOC: el primero queda ARRIBA (se dibuja encima) ---
    vec("nsw_niafed_black_summer.gpkg", "Perímetro Black Summer 2019–2020",
        single_symbol_fill("227,26,28,40", "227,26,28,255", "0.5"), True)
    vec("asp_quemado_interseccion.gpkg", "ASP quemadas (intersección)",
        single_symbol_fill("252,78,42,140", "120,30,10,255", "0.1"), False)
    vec("nsw_boundary.gpkg", "Límite de NSW",
        single_symbol_fill("0,0,0,0", "60,60,60,255", "0.5"), True)
    vec("asp_bivariado.gpkg", "ASP · bivariado exposición × severidad (06a)",
        categorized_renderer("biv_expsev_key", biv_cats(BIV_LABELS)), False)
    vec("nsw_capad_2020.gpkg", "Áreas protegidas (CAPAD 2020) por IUCN",
        categorized_renderer("IUCN", [(v, c, l) for v, c, l in IUCN_CATS]), True)
    ras("eucalipto_en_asp.tif", "Eucalipto en ASP (NVIS reclasificado)",
        paletted_renderer([(1, "#1b7837", "Eucalipto esclerófilo", 255),
                           (2, "#b8a038", "Mallee (eucalipto)", 255)]), False)
    ras("nsw_fesm_severity.tif", "Severidad del fuego (FESM)",
        paletted_renderer([(0, "#d9d9d9", "Sin quemar", 0),
                           (2, "#ffeda0", "Baja", 255),
                           (3, "#feb24c", "Moderada", 255),
                           (4, "#fc4e2a", "Alta", 255),
                           (5, "#800026", "Extrema", 255)]), True)
    ras("nsw_nvis_mvg.tif", "Vegetación NVIS (Major Vegetation Groups)",
        singlebandgray_renderer, False)
    ras("nsw_dem.tif", "Elevación (DEM)",
        lambda mn, mx: pseudocolor_renderer(
            mn, mx, [(mn, "#276419"), ((mn + mx) / 2, "#f7f7c8"), (mx, "#8c510a")]), False)
    ras("nsw_slope.tif", "Pendiente", singlebandgray_renderer, False)
    ras("nsw_northness.tif", "Northness (orientación N–S)", singlebandgray_renderer, False)

    return layers


# ----------------------------------------------------------------- emisión
def write_qml(layers):
    for L in layers:
        body = L["renderer"]
        if L["kind"] == "raster":
            xml = (f'<!DOCTYPE qgis PUBLIC \'http://mrcc.com/qgis.dtd\' \'SYSTEM\'>\n'
                   f'<qgis version="3.34.0-Prizren" styleCategories="AllStyleCategories">\n'
                   f'<pipe>{body}</pipe>\n<blendMode>0</blendMode>\n</qgis>\n')
        else:
            xml = (f'<!DOCTYPE qgis PUBLIC \'http://mrcc.com/qgis.dtd\' \'SYSTEM\'>\n'
                   f'<qgis version="3.34.0-Prizren" styleCategories="AllStyleCategories">\n'
                   f'{body}\n<blendMode>0</blendMode>\n</qgis>\n')
        qml = os.path.join(DP, os.path.splitext(L["file"])[0] + ".qml")
        with open(qml, "w") as f:
            f.write(xml)
        print("[qml] ", os.path.basename(qml))


def maplayer_xml(L):
    xmin, ymin, xmax, ymax = L["ext"]
    ext = (f"<extent><xmin>{xmin}</xmin><ymin>{ymin}</ymin>"
           f"<xmax>{xmax}</xmax><ymax>{ymax}</ymax></extent>")
    srs = f"<srs>{SRS}</srs>"
    if L["kind"] == "vector":
        ds = f'./{L["file"]}|layername={L["lyr"]}'
        return (f'<maplayer type="vector" geometry="Polygon" hasScaleBasedVisibilityFlag="0">'
                f'<id>{L["id"]}</id><datasource>{ds}</datasource>'
                f'<layername>{L["name"]}</layername>{srs}{ext}'
                f'<provider>ogr</provider>{L["renderer"]}'
                f'<blendMode>0</blendMode></maplayer>')
    else:
        return (f'<maplayer type="raster" hasScaleBasedVisibilityFlag="0">'
                f'<id>{L["id"]}</id><datasource>./{L["file"]}</datasource>'
                f'<layername>{L["name"]}</layername>{srs}{ext}'
                f'<provider>gdal</provider><pipe>{L["renderer"]}</pipe>'
                f'<blendMode>0</blendMode></maplayer>')


def write_project(layers):
    union = [min(L["ext"][0] for L in layers), min(L["ext"][1] for L in layers),
             max(L["ext"][2] for L in layers), max(L["ext"][3] for L in layers)]
    tree = "".join(
        f'<layer-tree-layer id="{L["id"]}" name="{L["name"]}" source="./{L["file"]}" '
        f'providerKey="{"ogr" if L["kind"]=="vector" else "gdal"}" '
        f'checked="{"Qt::Checked" if L["checked"] else "Qt::Unchecked"}" expanded="0"/>'
        for L in layers)
    maplayers = "".join(maplayer_xml(L) for L in layers)
    order = "".join(f'<layer id="{L["id"]}"/>' for L in layers)
    qgs = f"""<!DOCTYPE qgis PUBLIC 'http://mrcc.com/qgis.dtd' 'SYSTEM'>
<qgis version="3.34.0-Prizren" projectname="ASP Black Summer — capas QGIS">
  <homePath path=""/>
  <title>ASP Black Summer — capas QGIS</title>
  <projectCrs>{SRS}</projectCrs>
  <layer-tree-group>{tree}</layer-tree-group>
  <mapcanvas name="theMapCanvas" annotationsVisible="1">
    <units>meters</units>
    <extent><xmin>{union[0]}</xmin><ymin>{union[1]}</ymin><xmax>{union[2]}</xmax><ymax>{union[3]}</ymax></extent>
    <rotation>0</rotation>
    <destinationsrs>{SRS}</destinationsrs>
    <rendermaptile>0</rendermaptile>
  </mapcanvas>
  <projectlayers>{maplayers}</projectlayers>
  <layerorder>{order}</layerorder>
  <!-- Sin este flag heredado QGIS NO lee el CRS del proyecto (lo deja vacío) ni
       reproyecta al vuelo: las capas se dibujan en metros Albers crudos y, al
       agregar un mapa base (EPSG:3857), aterrizan frente a Sudáfrica. -->
  <properties>
    <SpatialRefSys>
      <ProjectionsEnabled type="int">1</ProjectionsEnabled>
    </SpatialRefSys>
  </properties>
</qgis>
"""
    qgs_path = os.path.join(DP, "asp_black_summer.qgs")
    with open(qgs_path, "w") as f:
        f.write(qgs)
    print("[qgs] ", os.path.basename(qgs_path))
    qgz_path = os.path.join(DP, "asp_black_summer.qgz")
    with zipfile.ZipFile(qgz_path, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(qgs_path, "asp_black_summer.qgs")
    print("[qgz] ", os.path.basename(qgz_path))


def write_bundle(layers):
    """Arma asp-black-summer-capas-qgis.zip en la raíz del repo: una carpeta
    autocontenida (datos + .qml + .qgz + LEEME) con rutas relativas, lista para
    abrir en cualquier QGIS (incluido Windows). Lista los archivos de forma
    explícita: NO arrastra residuos como .qgs~, *_attachments.zip o *_styles.db."""
    root = os.path.normpath(os.path.join(HERE, ".."))
    folder = "asp-black-summer-qgis"

    files = []
    for L in layers:
        base = os.path.splitext(L["file"])[0]
        files += [L["file"], base + ".qml"]              # dato + estilo
        if L["kind"] == "raster" and os.path.exists(os.path.join(DP, L["file"] + ".aux.xml")):
            files.append(L["file"] + ".aux.xml")          # tablas de categorías
    files.append("asp_black_summer.qgz")

    # (origen, nombre en el zip). Los datos/estilos salen de DP; el LEEME es una
    # plantilla versionada en assets/ (DP está en .gitignore).
    members = [(os.path.join(DP, f), f) for f in files]
    members.append((os.path.join(ASSETS, "LEEME_QGIS.txt"), "LEEME_QGIS.txt"))

    zip_path = os.path.join(root, "asp-black-summer-capas-qgis.zip")
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for src, arcname in members:
            if not os.path.exists(src):
                raise RuntimeError("falta en el bundle: " + src)
            z.write(src, os.path.join(folder, arcname))
    print("[zip] ", os.path.relpath(zip_path, root), f"({len(members)} archivos)")


if __name__ == "__main__":
    layers = build()
    write_qml(layers)
    write_project(layers)
    write_bundle(layers)
    print("\nListo. Proyecto + estilos en:", DP)
