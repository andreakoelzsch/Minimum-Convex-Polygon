library(move2)
library(adehabitatHR)
library(shiny)
library(zip)
library(shinyBS)
library(sf)
library(pals)
library(leaflet)
library(htmlwidgets)
library(webshot2)
library(callr)
library(shinybusy)
library(dplyr)
library(jsonlite)
library(shinycssloaders)

`%||%` <- function(x, y) if (is.null(x)) y else x

##### Interface ######
shinyModuleUserInterface <- function(id, label) {
  ns <- NS(id)
  
  tagList(
    titlePanel("Minimum Convex Polygon (MCP)"),
    sidebarLayout(
      sidebarPanel(
        sliderInput(ns("perc"), "Percentage of points included in MCP", min = 1, max = 100, value = 95, width = "100%"),
        #checkboxGroupInput(ns("animal_selector"), "Select Track:", choices = NULL),
        uiOutput(ns("animals_ui")),
        tags$div(style = "display:none;", textInput(ns("animals_json"), label = NULL, value = "")),
        downloadButton(ns("save_html"),"Download as HTML", class = "btn-sm"),
        downloadButton(ns("save_png"), "Save Map as PNG", class = "btn-sm"),
        # downloadButton(ns("download_geojson"), "Download MCP as GeoJSON", class = "btn-sm"),
        downloadButton(ns("download_kmz"), "Download as KMZ", class = "btn-sm"),
        bsTooltip(id=ns("download_kmz"), title="Format for GoogleEarth", placement = "bottom", trigger = "hover", options = list(container = "body")),
        downloadButton(ns("download_gpkg"), "Download as GPKG", class = "btn-sm"),
        bsTooltip(id=ns("download_gpkg"), title="Shapefile for QGIS/ArcGIS", placement = "bottom", trigger = "hover", options = list(container = "body")),
        downloadButton(ns("download_mcp_table"), "Download MCP Areas Table", class = "btn-sm"),
        width = 3),
      mainPanel(
        withSpinner(leafletOutput(ns("leafmap"), height = "85vh")),
        width = 9
      )
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
  
  all_ids_vec <- reactive({
    req(data_filtered())
    sort(unique(as.character(mt_track_id(data_filtered()))))
  })
  output$animals_ui <- renderUI({
    animal_choices <- all_ids_vec()
    restored_sel <- isolate(input$animal_selector)
    sel <- if (!is.null(restored_sel)) restored_sel else animal_choices
    
    checkboxGroupInput( ns("animal_selector"),"Select Track:",choices = animal_choices,selected = sel )
  })
  
  applied_animals <- reactiveVal(NULL)
  init_applied <- reactiveVal(FALSE)
  
  observeEvent(input$animal_selector, {
    applied_animals(as.character(input$animal_selector %||% character(0)))
    init_applied(TRUE)
  }, ignoreInit = FALSE, ignoreNULL = FALSE)
  
  observeEvent(input$animal_selector, {
    vals <- input$animal_selector %||% character(0)
    updateTextInput(session,"animals_json", value = jsonlite::toJSON(vals, auto_unbox = FALSE))
  }, ignoreInit = TRUE)
  
  selected_data <- reactive({
    req(init_applied())
    
    sel <- applied_animals()
    df  <- data_filtered()
    
    if (is.null(sel) || length(sel) == 0) return(df[0, ])
    
    filter_track_data(df, .track_id = sel)
  })
  
  # Compute the MCP 
  mcp_cal <- reactive({
    req(input$perc)
    data_sel <- selected_data()
    shiny::validate(shiny::need(nrow(data_sel) > 0, "Select at least one track."))
    
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
  
  # Fixed opacity for the MCP fills; the track lines stay solid.
  layer_opacity <- 0.4
  
  # The map is built in two parts. base_map() holds everything that never
  # depends on the inputs (tiles, scale bar, layers control); add_data_layers()
  # holds everything that does. renderLeaflet() below draws the base only, so
  # moving the slider updates the data layers through leafletProxy() instead of
  # rebuilding the widget -- rebuilding is what reset the chosen basemap, the
  # overlay checkboxes and the zoom on every slider move.
  base_map <- function() {
    leaflet(options = leafletOptions(minZoom = 2)) %>%
      addTiles() %>%
      # addProviderTiles("OpenStreetMap", group = "OpenStreetMap") %>%
      addProviderTiles("Esri.WorldTopoMap", group = "TopoMap") %>%
      addProviderTiles("Esri.WorldImagery", group = "Aerial") %>%
      addProviderTiles("OpenStreetMap", group = "OpenStreetMap") %>%
      addScaleBar(position = "topleft") %>%
      addLayersControl(
        baseGroups = c("TopoMap", "Aerial", "OpenStreetMap"),
        overlayGroups = c("Tracks", "MCPs"),
        options = layersControlOptions(collapsed = FALSE)
      )
  }
  
  # layerId on the legend so the proxy can replace it instead of stacking one
  # legend per redraw.
  add_data_layers <- function(map, mcp_dat) {
    track_lines <- mcp_dat$track_lines
    sf_mcp <- mcp_dat$data_mcp
    ids <- unique(c(sf_mcp$track_id, track_lines$track_id))
    pal <- colorFactor(palette = pals::glasbey(), domain = ids)
    
    map %>%
      addPolylines(data = track_lines, color = ~pal(track_lines$track_id),
                   weight = 3, opacity = 1, group = "Tracks") %>%
      addPolygons(data = sf_mcp, fillColor = ~pal(track_id),color = "black",fillOpacity = layer_opacity,
                  weight = 2,label = ~track_id,group = "MCPs") %>%
      
      addLegend(position = "bottomright",pal = pal,values = ids,title = "Track",
                layerId = "track_legend")
  }
  
  # Full standalone widget, used by the HTML and PNG downloads only.
  mmap <- reactive({
    mcp_dat <- mcp_cal()
    bounds <- as.vector(st_bbox(selected_data()))
    
    base_map() %>%
      fitBounds(bounds[1], bounds[2], bounds[3], bounds[4]) %>%
      add_data_layers(mcp_dat)
  })
  
  output$leafmap <- renderLeaflet({base_map()})
  
  # Redraw the data layers whenever the percentage or the track selection
  # changes. The view is left alone here on purpose.
  observe({
    proxy <- leafletProxy("leafmap", session) %>%
      clearGroup("Tracks") %>%
      clearGroup("MCPs") %>%
      removeControl("track_legend")
    
    if (nrow(selected_data()) == 0) {
      proxy %>% addControl("Select at least one track.", position = "topright",
                           layerId = "empty_msg")
      return(invisible(NULL))
    }
    
    proxy %>%
      removeControl("empty_msg") %>%
      add_data_layers(mcp_cal())
  })
  
  # Re-frame only when the selected tracks change: the bounds do not depend on
  # the slider, so this keeps the user's pan/zoom while they drag it.
  observeEvent(selected_data(), {
    d <- selected_data()
    req(nrow(d) > 0)
    bounds <- as.vector(st_bbox(d))
    leafletProxy("leafmap", session) %>%
      fitBounds(bounds[1], bounds[2], bounds[3], bounds[4])
  })
  
  
  ###download the table of mcp
  output$download_mcp_table <- downloadHandler(
    filename = function() paste0("MCPs_", input$perc, "_areas.csv"),
    content = function(file) {
      mcp_df <- as.data.frame(mcp_cal()$data_mcp)
      df <- data.frame(TrackID = mcp_df$track_id, Area_km2 = mcp_df$area, MCP_percent = input$perc)
      write.csv(df, file, row.names = FALSE) })
  
  
  
  ### save map as HTML
  output$save_html <- downloadHandler(
    filename = function() paste0("MCPs_", input$perc, ".html"),
    content = function(file) {
      saveWidget(widget = mmap(),file=file) })
  
  
  ### save map as PNG
  output$save_png <- downloadHandler(
    filename = function() paste0("MCPs_",input$perc,".png"),
    content = function(file) {
    
    shinybusy::show_modal_spinner(spin = "fading-circle", text = "Saving PNG…")
      on.exit(shinybusy::remove_modal_spinner(), add = TRUE)
      # Render the map to an HTML file first. selfcontained = FALSE avoids the
      # pandoc dependency (the browser loads the local file + sidecar directly).
      html_file <- tempfile(fileext = ".html")
      saveWidget(mmap(), file = html_file, selfcontained = FALSE)
      html_file <- normalizePath(html_file, winslash = "/", mustWork = TRUE)

      # webshot2/chromote drive headless Chrome over the SAME global `later`
      # event loop that Shiny is already running. Calling it directly from a
      # Shiny handler re-enters that loop and deadlocks (the R process spins at
      # ~100% CPU, the screenshot never completes, and the download surfaces as
      # a gateway 500 / "connection prematurely closed"). Running it in a
      # separate R process via callr gives chromote its own event loop and
      # avoids the deadlock.
      callr::r(
        function(html_file, out_file) {
          webshot2::webshot(url = html_file, file = out_file, vwidth = 1000, vheight = 800, delay = 2)
        },
        args = list(html_file = html_file, out_file = file)
      )
    })
  
  
  ###download shape as kmz  
  output$download_kmz <- downloadHandler(
    filename = function() paste0("MCPs_", input$perc, ".kmz"),
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
    filename = function() paste0("MCPs_", input$perc, ".gpkg"),
    content = function(file) {
      mcp_shape <- st_as_sf(mcp_cal()$data_mcp)
      st_write(mcp_shape, file, driver = "GPKG", delete_dsn = TRUE)} )
  
  
  return(reactive({ current() }))
}