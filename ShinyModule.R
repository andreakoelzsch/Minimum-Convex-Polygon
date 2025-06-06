library(move2)
library(adehabitatHR)
library(shiny)
library(fields)
library(zip)
library(shinyBS)
library(sf)
library(pals)
library(leaflet)
library(leaflet.extras)
library(htmlwidgets)
# library(webshot2) # needed for save as PNG (add to appspecs if activated)
library(dplyr)
# library(chromote) #

##### Interface ######
shinyModuleUserInterface <- function(id, label) {
  ns <- NS(id)
  
  tagList(
    titlePanel("Minimum Convex Polygon (MCP)"),
    sidebarLayout(
      sidebarPanel(
        sliderInput(ns("perc"), "Percentage of points included in MCP", min = 0, max = 100, value = 95, width = "100%"),
        checkboxGroupInput(ns("animal_selector"), "Select Track:", choices = NULL),
        downloadButton(ns("save_html"),"Download as HTML", class = "btn-sm"),
        # downloadButton(ns("save_png"), "Save Map as PNG", class = "btn-sm"),
        # downloadButton(ns("download_geojson"), "Download MCP as GeoJSON", class = "btn-sm"),
        downloadButton(ns("download_kmz"), "Download as KMZ", class = "btn-sm"),
        bsTooltip(id=ns("download_kmz"), title="Format for GoogleEarth", placement = "bottom", trigger = "hover", options = list(container = "body")),
        downloadButton(ns("download_gpkg"), "Download as GPKG", class = "btn-sm"),
        bsTooltip(id=ns("download_gpkg"), title="Shapefile for QGIS/ArcGIS", placement = "bottom", trigger = "hover", options = list(container = "body")),
        downloadButton(ns("download_mcp_table"), "Download MCP Areas Table", class = "btn-sm"),
        ,width = 3),
      mainPanel(leafletOutput(ns("leafmap"), height = "85vh") ,width = 9)
    )
  )
}



#####server######

shinyModule <- function(input, output, session, data) {
  ns <- session$ns
  current <- reactiveVal(data)

  # exclude all individuals with less than 5 locations
  data_filtered <- reactive({
    req(data)
    data %>%
      group_by(mt_track_id()) %>%
      filter(n() >= 5) %>%
      ungroup()
  })
  
  ##select animal in side bar
  observe({
    req(data_filtered())
    df <- data_filtered()
    
    animal_choices <- unique(mt_track_id(df))
    updateCheckboxGroupInput(session = session,
                             inputId = "animal_selector",
                             choices = animal_choices,
                             selected = animal_choices)
  })
  
  
  selected_data <- reactive({
    req(input$animal_selector)
    df <- data_filtered()
    selected <- filter_track_data(df, .track_id = input$animal_selector)
    selected
  })
  
  
  # Compute the MCP 
  mcp_cal <- reactive({
    req(input$perc)
    data_sel <- selected_data()
    
    crs_proj <- mt_aeqd_crs(data_sel, center = "center", units = "m")
    sf_data_proj <- st_transform(data_sel, crs_proj) 
    sf_data_proj$id <- mt_track_id(sf_data_proj)
    sp_data_proj <- as_Spatial(sf_data_proj[,'id'])
    sp_data_proj <- sp_data_proj[,(names(sp_data_proj) %in% "id")] 
    sp_data_proj$id <- make.names(as.character(sp_data_proj$id),allow_=F)

    data_mcp <- adehabitatHR::mcp(sp_data_proj, input$perc, "m", "km2")
   
    sf_mcp <- st_as_sf(data_mcp) %>% 
      rename(track_id = id) %>%
      st_transform(4326)
    sf_mcp$track_id <- as.character(sf_mcp$track_id)
    
    data_sel <-  mutate_track_data(data_sel, track_id= make.names(data.frame(mt_track_data(data_sel)[,mt_track_id_column(data_sel)])[,1],allow_=F)) ## adding column 'track_id' to data

    return(list(data_mcp = sf_mcp, track_lines = mt_track_lines(data_sel)))
    
  })
  
  
  
  ##leaflet map####

  mmap <- reactive({
    req(mcp_cal())
    mcp_dat <- mcp_cal()
    bounds <- as.vector(st_bbox(selected_data()))
    track_lines <- mcp_dat$track_lines
    sf_mcp <- mcp_dat$data_mcp
    ids <- unique(c(sf_mcp$track_id, track_lines$track_id))
    pal <- colorFactor(palette = pals::glasbey(), domain = ids)

    leaflet(options = leafletOptions(minZoom = 2)) %>% 
      fitBounds(bounds[1], bounds[2], bounds[3], bounds[4]) %>%       
      addTiles() %>%
      addProviderTiles("Esri.WorldTopoMap", group = "TopoMap") %>%
      addProviderTiles("Esri.WorldImagery", group = "Aerial") %>%
      addTiles(group = "OpenStreetMap") %>%
      addScaleBar(position = "topleft") %>%
      
      addPolylines(data = track_lines, color = ~pal(track_lines$track_id),
                   weight = 3, group = "Tracks") %>%
      addPolygons(data = sf_mcp, fillColor = ~pal(track_id),color = "black",fillOpacity = 0.4,
                  weight = 2,label = ~track_id,group = "MCPs") %>%
      
      addLegend(position = "bottomright",pal = pal,values = ids,title = "Track") %>%
      
      addLayersControl(
        baseGroups = c("OpenStreetMap", "TopoMap", "Aerial"),
        overlayGroups = c("Tracks", "MCPs"),
        options = layersControlOptions(collapsed = FALSE)
      )
  })
  
  output$leafmap <- renderLeaflet({mmap()})
  
  
  ###download the table of mcp
  output$download_mcp_table <- downloadHandler(
    filename = paste0("MCPs_",input$perc,"_areas.csv"),
    content = function(file) {
      mcp <- mcp_cal()$data_mcp
      mcp_df <- as.data.frame(mcp)
      df <- data.frame(TrackID = rownames(mcp_df), Area_km2 = mcp_df$area, MCP_percent=input$perc)
      write.csv(df, file, row.names = FALSE) })
  
  
  
  ### save map as HTML
  output$save_html <- downloadHandler(
    filename = paste0("MCPs_",input$perc,".html"),
    content = function(file) {
      saveWidget(widget = mmap(),file=file) })
  
  
  # ### save map as PNG
  # output$save_png <- downloadHandler(
  #   filename = paste0("MCPs_",input$perc,".png"),
  #   content = function(file) {
  #     html_file <- "leaflet_export.html"
  #     saveWidget(mmap(), file = html_file, selfcontained = TRUE)
  #     Sys.sleep(2)
  #     webshot2::webshot(url = html_file,file = file,vwidth = 1000,vheight = 800) })


  ###download shape as kmz  
  output$download_kmz <- downloadHandler(
    filename = paste0("MCPs_",input$perc,".kmz"),
    content = function(file) {
      temp_kmz <- tempdir()
      mcp_shape <- st_as_sf(mcp_cal()$data_mcp)
      kml_path <- file.path(temp_kmz, "mcp.kml")
      st_write(mcp_shape, kml_path, driver="KML", delete_dsn = TRUE)
      zip::zip(zipfile = file, files = kml_path, mode = "cherry-pick")})
  

  # ###download shape as GeoJSON###
  # output$download_geojson <- downloadHandler(
  #   filename = paste0("MCPs_",input$perc,".geojson"),
  #   content = function(file) {
  #     mcp_l <- mcp_cal()
  #     mcp_shape <- st_as_sf(mcp_l$data_mcp)
  #     track_lines <- mcp_l$track_lines
  #     ids <- unique(mcp_shape$individual_name_deployment_id)
  #     pal <- colorFactor(palette = pals::cols25(), domain = ids)
  #     mcp_shape$`fill` <- pal(mcp_shape$individual_name_deployment_id)
  #     st_write(mcp_shape, file, driver = "GeoJSON", delete_dsn = TRUE)  })

  
  ###download shape as GeoPackage (GPKG)
  output$download_gpkg <- downloadHandler(
    filename = paste0("MCPs_",input$perc,".gpkg"),
    content = function(file) {
      mcp_shape <- st_as_sf(mcp_cal()$data_mcp)
      st_write(mcp_shape, file, driver = "GPKG", delete_dsn = TRUE)} )
  
  
  return(reactive({ current() }))
}
