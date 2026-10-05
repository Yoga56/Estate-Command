CLASS zcl_est_fire_query DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Query provider of the custom entity ZI_EST_FIRE: reads NASA FIRMS on each request. Filter
    "! on Estate. Per estate one row with IsStatus set says what was read (or why not), then one
    "! row per hotspot, nearest first.
    INTERFACES if_rap_query_provider.
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcl_est_fire_query IMPLEMENTATION.

  METHOD if_rap_query_provider~select.
    DATA rows TYPE STANDARD TABLE OF zi_est_fire WITH EMPTY KEY.
    DATA estates TYPE RANGE OF zest_estate-estate.

    TRY.
        DATA(ranges) = io_request->get_filter( )->get_as_ranges( ).
      CATCH cx_rap_query_filter_no_range.
        CLEAR ranges.
    ENDTRY.
    LOOP AT ranges INTO DATA(range) WHERE name = 'ESTATE'.
      estates = CORRESPONDING #( range-range ).
    ENDLOOP.

    " every hotspot read costs FIRMS transactions: one estate unless the filter asks for more
    SELECT estate FROM zest_estate WHERE estate IN @estates ORDER BY estate INTO TABLE @DATA(selected).
    LOOP AT selected INTO DATA(estate).
      DATA(fires) = zcl_est_firms=>around( estate-estate ).
      APPEND VALUE #( estate      = estate-estate
                      hotspotid   = 'STATUS'
                      isstatus    = abap_true
                      statustext  = fires-status
                      radiuskm    = fires-radius_km
                      watchdays   = fires-days
                      criticality = COND #( WHEN fires-known = abap_false THEN 0
                                            WHEN fires-hotspots IS INITIAL THEN 3
                                            WHEN line_exists( fires-hotspots[ inside = abap_true ] ) THEN 1
                                            ELSE 2 ) ) TO rows.
      LOOP AT fires-hotspots INTO DATA(hotspot).
        APPEND VALUE #( estate       = estate-estate
                        hotspotid    = hotspot-hotspot_id
                        radiuskm     = fires-radius_km
                        watchdays    = fires-days
                        latitude     = hotspot-latitude
                        longitude    = hotspot-longitude
                        acqdate      = hotspot-acq_date
                        acqtime      = hotspot-acq_time
                        product      = hotspot-product
                        satellite    = hotspot-satellite
                        instrument   = hotspot-instrument
                        confidence   = hotspot-confidence
                        criticality  = COND #( WHEN hotspot-inside = abap_true OR hotspot-distance_km <= 2 THEN 1 ELSE 2 )
                        frp          = hotspot-frp
                        brightness   = hotspot-brightness
                        daynight     = hotspot-daynight
                        distancekm   = hotspot-distance_km
                        nearestblock = hotspot-nearest_block
                        isinside     = hotspot-inside ) TO rows.
      ENDLOOP.
    ENDLOOP.

    IF io_request->is_total_numb_of_rec_requested( ).
      io_response->set_total_number_of_records( lines( rows ) ).
    ENDIF.

    IF io_request->is_data_requested( ).
      DATA(offset) = io_request->get_paging( )->get_offset( ).
      DATA(page_size) = io_request->get_paging( )->get_page_size( ).
      IF offset > 0.
        DELETE rows TO offset.
      ENDIF.
      IF page_size > 0 AND page_size <> if_rap_query_paging=>page_size_unlimited AND lines( rows ) > page_size.
        DELETE rows FROM page_size + 1.
      ENDIF.
      io_response->set_data( rows ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
