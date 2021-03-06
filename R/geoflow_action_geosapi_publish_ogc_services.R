geosapi_publish_ogc_services <- function(entity, config, options){
  
  #options
  createWorkspace <- if(!is.null(options$createWorkspace)) options$createWorkspace else FALSE
  createDatastore <- if(!is.null(options$createDatastore)) options$createDatastore else FALSE
  datastore_description <- if(!is.null(options$datastore_description)) options$datastore_description else ""
  
  #for the timebeing, this action targets Vector data (featureType)
  #Later this action may also target coverage, but it's not yet supported by geosapi
  
  #check presence of data
  if(is.null(entity$data)){
    warnMsg <- sprintf("No data object associated to entity '%s'. Skipping data publication!", 
                       entity$identifiers[["id"]])
    config$logger.warn(warnMsg)
    return(NULL)
  }
  
  if(length(entity$data$source)>1) 
    config$logger.warn("More than one data sources, geosapi action will consider the first one only!")
  
  #datasource
  datasource <- entity$data$uploadSource[[1]]
  datasource_name <- NULL
  datasource_file <- NULL
  if(!is.null(datasource)){
    datasource_name <- unlist(strsplit(datasource, "\\."))[1]
    datasource_file <- attr(datasource, "uri")
    attributes(datasource) <- NULL
  }
  
  #layername/sourcename
  layername <- if(!is.null(entity$data$layername)) entity$data$layername else entity$identifiers$id
  
  #shortcut for gs config
  GS <- config$software$output$geoserver
  if(is.null(GS)){
    errMsg <- "This action requires a GeoServer software to be declared in the configuration"
    config$logger.error(errMsg)
    stop(errMsg)
  }

  datastore <- GS_CONFIG$properties$datastore
  if(is.null(datastore)) if(!is.null(entity$data$datastore)) datastore <- entity$data$datastore
  if(is.null(datastore)){
    errMsg <- "The geoserver configuration requires a datastore for publishing action"
    config$logger.error(errMsg)
    stop(errMsg)
  }
  
  if(entity$data$uploadType == "other"){
    warnMsg <- "No 'geosapi' action possible for type 'other'. Action skipped"
    config$logger.warn(warnMsg)
    return(NULL)
  }
  
  # Check existence of datastore
  ns <- GS$getDataStore(workspace, datastore)
  ds <- NULL
  # If datastore not exist
  # Check if createDataspace is TRUE
  if(length(ns)==0){
    if(createDatastore){
      switch(entity$data$uploadType,
        "gpkg"= ds<-GSGeoPackageDataStore$new(dataStore=datastore, description = datastore_description , enabled = TRUE, database = paste0("file://data/",workspace,"/",entity$data$uploadSource,".gpkg")),
        "dbtable"= {
          dbi<-config$software$output$dbi_config
          if(is.null(dbi)) dbi<-config$software$output$dbi_config
          if(is.null(dbi)) {
            errMsg <- sprintf("Error during Geoserver '%s' datastore creation, this datastore type requires a DBI type software declaration in the configuration",datastore)
            config$logger.error(errMsg)
            stop(errMsg)   
          }
          Postgres<-dbi$parameters$drv=="Postgres"
          if(!Postgres){
            errMsg <- sprintf("Error during Geoserver '%s' datastore creation, the DBI software declared in the configuration is not a PostGis database",datastore)
            config$logger.error(errMsg)
            stop(errMsg)   
          }
          ds<-GSPostGISDataStore$new(dataStore=datastore, description = datastore_description, enabled = TRUE)
          ds$setHost(dbi$parameters$host)
          ds$setPort(dbi$parameters$port)
          ds$setDatabase(dbi$parameters$dbname)
          #ds$setSchema()#Not yet implemented in dbi software arguments
          ds$setUser(dbi$parameters$user)
          ds$setPassword(dbi$parameters$password)
          },
        "dbquery"= {
          dbi<-config$software$output$dbi_config
          if(is.null(dbi)) dbi<-config$software$output$dbi_config
          if(is.null(dbi)) {
            errMsg <- sprintf("Error during Geoserver '%s' datastore creation, this datastore type requires a DBI type software declaration in the configuration",datastore)
            config$logger.error(errMsg)
            stop(errMsg)   
          }
          Postgres<-dbi$parameters$drv=="Postgres"
          if(!Postgres){
            errMsg <- sprintf("Error during Geoserver '%s' datastore creation, the DBI software declared in the configuration is not a PostGis database",datastore)
            config$logger.error(errMsg)
            stop(errMsg)   
          }
          ds<-GSPostGISDataStore$new(dataStore=datastore, description = datastore_description, enabled = TRUE)
          ds$setHost(dbi$parameters$host)
          ds$setPort(dbi$parameters$port)
          ds$setDatabase(dbi$parameters$dbname)
          #ds$setSchema()#Not yet implemented in dbi software arguments
          ds$setUser(dbi$parameters$user)
          ds$setPassword(dbi$parameters$password)
        },
        "shp"= ds<-GSShapefileDirectoryDataStore$new(dataStore=datastore, description = datastore_description,enabled = TRUE, url = paste0("file://data","/",workspace))
      )
      if(is.null(ds)){
        errMsg <- sprintf("Error during Geoserver datastore creation, format '%s' not supported. Aborting 'geosapi' action!",entity$data$uploadType)
        config$logger.error(errMsg)
        stop(errMsg)      
      }else{
        created <- GS$createDataStore(workspace, ds)
        if(created){
          infoMsg <- sprintf("Successful Geoserver '%s' datastore creaction", datastore)
          config$logger.info(infoMsg)
        }else{
          errMsg <- "Error during Geoserver datastore creation. Aborting 'geosapi' action!"
          config$logger.error(errMsg)
          stop(errMsg)
        }
      }
    }else{
      # If createDatastore is FALSE edit ERROR Message
      errMsg <- sprintf("Datastore '%s' don't exist and createDatastore option = FALSE, please verify config if datastore already exist or change createDatastore = TRUE to create it",datastore)
      config$logger.error(errMsg)
      stop(errMsg)
    }    
  }
  
  #upload
  #-------------------------------------------------------------------------------------------------
  if(entity$data$upload){

    config$logger.info("Upload mode is set to true")
    if(startsWith(entity$data$uploadType,"db") || entity$data$uploadType == "other"){
      warnMsg <- "Skipping upload: Upload mode is only valid for types 'shp', 'spatialite' or 'h2'"
      config$logger.warn(warnMsg)
    }else{
      uploaded <- FALSE
      config$logger.info("Upload from local file(s)")
      filepath <- file.path(getwd(), "data", datasource)
      config$logger.info(sprintf("File to upload to Geoserver: %s", filepath))
      if(file.exists(filepath)){
        config$logger.info(sprintf("Upload file '%s' [%s] to GeoServer...", filepath, entity$data$uploadType))
        uploaded <- GS$uploadData(workspace, datastore, endpoint = "file", configure = "none", update = "overwrite",
                                  filename = filepath, extension = entity$data$uploadType, charset = "UTF-8",
                                  contentType = if(entity$data$uploadType=="spatialite") "application/x-sqlite3" else "")
        }else{
          errMsg <- sprintf("Upload from local file(s): no zipped file found for source '%s' (%s)", filepath, datasource)
          config$logger.error(errMsg)
          stop(errMsg)
      }

      if(uploaded){
        infoMsg <- sprintf("Successful Geoserver upload for file '%s' (%s)", datasource_file, entity$data$uploadType)
        config$logger.info(infoMsg)
      }else{
        errMsg <- "Error during Geoserver file upload. Aborting 'geosapi' action!"
        config$logger.error(errMsg)
        stop(errMsg)
      }
    }
  }
  
  #featuretype/layer publication
  #--------------------------------------------------------------------------------------------------
  
  #variables
  epsgCode <- sprintf("EPSG:%s", entity$srid)
  
  #build feature type
  featureType <- GSFeatureType$new()
  featureType$setName(layername)
  nativename <- datasource_name
  if(entity$data$uploadType == "dbquery") nativename <- layername
  featureType$setNativeName(nativename)
  featureType$setAbstract(entity$descriptions$abstract)
  featureType$setTitle(entity$titles[["title"]])
  featureType$setSrs(epsgCode)
  featureType$setNativeCRS(epsgCode)
  featureType$setEnabled(TRUE)
  featureType$setProjectionPolicy("FORCE_DECLARED")
  bbox <- entity$spatial_bbox
  featureType$setLatLonBoundingBox(bbox$xmin, bbox$ymin, bbox$xmax, bbox$ymax, crs = epsgCode)
  featureType$setNativeBoundingBox(bbox$xmin, bbox$ymin, bbox$xmax, bbox$ymax, crs = epsgCode) 
  for(subject in entity$subjects){
    kwds <- subject$keywords
    for(kwd in kwds) featureType$addKeyword(kwd$name)
  }
  
  #cql filter?
  if(!is.null(entity$data$cqlfilter)){
    featureType$setCqlFilter(entity$data$cqlfilter)
  }
  
  #virtual table?
  if(entity$data$uploadType == "dbquery"){
    vt <- GSVirtualTable$new()
    vt$setName(layername)
    vt$setSql(entity$data$sql)
    #if the virtual table is spatialized
    if(!is.null(entity$data$geometryField) & !is.null(entity$data$geometryType)){
      vtg <- GSVirtualTableGeometry$new(
        name = entity$data$geometryField, 
        type = entity$data$geometryType, 
        srid = entity$srid
      )
      vt$setGeometry(vtg)
    }
    #if the virtual table has service parameters
    if(length(entity$data$parameters)){
      for(param in entity$data$parameters){
        vtp <- GSVirtualTableParameter$new(
          name = param$name, 
          defaultValue = param$defaultvalue, 
          regexpValidator = param$regexp
        )
        vt$addParameter(vtp)
      }
    }
    featureType$setVirtualTable(vt)
  }
  
  #add metadata links
  #in case (only if) geoflow defines either CSW or Geonetwork software, we can add metadata links
  md_link_xml <- NULL
  md_link_html <- NULL
  if(!is.null(config$software$output$csw)|!is.null(config$software$output$geonetwork)){
    if(!is.null(config$software$output$csw)){
      md_link_xml <- paste0(config$software$output$csw_config$parameters$url, "?service=CSW&request=GetRecordById&Version=", config$software$output$csw_config$parameters$version,
                            "&elementSetName=full&outputSchema=http%3A//www.isotc211.org/2005/gmd&id=", entity$identifiers[["id"]])
    }
    if(!is.null(config$software$output$geonetwork)){
      md_link_xml <- paste0(config$software$output$geonetwork_config$parameters$url, "/srv/eng/csw?service=CSW&request=GetRecordById&Version=2.0.2",
                            "&elementSetName=full&outputSchema=http%3A//www.isotc211.org/2005/gmd&id=", entity$identifiers[["id"]])
      if(startsWith(config$software$output$geonetwork_config$parameters$version, "2")){
        md_link_html <- paste0(config$software$output$geonetwork_config$parameters$url, "/srv/en/main.home?uuid=", entity$identifiers[["id"]])
      }else if(startsWith(config$software$output$geonetwork_config$parameters$version, "3")){
        md_link_html <- paste0(config$software$output$geonetwork_config$parameters$url, "/srv/eng/catalog.search#/metadata/", entity$identifiers[["id"]])
      }
    }
  }
  if(!is.null(md_link_xml)){
    md_xml <- GSMetadataLink$new(type = "text/xml", metadataType = "ISO19115:2003", content = md_link_xml)
    featureType$addMetadataLink(md_xml)
  }
  if(!is.null(md_link_html)){
    md_html <- GSMetadataLink$new(type = "text/html", metadataType = "ISO19115:2003", content = md_link_html)
    featureType$addMetadataLink(md_html)
  }
  
  #build layer
  layer <- GSLayer$new()
  layer$setName(layername)
  if(length(entity$data$styles)>0){
    for(i in 1:length(entity$data$styles)){
      style <- entity$data$styles[i]
      if(i==1) layer$setDefaultStyle(style) else layer$addStyle(style)
    }
  }else{
    layer$setDefaultStyle("generic")
  }

  #publish
  try(GS$unpublishLayer(workspace, datastore, layername))
  out <- GS$publishLayer(workspace, datastore, featureType, layer)
  if(!out){
    errMsg <- sprintf("Error during layer '%s' publication for entity '%s'!",layername, entity$identifiers[["id"]])
    config$logger.error(errMsg)
  }else{
    infoMsg <- sprintf("Successful layer'%s' publication in Geoserver for entity '%s'!", layername, entity$identifiers[["id"]])
  }
  
}