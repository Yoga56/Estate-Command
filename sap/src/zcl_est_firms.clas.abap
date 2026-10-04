CLASS zcl_est_firms DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Active fires around an estate from NASA FIRMS (firms.modaps.eosdis.nasa.gov): the VIIRS and
    "! MODIS hotspots of the last days within a radius of the estate's blocks, each with its
    "! distance to the nearest block. Optional: without the communication arrangement or a map key
    "! the answer says the fires are unknown - it never invents a hotspot.
    TYPES:
      BEGIN OF ty_hotspot,
        hotspot_id    TYPE string,
        latitude      TYPE decfloat34,
        longitude     TYPE decfloat34,
        acq_date      TYPE d,
        "! HHMM, UTC
        acq_time      TYPE string,
        "! FIRMS product, e.g. VIIRS_NOAA20_NRT
        product       TYPE string,
        satellite     TYPE string,
        instrument    TYPE string,
        "! low / nominal / high (MODIS percentages mapped to the same three)
        confidence    TYPE string,
        "! fire radiative power, MW
        frp           TYPE decfloat34,
        "! brightness temperature, K
        brightness    TYPE decfloat34,
        daynight      TYPE string,
        distance_km   TYPE decfloat34,
        nearest_block TYPE string,
        inside        TYPE abap_bool,
      END OF ty_hotspot,
      ty_hotspots TYPE STANDARD TABLE OF ty_hotspot WITH EMPTY KEY,
      BEGIN OF ty_result,
        known     TYPE abap_bool,
        status    TYPE string,
        radius_km TYPE decfloat34,
        days      TYPE i,
        hotspots  TYPE ty_hotspots,
      END OF ty_result.

    CONSTANTS comm_scenario TYPE string VALUE `ZEST_FIRMS`.
    CONSTANTS outbound_service TYPE string VALUE `ZEST_FIRMS_REST`.
    "! The provider row whose API key is the FIRMS map key, when the arrangement has no MAP_KEY
    "! property. It is inactive: it is never offered as an AI provider.
    CONSTANTS key_row TYPE zest_ai_prov-provider_id VALUE 'FIRMS'.
    CONSTANTS key_property TYPE string VALUE `MAP_KEY`.

    CLASS-METHODS around
      IMPORTING estate        TYPE zest_estate-estate
      RETURNING VALUE(result) TYPE ty_result.

    "! The map key: arrangement property MAP_KEY, else the API key of provider row FIRMS. Spaces
    "! and line breaks pasted with it are removed; FIRMS keys are 32 letters and digits.
    CLASS-METHODS map_key
      RETURNING VALUE(result) TYPE string
      RAISING   zcx_est_ai.

    "! FIRMS' own answer on the key (/api/map_key): its transaction limit and use, or why not
    CLASS-METHODS check_key
      RETURNING VALUE(result) TYPE string.

    "! The area path for an estate as it is sent, the key masked - for the error text and the test
    CLASS-METHODS request_path
      IMPORTING product       TYPE string
                area          TYPE string
                days          TYPE i
                key           TYPE string
      RETURNING VALUE(result) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    "! the near-real-time products of the three VIIRS satellites and MODIS
    CONSTANTS products TYPE string VALUE `VIIRS_SNPP_NRT,VIIRS_NOAA20_NRT,VIIRS_NOAA21_NRT,MODIS_NRT`.
    CONSTANTS km_per_degree TYPE f VALUE '111.32'.
    CONSTANTS pi TYPE f VALUE '3.14159265358979'.

    CLASS-METHODS parse
      IMPORTING csv           TYPE string
                product       TYPE string
      RETURNING VALUE(result) TYPE ty_hotspots
      RAISING   zcx_est_ai.

    CLASS-METHODS coordinate
      IMPORTING value         TYPE f
      RETURNING VALUE(result) TYPE string.

    CLASS-METHODS inside
      IMPORTING point         TYPE zcl_est_geo=>ty_point
                ring          TYPE zcl_est_geo=>ty_ring
      RETURNING VALUE(result) TYPE abap_bool.
ENDCLASS.



CLASS zcl_est_firms IMPLEMENTATION.

  METHOD around.
    DATA hotspots TYPE ty_hotspots.
    DATA south TYPE f VALUE 90.
    DATA north TYPE f VALUE -90.
    DATA west TYPE f VALUE 180.
    DATA east TYPE f VALUE -180.

    result-radius_km = zcl_est_assumptions=>value( 'fire_radius_km' ).
    IF result-radius_km <= 0.
      result-radius_km = 10.
    ENDIF.
    result-days = CONV i( zcl_est_assumptions=>value( 'fire_days' ) ).
    " the area API takes a day range of 1 to 5
    IF result-days < 1.
      result-days = 3.
    ELSEIF result-days > 5.
      result-days = 5.
    ENDIF.

    SELECT block_label, centroid_lon, centroid_lat, geometry FROM zest_block
      WHERE estate = @estate
      INTO TABLE @DATA(blocks).
    SELECT SINGLE latitude, longitude FROM zest_estate WHERE estate = @estate INTO @DATA(position).

    LOOP AT blocks INTO DATA(block) WHERE centroid_lat IS NOT INITIAL OR centroid_lon IS NOT INITIAL.
      south = nmin( val1 = south val2 = CONV f( block-centroid_lat ) ).
      north = nmax( val1 = north val2 = CONV f( block-centroid_lat ) ).
      west  = nmin( val1 = west  val2 = CONV f( block-centroid_lon ) ).
      east  = nmax( val1 = east  val2 = CONV f( block-centroid_lon ) ).
    ENDLOOP.
    IF south > north.
      IF position IS INITIAL.
        result-status = `unknown: the estate has no blocks and no coordinates`.
        RETURN.
      ENDIF.
      south = position-latitude.
      north = position-latitude.
      west  = position-longitude.
      east  = position-longitude.
    ENDIF.

    DATA(radius) = CONV f( result-radius_km ).
    DATA(margin_lat) = radius / km_per_degree.
    DATA(margin_lon) = radius / ( km_per_degree * cos( ( south + north ) / 2 * pi / 180 ) ).
    DATA(area) = |{ coordinate( west - margin_lon ) },{ coordinate( south - margin_lat ) },| &&
                 |{ coordinate( east + margin_lon ) },{ coordinate( north + margin_lat ) }|.

    TRY.
        DATA(key) = map_key( ).
      CATCH zcx_est_ai INTO DATA(no_key).
        result-status = |unknown: { no_key->get_text( ) }|.
        RETURN.
    ENDTRY.

    DATA failures TYPE string_table.
    SPLIT products AT ',' INTO TABLE DATA(product_list).
    LOOP AT product_list INTO DATA(product).
      TRY.
          DATA(csv) = zcl_est_ai_http=>get( comm_scenario    = comm_scenario
                                            outbound_service = outbound_service
                                            path             = request_path( product = product area = area
                                                                             days = result-days key = key ) ).
          APPEND LINES OF parse( csv = csv product = product ) TO hotspots.
          result-known = abap_true.
        CATCH zcx_est_ai INTO DATA(error).
          DATA(masked) = request_path( product = product area = area days = result-days key = `***` ).
          APPEND |{ product }: { error->get_text( ) } - request { masked }| TO failures.
      ENDTRY.
    ENDLOOP.

    IF result-known = abap_false.
      result-status = |unknown: { VALUE #( failures[ 1 ] OPTIONAL ) }|.
      RETURN.
    ENDIF.

    " each hotspot: the nearest block, and whether it burns inside one
    DATA shapes TYPE STANDARD TABLE OF zcl_est_geo=>ty_shape WITH EMPTY KEY.
    LOOP AT blocks INTO block.
      APPEND VALUE #( block_key = block-block_label
                      centroid  = VALUE #( lon = block-centroid_lon lat = block-centroid_lat )
                      ring      = zcl_est_geo=>parse_ring( block-geometry ) ) TO shapes.
    ENDLOOP.
    LOOP AT hotspots ASSIGNING FIELD-SYMBOL(<hotspot>).
      DATA(point) = VALUE zcl_est_geo=>ty_point( lon = <hotspot>-longitude lat = <hotspot>-latitude ).
      DATA(best) = CONV f( -1 ).
      LOOP AT shapes INTO DATA(shape).
        DATA(km) = zcl_est_geo=>km( a = point b = shape-centroid ).
        IF best < 0 OR km < best.
          best = km.
          <hotspot>-nearest_block = shape-block_key.
        ENDIF.
        IF <hotspot>-inside = abap_false AND lines( shape-ring ) >= 3 AND inside( point = point ring = shape-ring ).
          <hotspot>-inside = abap_true.
          <hotspot>-nearest_block = shape-block_key.
        ENDIF.
      ENDLOOP.
      IF best < 0.
        best = zcl_est_geo=>km( a = point b = VALUE #( lon = position-longitude lat = position-latitude ) ).
      ENDIF.
      <hotspot>-distance_km = COND decfloat34( WHEN <hotspot>-inside = abap_true THEN 0
                                               ELSE round( val = CONV decfloat34( best ) dec = 2 ) ).
    ENDLOOP.
    " the box is wider than the circle at its corners
    DELETE hotspots WHERE distance_km > result-radius_km.
    SORT hotspots BY distance_km acq_date DESCENDING acq_time DESCENDING.
    result-hotspots = hotspots.

    DATA(burning) = REDUCE i( INIT n = 0 FOR h IN hotspots WHERE ( inside = abap_true ) NEXT n = n + 1 ).
    result-status = |NASA FIRMS, last { result-days } day(s), within { result-radius_km } km: | &&
                    COND #( WHEN hotspots IS INITIAL THEN `no fire hotspots`
                            WHEN burning > 0 THEN |{ lines( hotspots ) } hotspot(s), { burning } inside the estate|
                            ELSE |{ lines( hotspots ) } hotspot(s), the nearest { hotspots[ 1 ]-distance_km } km from block | &&
                                 |{ hotspots[ 1 ]-nearest_block }| ).
    IF failures IS NOT INITIAL.
      result-status = |{ result-status } (not read: { concat_lines_of( table = failures sep = `; ` ) })|.
    ENDIF.
  ENDMETHOD.


  METHOD map_key.
    " a missing arrangement is the first thing to say: without it there is no host to call
    result = zcl_est_ai_http=>property( comm_scenario = comm_scenario name = key_property ).
    IF result IS INITIAL.
      SELECT SINGLE api_key FROM zest_ai_prov WHERE provider_id = @key_row INTO @result.
    ENDIF.
    " a key copied from the e-mail often brings a space or a line break along
    result = replace( val = result pcre = `[^A-Za-z0-9]` with = `` occ = 0 ).
    IF result IS INITIAL.
      RAISE EXCEPTION NEW zcx_est_ai(
        message = |no FIRMS map key: enter it as API key of AI provider row { key_row }, or as arrangement property { key_property }| ).
    ENDIF.
    IF strlen( result ) <> 32.
      RAISE EXCEPTION NEW zcx_est_ai(
        message = |the FIRMS map key in row { key_row } has { strlen( result ) } letters and digits; a FIRMS key has 32| ).
    ENDIF.
  ENDMETHOD.


  METHOD check_key.
    TRY.
        DATA(key) = map_key( ).
        result = zcl_est_ai_http=>get( comm_scenario    = comm_scenario
                                       outbound_service = outbound_service
                                       path             = |/api/map_key/?MAP_KEY={ key }| ).
        result = |key { substring( val = key len = 4 ) }...: { condense( substring( val = result
                                                      len = nmin( val1 = 300 val2 = strlen( result ) ) ) ) }|.
      CATCH zcx_est_ai INTO DATA(error).
        result = error->get_text( ).
    ENDTRY.
  ENDMETHOD.


  METHOD request_path.
    result = |/api/area/csv/{ key }/{ product }/{ area }/{ days }|.
  ENDMETHOD.


  METHOD parse.
    " latitude,longitude,bright_ti4|brightness,scan,track,acq_date,acq_time,satellite,instrument,
    " confidence,version,bright_ti5|bright_t31,frp,daynight
    DATA(text) = csv.
    DATA(cr) = substring( val = cl_abap_char_utilities=>cr_lf len = 1 ).
    REPLACE ALL OCCURRENCES OF cr IN text WITH ``.
    SPLIT text AT cl_abap_char_utilities=>newline INTO TABLE DATA(rows).
    DELETE rows WHERE table_line IS INITIAL.
    IF rows IS INITIAL.
      RETURN.
    ENDIF.

    DATA(header) = rows[ 1 ].
    IF NOT header CP 'latitude,longitude*'.
      " FIRMS answers a wrong key or area with a line of text instead of the CSV
      RAISE EXCEPTION NEW zcx_est_ai(
        message = |FIRMS: { substring( val = header len = nmin( val1 = 160 val2 = strlen( header ) ) ) }| ).
    ENDIF.
    SPLIT header AT ',' INTO TABLE DATA(names).
    DATA(col_lat)        = line_index( names[ table_line = `latitude` ] ).
    DATA(col_lon)        = line_index( names[ table_line = `longitude` ] ).
    DATA(col_date)       = line_index( names[ table_line = `acq_date` ] ).
    DATA(col_time)       = line_index( names[ table_line = `acq_time` ] ).
    DATA(col_satellite)  = line_index( names[ table_line = `satellite` ] ).
    DATA(col_instrument) = line_index( names[ table_line = `instrument` ] ).
    DATA(col_confidence) = line_index( names[ table_line = `confidence` ] ).
    DATA(col_frp)        = line_index( names[ table_line = `frp` ] ).
    DATA(col_daynight)   = line_index( names[ table_line = `daynight` ] ).
    DATA(col_bright)     = line_index( names[ table_line = `bright_ti4` ] ).
    IF col_bright = 0.
      col_bright = line_index( names[ table_line = `brightness` ] ).
    ENDIF.

    LOOP AT rows INTO DATA(row) FROM 2.
      SPLIT row AT ',' INTO TABLE DATA(cells).
      DATA(hotspot) = VALUE ty_hotspot(
        product    = product
        satellite  = VALUE #( cells[ col_satellite ] OPTIONAL )
        instrument = VALUE #( cells[ col_instrument ] OPTIONAL )
        daynight   = VALUE #( cells[ col_daynight ] OPTIONAL ) ).
      TRY.
          hotspot-latitude   = CONV decfloat34( cells[ col_lat ] ).
          hotspot-longitude  = CONV decfloat34( cells[ col_lon ] ).
          hotspot-frp        = CONV decfloat34( VALUE string( cells[ col_frp ] DEFAULT `0` ) ).
          hotspot-brightness = CONV decfloat34( VALUE string( cells[ col_bright ] DEFAULT `0` ) ).
          hotspot-acq_date   = CONV d( replace( val = cells[ col_date ] sub = `-` with = `` occ = 0 ) ).
        CATCH cx_sy_conversion_error cx_sy_itab_line_not_found.
          CONTINUE.
      ENDTRY.
      DATA(time) = VALUE string( cells[ col_time ] OPTIONAL ).
      hotspot-acq_time = |{ time ALIGN = RIGHT WIDTH = 4 PAD = '0' }|.

      " VIIRS says l / n / h, MODIS a percentage
      DATA(confidence) = to_lower( VALUE string( cells[ col_confidence ] OPTIONAL ) ).
      hotspot-confidence = SWITCH #( confidence
        WHEN `l` OR `low` THEN `low`
        WHEN `n` OR `nominal` THEN `nominal`
        WHEN `h` OR `high` THEN `high`
        ELSE COND #( WHEN confidence CO '0123456789' AND confidence IS NOT INITIAL
                     THEN COND #( WHEN CONV i( confidence ) < 30 THEN `low`
                                  WHEN CONV i( confidence ) < 80 THEN `nominal`
                                  ELSE `high` )
                     ELSE confidence ) ).
      hotspot-hotspot_id = |{ substring( val = product len = 5 ) }{ hotspot-acq_date }{ hotspot-acq_time }| &&
                           |{ coordinate( CONV f( hotspot-latitude ) ) }{ coordinate( CONV f( hotspot-longitude ) ) }|.
      APPEND hotspot TO result.
    ENDLOOP.
  ENDMETHOD.


  METHOD coordinate.
    DATA(rounded) = round( val = CONV decfloat34( value ) dec = 4 ).
    result = |{ rounded DECIMALS = 4 }|.
  ENDMETHOD.


  METHOD inside.
    " even-odd ray casting
    DATA(count) = lines( ring ).
    DATA(j) = count.
    DO count TIMES.
      DATA(i) = sy-index.
      DATA(a) = ring[ i ].
      DATA(b) = ring[ j ].
      IF xsdbool( a-lat > point-lat ) <> xsdbool( b-lat > point-lat ).
        IF point-lon < ( b-lon - a-lon ) * ( point-lat - a-lat ) / ( b-lat - a-lat ) + a-lon.
          result = xsdbool( result = abap_false ).
        ENDIF.
      ENDIF.
      j = i.
    ENDDO.
  ENDMETHOD.

ENDCLASS.
