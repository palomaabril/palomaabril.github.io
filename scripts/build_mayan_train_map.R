workspace <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)

sections_root <- "C:/Users/palom/OneDrive - Istituto Universitario Europeo/Documentos/Paper_tren_maya/secciones"
deforestation_csv <- "C:/Users/palom/OneDrive - Istituto Universitario Europeo/Documentos/LEFT TO CLASSIFY/deforestation_new_calculation.csv"
output_geojson <- file.path(workspace, "assets/maps/sections_deforestation_light.geojson")

ogr2ogr <- Sys.which("ogr2ogr")
ogrinfo <- Sys.which("ogrinfo")
if (!nzchar(ogr2ogr)) ogr2ogr <- "C:/OSGeo4W/bin/ogr2ogr.exe"
if (!nzchar(ogrinfo)) ogrinfo <- "C:/OSGeo4W/bin/ogrinfo.exe"
stopifnot(file.exists(ogr2ogr), file.exists(ogrinfo))
stopifnot(file.exists(deforestation_csv), dir.exists(sections_root))

run_cmd <- function(exe, args) {
  cmd <- paste(c(shQuote(exe), shQuote(args)), collapse = " ")
  out <- system(cmd, intern = TRUE, ignore.stderr = FALSE)
  status <- attr(out, "status")
  if (!is.null(status) && status != 0) {
    cat(out, sep = "\n")
    stop("Command failed: ", cmd)
  }
  invisible(out)
}

write_sql <- function(name, sql) {
  path <- file.path(tmp_dir, name)
  writeLines(sql, path, useBytes = TRUE)
  paste0("@", path)
}

dir.create(dirname(output_geojson), recursive = TRUE, showWarnings = FALSE)
tmp_dir <- file.path(workspace, "assets/maps/_tmp_build")
if (dir.exists(tmp_dir)) unlink(tmp_dir, recursive = TRUE)
dir.create(tmp_dir, recursive = TRUE)

message("Reading deforestation CSV...")
def <- read.csv(deforestation_csv, check.names = FALSE, stringsAsFactors = FALSE)
required <- c("entidad_municipio_seccion", "def_seccion_m")
missing <- setdiff(required, names(def))
if (length(missing) > 0) {
  stop("CSV is missing required column(s): ", paste(missing, collapse = ", "))
}

def$section_join_id <- sprintf("%09.0f", as.numeric(def$entidad_municipio_seccion))
def$def_seccion_m <- as.numeric(def$def_seccion_m)
def_agg <- aggregate(
  def$def_seccion_m,
  by = list(section_join_id = def$section_join_id),
  FUN = sum,
  na.rm = TRUE
)
names(def_agg)[2] <- "deforestation_m2"
def_agg <- def_agg[is.finite(def_agg$deforestation_m2), ]
write.csv(
  def_agg,
  file.path(tmp_dir, "deforestation_by_section.csv"),
  row.names = FALSE,
  quote = TRUE
)

message("CSV rows: ", nrow(def))
message("Unique CSV sections: ", nrow(def_agg))
message("Total deforestation_m2: ", round(sum(def_agg$deforestation_m2), 3))

state_dirs <- list.dirs(file.path(sections_root, "2024"), recursive = FALSE, full.names = TRUE)
state_dirs <- state_dirs[basename(state_dirs) != "todas"]
shps <- file.path(state_dirs, ifelse(basename(state_dirs) == "QUINTANAROO", "SECCION.shp", "SECCION (1).shp"))
shps <- shps[file.exists(shps)]
if (length(shps) == 0) stop("No 2024 state shapefiles found.")

gpkg <- file.path(tmp_dir, "sections_work.gpkg")
first <- TRUE
for (shp in shps) {
  state <- basename(dirname(shp))
  layer <- tools::file_path_sans_ext(basename(shp))
  message("Importing ", state, " from ", basename(shp), " and transforming to EPSG:4326...")
  sql <- paste0(
    "SELECT *, '", state, "' AS state_name, ",
    "printf('%02d%03d%04d', CAST(ENTIDAD AS INTEGER), CAST(MUNICIPIO AS INTEGER), CAST(SECCION AS INTEGER)) AS section_join_id ",
    "FROM \"", layer, "\""
  )
  sql_file <- write_sql(paste0("import_", state, ".sql"), sql)
  args <- c(
    "-f", "GPKG", gpkg, shp,
    "-nln", "sections",
    "-nlt", "PROMOTE_TO_MULTI",
    "-t_srs", "EPSG:4326",
    "-dialect", "SQLite",
    "-sql", sql_file
  )
  if (!first) args <- c("-update", "-append", args[-c(1, 2)])
  run_cmd(ogr2ogr, args)
  first <- FALSE
}

message("Importing aggregated deforestation table...")
run_cmd(
  ogr2ogr,
  c(
    "-f", "GPKG", "-update", gpkg,
    file.path(tmp_dir, "deforestation_by_section.csv"),
    "-nln", "deforestation",
    "-oo", "AUTODETECT_TYPE=YES"
  )
)

message("Diagnosing join...")
joined_csv <- file.path(tmp_dir, "join_diagnostics.csv")
diag_sql <- write_sql(
  "diagnose_join.sql",
  paste(
    "SELECT",
    "(SELECT COUNT(*) FROM deforestation) AS csv_sections,",
    "(SELECT COUNT(DISTINCT section_join_id) FROM sections) AS shapefile_sections,",
    "(SELECT COUNT(DISTINCT d.section_join_id)",
    " FROM deforestation d INNER JOIN sections s",
    " ON d.section_join_id = s.section_join_id) AS matched_sections,",
    "(SELECT COUNT(DISTINCT d.section_join_id)",
    " FROM deforestation d LEFT JOIN sections s",
    " ON d.section_join_id = s.section_join_id",
    " WHERE s.section_join_id IS NULL) AS unmatched_csv_sections"
  )
)
run_cmd(
  ogr2ogr,
  c(
    "-f", "CSV", joined_csv, gpkg,
    "-dialect", "SQLite",
    "-sql", diag_sql
  )
)
diag <- read.csv(joined_csv, stringsAsFactors = FALSE)
print(diag)
write.csv(diag, file.path(dirname(output_geojson), "sections_deforestation_join_diagnostics.csv"), row.names = FALSE)
if (diag$matched_sections == 0) stop("Join produced zero matched sections; check the ID construction.")

message("Writing lightweight GeoJSON with real joined deforestation values...")
if (file.exists(output_geojson)) unlink(output_geojson)
export_sql <- paste(
  "SELECT",
  "s.section_join_id,",
  "s.state_name,",
  "CAST(s.ENTIDAD AS INTEGER) AS entidad,",
  "CAST(s.MUNICIPIO AS INTEGER) AS municipio,",
  "CAST(s.SECCION AS INTEGER) AS seccion,",
  "ROUND(d.deforestation_m2, 3) AS deforestation_m2,",
  "ST_SimplifyPreserveTopology(s.GEOMETRY, 0.001) AS GEOMETRY",
  "FROM sections s",
  "INNER JOIN deforestation d ON s.section_join_id = d.section_join_id",
  "WHERE d.deforestation_m2 IS NOT NULL"
)
export_sql_file <- write_sql("export_sections.sql", export_sql)
run_cmd(
  ogr2ogr,
  c(
    "-f", "GeoJSON", output_geojson, gpkg,
    "-dialect", "SQLite",
    "-sql", export_sql_file,
    "-lco", "COORDINATE_PRECISION=5"
  )
)

size_mb <- file.info(output_geojson)$size / 1024 / 1024
message("GeoJSON size MB: ", round(size_mb, 2))
if (size_mb >= 25) stop("GeoJSON is ", round(size_mb, 2), " MB; increase simplification before publishing.")

unlink(tmp_dir, recursive = TRUE)
message("Done: ", output_geojson)
