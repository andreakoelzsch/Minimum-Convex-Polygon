# Minimum Convex Polygon

MoveApps

Github repository: *github.com/andreakoelzsch/Minimum-Convex-Polygon*
  
  
## Description
Calculate the individual MCPs of your Individuals' locations and have them plotted on an interactive map. The MCPs polygons can be downloaded as a HTML, KMZ and GeoPackage (GPKG). A table with the MCPs area sizes can also be downloaded.

## Documentation
This App calculates simple Minimum Convex Polygons (MCPs) for each individual of your data set. Note that calculation of MCP is only possible for tracks with at least 5 locations. Individual tracks with less locations are removed for this analysis but are included in the output data set for use in further Apps. 
In addition, the user can select the individual for whom the MCP will be calculated and visualized on the map.

To calculate the planar MCP shapes, the dataset is reprojected to an Azimuthal Equidistant (AEQD) coordinate system centered on the spatial extent of the data, using meters as units.

The MCPs for each individual are plotted on an OpenStreetMap as the default basemap, with transparent, individual-specific colors. Below the polygons, the downsampled tracks of individuals (with sufficiently long tracks) are displayed in the same matching colors. Users can switch to Topo or Aerial basemaps if desired.

A csv-file summarizing the area of each MCP is available through the "Download MCP Areas Table (CSV)" button. 
Users also can save the currently displayed map as an HTML file, as a KMZ file (for Google Earth) and as a GeoPackage (GPKG) file (shapefiles for QGis, ArcGis, etc).
  
### Application scope
#### Generality of App usability
This App was developed for any taxonomic group. 

#### Required data properties
The App should work for any kind of (location) data. Each track needs a minimum of 5 locations. The location data should not be spacially autocorrelated to compile with the assumptions of the method. WE RECOMEND USING THE APP XXXX TO FILTER THE DATA 

### Input type
`move2::move2_loc`

### Output type
`move2::move2_loc`

### Artefacts
This App does not produce Artefacts. The following files can be downloaded optionally:

`MCPs_xx_areas.csv`: `xx` representing the chosen percentage. Contains the area of each MPC per track.

`MCPs_xx.html`: `xx` representing the chosen percentage. MCPs polygons on basemap as a HTML file.

`MCPs_xx.kmz`: `xx` representing the chosen percentage. MCPs polygons in a Google Earth friendly format.

`MCPs_xx.gpkg`: `xx` representing the chosen percentage. MCPs shapefiles as a GeoPackage (GPKG) in a ArcGis, QGis, etc.

### Settings 
`Percentage of points included in MCP`: Defined percentage of locations that the MCP algorithm shall use for calculating the MCP. We use the mcp() implementation of the adehabitat package, where (100 minus perc percent of the) locations furthest away from the centroid (arithmetic mean of the coordinates for each animal) are removed. Unit: % (range 0-100). Default 95.

`Select Track`: Select the Track(s) for whom the MCP will be calculated and visualized on the map. By default, all Tracks are selected.

`Map`: selection of basemap (OpenStreetMap, Topomap or Aerial) and display of Tracks and MCPs. By default OpenStreeMap and both Tracks and MCPs are selected 


### Changes in output data
The input data remains unchanged.

### Most common errors

### Null or error handling
