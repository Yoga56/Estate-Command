CLASS zcl_est_geo DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Geometry the scheduler needs (port of the geometry part of gis/models/scheduler.py):
    "! distances, which blocks share a boundary, and "14-19, 23" labels.
    TYPES:
      BEGIN OF ty_point,
        lon TYPE f,
        lat TYPE f,
      END OF ty_point,
      ty_ring TYPE STANDARD TABLE OF ty_point WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_shape,
        block_key TYPE zest_block-block_key,
        centroid  TYPE ty_point,
        ring      TYPE ty_ring,
      END OF ty_shape,
      ty_shapes TYPE STANDARD TABLE OF ty_shape WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_pair,
        block_key TYPE zest_block-block_key,
        neighbour TYPE zest_block-block_key,
      END OF ty_pair,
      ty_adjacency TYPE HASHED TABLE OF ty_pair WITH UNIQUE KEY block_key neighbour.
    TYPES ty_codes TYPE STANDARD TABLE OF zest_block-block_code WITH EMPTY KEY.

    "! "lon lat,lon lat,..." as stored in ZEST_BLOCK-GEOMETRY
    CLASS-METHODS parse_ring
      IMPORTING geometry      TYPE string
      RETURNING VALUE(result) TYPE ty_ring.

    CLASS-METHODS format_ring
      IMPORTING ring          TYPE ty_ring
      RETURNING VALUE(result) TYPE string.

    "! Mean of the vertices, the closing vertex counted once
    CLASS-METHODS centroid
      IMPORTING ring          TYPE ty_ring
      RETURNING VALUE(result) TYPE ty_point.

    "! Equirectangular distance; good to a few metres across one estate
    CLASS-METHODS km
      IMPORTING a             TYPE ty_point
                b             TYPE ty_point
      RETURNING VALUE(result) TYPE f.

    "! Two blocks are adjacent when a vertex of one lies within about 55 m of a vertex of the
    "! other. A grid hash keeps it linear. Blocks without a polygon fall back to centroids
    "! closer than FALLBACK_KM.
    CLASS-METHODS adjacency
      IMPORTING shapes        TYPE ty_shapes
                fallback_km   TYPE f DEFAULT '0.6'
      RETURNING VALUE(result) TYPE ty_adjacency.

    "! '14-19, 23, 31-33' from block codes; codes that are not numbers are listed as they are
    CLASS-METHODS range_label
      IMPORTING codes         TYPE ty_codes
      RETURNING VALUE(result) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CONSTANTS cell_degrees TYPE f VALUE '0.0005'.
ENDCLASS.



CLASS zcl_est_geo IMPLEMENTATION.

  METHOD parse_ring.
    SPLIT geometry AT ',' INTO TABLE DATA(pairs).
    LOOP AT pairs INTO DATA(pair).
      CONDENSE pair.
      SPLIT pair AT space INTO DATA(lon) DATA(lat).
      CHECK lon IS NOT INITIAL AND lat IS NOT INITIAL.
      TRY.
          APPEND VALUE #( lon = CONV f( lon ) lat = CONV f( lat ) ) TO result.
        CATCH cx_sy_conversion_error.
          CONTINUE.
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.


  METHOD format_ring.
    LOOP AT ring INTO DATA(point).
      DATA(lon) = CONV decfloat34( round( val = CONV decfloat34( point-lon ) dec = 6 ) ).
      DATA(lat) = CONV decfloat34( round( val = CONV decfloat34( point-lat ) dec = 6 ) ).
      result = COND #( WHEN result IS INITIAL THEN |{ lon } { lat }| ELSE |{ result },{ lon } { lat }| ).
    ENDLOOP.
  ENDMETHOD.


  METHOD centroid.
    DATA(count) = lines( ring ).
    CHECK count > 0.
    " a closed ring repeats its first vertex at the end
    IF count > 1 AND ring[ 1 ] = ring[ count ].
      count = count - 1.
    ENDIF.
    DO count TIMES.
      result-lon = result-lon + ring[ sy-index ]-lon.
      result-lat = result-lat + ring[ sy-index ]-lat.
    ENDDO.
    result-lon = result-lon / count.
    result-lat = result-lat / count.
  ENDMETHOD.


  METHOD km.
    CONSTANTS km_per_degree TYPE f VALUE '111.32'.
    CONSTANTS pi TYPE f VALUE '3.14159265358979'.
    DATA(lat) = ( a-lat + b-lat ) / 2 * pi / 180.
    DATA(dx) = ( a-lon - b-lon ) * km_per_degree * cos( lat ).
    DATA(dy) = ( a-lat - b-lat ) * km_per_degree.
    result = sqrt( dx * dx + dy * dy ).
  ENDMETHOD.


  METHOD adjacency.
    TYPES:
      BEGIN OF ty_cell,
        x         TYPE int8,
        y         TYPE int8,
        block_key TYPE zest_block-block_key,
      END OF ty_cell.
    DATA grid TYPE SORTED TABLE OF ty_cell WITH NON-UNIQUE KEY x y.

    LOOP AT shapes INTO DATA(shape) WHERE ring IS NOT INITIAL.
      LOOP AT shape-ring INTO DATA(point).
        DATA(cell) = VALUE ty_cell( x         = CONV int8( floor( point-lon / cell_degrees ) )
                                    y         = CONV int8( floor( point-lat / cell_degrees ) )
                                    block_key = shape-block_key ).
        CHECK NOT line_exists( grid[ x = cell-x y = cell-y block_key = cell-block_key ] ).
        INSERT cell INTO TABLE grid.
      ENDLOOP.
    ENDLOOP.

    LOOP AT grid INTO DATA(own).
      DO 3 TIMES.
        DATA(nx) = own-x + sy-index - 2.
        DO 3 TIMES.
          DATA(ny) = own-y + sy-index - 2.
          LOOP AT grid INTO DATA(other) WHERE x = nx AND y = ny.
            CHECK other-block_key <> own-block_key.
            INSERT VALUE #( block_key = own-block_key neighbour = other-block_key ) INTO TABLE result.
          ENDLOOP.
        ENDDO.
      ENDDO.
    ENDLOOP.

    " blocks known only by their centroid
    LOOP AT shapes INTO DATA(lonely) WHERE ring IS INITIAL.
      LOOP AT shapes INTO DATA(near) WHERE block_key <> lonely-block_key.
        CHECK km( a = lonely-centroid b = near-centroid ) <= fallback_km.
        INSERT VALUE #( block_key = lonely-block_key neighbour = near-block_key ) INTO TABLE result.
        INSERT VALUE #( block_key = near-block_key neighbour = lonely-block_key ) INTO TABLE result.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD range_label.
    DATA numbers TYPE SORTED TABLE OF i WITH UNIQUE KEY table_line.
    DATA others TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    LOOP AT codes INTO DATA(code).
      DATA(text) = condense( CONV string( code ) ).
      IF text CO '0123456789' AND text IS NOT INITIAL.
        INSERT CONV i( text ) INTO TABLE numbers.
      ELSEIF text IS NOT INITIAL.
        APPEND text TO others.
      ENDIF.
    ENDLOOP.

    DATA(parts) = VALUE string_table( ).
    DATA(start) = -1.
    DATA(previous) = -1.
    LOOP AT numbers INTO DATA(number).
      IF start = -1.
        start = number.
      ELSEIF number <> previous + 1.
        APPEND COND string( WHEN start = previous THEN |{ start }| ELSE |{ start }-{ previous }| ) TO parts.
        start = number.
      ENDIF.
      previous = number.
    ENDLOOP.
    IF start <> -1.
      APPEND COND string( WHEN start = previous THEN |{ start }| ELSE |{ start }-{ previous }| ) TO parts.
    ENDIF.
    APPEND LINES OF others TO parts.

    result = concat_lines_of( table = parts sep = `, ` ).
  ENDMETHOD.

ENDCLASS.
