# Mayan Train Website Map

This repository contains a lightweight GitHub Pages page and a repeatable map build script for the Mayan Train deforestation section map.

Run the map export from the repository root:

```powershell
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts\build_mayan_train_map.R
```

The script uses the 2024 state section shapefiles in `Paper_tren_maya/secciones`, constructs the section key as `ENTIDAD` + padded `MUNICIPIO` + padded `SECCION`, joins it to `entidad_municipio_seccion` in `deforestation_new_calculation.csv`, creates aggregated `deforestation_m2`, transforms geometries to EPSG:4326, simplifies them, and exports `assets/maps/sections_deforestation_light.geojson`.

Preview locally:

```powershell
node scripts\static-server.js
```

Then open `http://127.0.0.1:8000/`.
