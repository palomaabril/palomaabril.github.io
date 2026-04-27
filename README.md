# Mayan Train Website Map

This repository contains a lightweight GitHub Pages page and a repeatable map build script for the Mayan Train deforestation section map.

Run the map export from the repository root:

```powershell
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts\build_mayan_train_map.R
```

The script uses the 2024 state section shapefiles in `Paper_tren_maya/secciones`, constructs the section key as `ENTIDAD` + padded `MUNICIPIO` + padded `SECCION`, joins it to `entidad_municipio_seccion` in `deforestation_new_calculation.csv`, creates aggregated `deforestation_m2`, transforms geometries to EPSG:4326, simplifies them, and exports `assets/maps/sections_deforestation_light.geojson`.

## Ecuador Referendum Map

Run the Ecuador export from the repository root:

```powershell
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts\build_ecuador_maps.R
```

The script reads `paper_ecuador/mw_expanded2.RData`, aggregates 2023 referendum Yes votes by parroquia and sex, joins those values to the CONALI/CNE parroquia boundary shapefile, transforms geometries to EPSG:4326, and exports `assets/maps/ecuador_referendum_parroquias.geojson`. The website lets users switch between the Yes vote layer and the male-minus-female gender gap layer, then click each parroquia for values.

The join diagnostic is written to `assets/maps/ecuador_referendum_join_diagnostics.csv`.

Preview locally:

```powershell
node scripts\static-server.js
```

Then open `http://127.0.0.1:8000/`.
