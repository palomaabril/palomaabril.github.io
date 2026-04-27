workspace <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)

ecuador_root <- "C:/Users/palom/OneDrive - Istituto Universitario Europeo/Documentos/paper_ecuador"
vote_rdata <- file.path(ecuador_root, "mw_expanded2.RData")
parroquia_shp <- file.path(ecuador_root, "limites_parroquiales/LIMITE_PARROQUIAL_CONALI_CNE_2022.shp")
output_geojson <- file.path(workspace, "assets/maps/ecuador_referendum_parroquias.geojson")

ogr2ogr <- Sys.which("ogr2ogr")
if (!nzchar(ogr2ogr)) ogr2ogr <- "C:/OSGeo4W/bin/ogr2ogr.exe"
stopifnot(file.exists(ogr2ogr), file.exists(vote_rdata), file.exists(parroquia_shp))

dir.create(dirname(output_geojson), recursive = TRUE, showWarnings = FALSE)
tmp_dir <- file.path(workspace, "assets/maps/_tmp_ecuador")
if (dir.exists(tmp_dir)) unlink(tmp_dir, recursive = TRUE)
dir.create(tmp_dir, recursive = TRUE)

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

message("Loading Ecuador referendum data...")
load(vote_rdata)
if (!exists("mw_expanded2")) stop("mw_expanded2 was not found in ", vote_rdata)

dat <- as.data.frame(mw_expanded2)
dat$SI_num <- suppressWarnings(as.numeric(dat$SI))
dat$NO_num <- suppressWarnings(as.numeric(dat$NO))
dat$total_si_no <- dat$SI_num + dat$NO_num
dat$percentage_SI_calc <- ifelse(dat$total_si_no > 0, 100 * dat$SI_num / dat$total_si_no, NA_real_)

df23 <- dat[dat$year.x == 2023 & !is.na(dat$parroquia_id.x) & !is.na(dat$percentage_SI_calc), ]
df23$parroquia_id <- as.character(df23$parroquia_id.x)
df23$sex <- toupper(as.character(df23$JUNTA_SEXO.x))

ids <- sort(unique(df23$parroquia_id))
summaries <- lapply(ids, function(id) {
  rows <- df23[df23$parroquia_id == id, ]
  male <- rows[rows$sex == "MASCULINO", ]
  female <- rows[rows$sex == "FEMENINO", ]

  yes_votes <- sum(rows$SI_num, na.rm = TRUE)
  no_votes <- sum(rows$NO_num, na.rm = TRUE)
  total_votes <- yes_votes + no_votes

  male_yes <- sum(male$SI_num, na.rm = TRUE)
  male_no <- sum(male$NO_num, na.rm = TRUE)
  female_yes <- sum(female$SI_num, na.rm = TRUE)
  female_no <- sum(female$NO_num, na.rm = TRUE)

  pct_si_male <- if ((male_yes + male_no) > 0) 100 * male_yes / (male_yes + male_no) else NA_real_
  pct_si_female <- if ((female_yes + female_no) > 0) 100 * female_yes / (female_yes + female_no) else NA_real_

  data.frame(
    parroquia_id = id,
    parroquia_name = rows$parroquia_name[which(!is.na(rows$parroquia_name))[1]],
    canton = rows$canton[which(!is.na(rows$canton))[1]],
    provincia = rows$provincia[which(!is.na(rows$provincia))[1]],
    yes_pct_2023 = if (total_votes > 0) 100 * yes_votes / total_votes else NA_real_,
    yes_votes = yes_votes,
    no_votes = no_votes,
    pct_si_male = pct_si_male,
    pct_si_female = pct_si_female,
    gender_gap_m_minus_f = pct_si_male - pct_si_female
  )
})

map_data <- do.call(rbind, summaries)
map_data$parroquia_name[is.na(map_data$parroquia_name)] <- ""
map_data$canton[is.na(map_data$canton)] <- ""
map_data$provincia[is.na(map_data$provincia)] <- ""

csv_path <- file.path(tmp_dir, "ecuador_map_values.csv")
write.csv(map_data, csv_path, row.names = FALSE, quote = TRUE)

message("Vote-data parroquias: ", nrow(map_data))
message("YES pct range: ", round(min(map_data$yes_pct_2023, na.rm = TRUE), 2), " to ", round(max(map_data$yes_pct_2023, na.rm = TRUE), 2))
message("Gender gap range: ", round(min(map_data$gender_gap_m_minus_f, na.rm = TRUE), 2), " to ", round(max(map_data$gender_gap_m_minus_f, na.rm = TRUE), 2))

gpkg <- file.path(tmp_dir, "ecuador_work.gpkg")
shape_sql <- write_sql(
  "import_parroquias.sql",
  paste(
    "SELECT *,",
    "printf('%s%03d%d', CODPRO, CAST(CODCAN AS INTEGER), CAST(CODPAR AS INTEGER)) AS parroquia_id",
    "FROM \"LIMITE_PARROQUIAL_CONALI_CNE_2022\""
  )
)
run_cmd(
  ogr2ogr,
  c(
    "-f", "GPKG", gpkg, parroquia_shp,
    "-nln", "parroquias",
    "-nlt", "PROMOTE_TO_MULTI",
    "-t_srs", "EPSG:4326",
    "-dialect", "SQLite",
    "-sql", shape_sql
  )
)

run_cmd(
  ogr2ogr,
  c(
    "-f", "GPKG", "-update", gpkg, csv_path,
    "-nln", "votes"
  )
)

diag_csv <- file.path(tmp_dir, "ecuador_join_diagnostics.csv")
diag_sql <- write_sql(
  "diagnose_ecuador_join.sql",
  paste(
    "SELECT",
    "(SELECT COUNT(*) FROM votes) AS vote_parroquias,",
    "(SELECT COUNT(*) FROM parroquias) AS shape_parroquias,",
    "(SELECT COUNT(DISTINCT v.parroquia_id) FROM votes v INNER JOIN parroquias p ON v.parroquia_id = p.parroquia_id) AS matched_parroquias,",
    "(SELECT COUNT(DISTINCT v.parroquia_id) FROM votes v LEFT JOIN parroquias p ON v.parroquia_id = p.parroquia_id WHERE p.parroquia_id IS NULL) AS unmatched_vote_parroquias"
  )
)
run_cmd(ogr2ogr, c("-f", "CSV", diag_csv, gpkg, "-dialect", "SQLite", "-sql", diag_sql))
diag <- read.csv(diag_csv, stringsAsFactors = FALSE)
print(diag)
write.csv(diag, file.path(dirname(output_geojson), "ecuador_referendum_join_diagnostics.csv"), row.names = FALSE)
if (diag$matched_parroquias == 0) stop("Join produced zero matched parroquias.")

export_sql <- write_sql(
  "export_ecuador.sql",
  paste(
    "SELECT",
    "p.parroquia_id,",
    "COALESCE(v.parroquia_name, p.PARROQUIA) AS parroquia_name,",
    "COALESCE(v.canton, p.CANTON) AS canton,",
    "COALESCE(v.provincia, p.PROVINCIA) AS provincia,",
    "ROUND(v.yes_pct_2023, 3) AS yes_pct_2023,",
    "CAST(v.yes_votes AS INTEGER) AS yes_votes,",
    "CAST(v.no_votes AS INTEGER) AS no_votes,",
    "ROUND(v.pct_si_male, 3) AS pct_si_male,",
    "ROUND(v.pct_si_female, 3) AS pct_si_female,",
    "ROUND(v.gender_gap_m_minus_f, 3) AS gender_gap_m_minus_f,",
    "ST_SimplifyPreserveTopology(p.GEOMETRY, 0.001) AS GEOMETRY",
    "FROM parroquias p",
    "INNER JOIN votes v ON p.parroquia_id = v.parroquia_id",
    "WHERE v.yes_pct_2023 IS NOT NULL"
  )
)
if (file.exists(output_geojson)) unlink(output_geojson)
run_cmd(
  ogr2ogr,
  c(
    "-f", "GeoJSON", output_geojson, gpkg,
    "-dialect", "SQLite",
    "-sql", export_sql,
    "-lco", "COORDINATE_PRECISION=5"
  )
)

size_mb <- file.info(output_geojson)$size / 1024 / 1024
message("GeoJSON size MB: ", round(size_mb, 2))
unlink(tmp_dir, recursive = TRUE)
message("Done: ", output_geojson)
