library(move2)
library(sf)
library(raster)
library(units)
library(adehabitatHR)

mcpPercentage <- 95

fishers_mv2 <- mt_read(mt_example())
fishers_mv2 <- dplyr::filter(fishers_mv2, !sf::st_is_empty(fishers_mv2))

aeqd_crs <-  mt_aeqd_crs(fishers_mv2, "center", "m") 
fishers_mv2_prj <- sf::st_transform(fishers_mv2, aeqd_crs) ## data for mcp always have to be projected

fishers_mv2_prj$id <- mt_track_id(fishers_mv2_prj)
fishers_p_sp <- as_Spatial(fishers_mv2_prj[,'id'])
## function mcp is very particular about the input object, it must only contain 1 column, and names of the individuals names have to follow the validNames() rules
fishers_p_sp <- fishers_p_sp[,(names(fishers_p_sp) %in% "id")] 
fishers_p_sp$id <- make.names(as.character(fishers_p_sp$id),allow_=F)
levels(fishers_p_sp$id) <- validNames(levels(fishers_p_sp$id))
mcp95 <- mcp(fishers_p_sp, percent=mcpPercentage, unin ="m",unout="km2")
mcp95$area # area in km2

mcp95sf <- st_as_sf(mcp95,crs=st_crs(4326)) ## converting it to lat/long to display on map and provide as download


