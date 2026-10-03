CLASS zcl_est_data DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! One estate's state, read once per request: blocks, crews, attendance, the work-order
    "! ledger and the upkeep rounds (port of gis/ops.py _state). Nothing here writes.
    TYPES:
      BEGIN OF ty_block,
        block_key      TYPE zest_block-block_key,
        division       TYPE zest_block-division,
        block_code     TYPE zest_block-block_code,
        label          TYPE zest_block-block_label,
        planted_ha     TYPE decfloat34,
        palms          TYPE i,
        abw_kg         TYPE decfloat34,
        rotation_days  TYPE i,
        gang_code      TYPE zest_block-gang_code,
        road_condition TYPE zest_block-road_condition,
        bunches_per_day TYPE decfloat34,
        centroid       TYPE zcl_est_geo=>ty_point,
        ring           TYPE zcl_est_geo=>ty_ring,
      END OF ty_block,
      ty_blocks TYPE HASHED TABLE OF ty_block WITH UNIQUE KEY block_key.
    TYPES:
      BEGIN OF ty_crew,
        crew_code     TYPE zest_crew-crew_code,
        crew_type     TYPE zest_crew-crew_type,
        crew_name     TYPE zest_crew-crew_name,
        division      TYPE zest_crew-division,
        establishment TYPE i,
        harvesters    TYPE i,
        home_block    TYPE zest_crew-home_block,
        home_key      TYPE zest_block-block_key,
        home          TYPE zcl_est_geo=>ty_point,
      END OF ty_crew,
      ty_crews TYPE STANDARD TABLE OF ty_crew WITH EMPTY KEY.
    TYPES ty_orders TYPE STANDARD TABLE OF zest_workord WITH EMPTY KEY.
    TYPES ty_attendance TYPE SORTED TABLE OF zest_attend WITH UNIQUE KEY crew_code work_date.
    TYPES ty_upkeep TYPE HASHED TABLE OF zest_upkeep WITH UNIQUE KEY block_key activity.
    TYPES:
      "! Tomorrow's headcount for one crew
      BEGIN OF ty_present,
        on_roll        TYPE i,
        present        TYPE i,
        attendance_pct TYPE decfloat34,
        basis          TYPE string,
      END OF ty_present.

    CONSTANTS:
      BEGIN OF op,
        harvest TYPE zest_plan-operation VALUE 'harvest',
        prune   TYPE zest_plan-operation VALUE 'prune',
        weed    TYPE zest_plan-operation VALUE 'weed',
        spray   TYPE zest_plan-operation VALUE 'spray',
      END OF op.

    DATA estate TYPE zest_estate READ-ONLY.
    DATA blocks TYPE ty_blocks READ-ONLY.
    DATA crews TYPE ty_crews READ-ONLY.
    DATA attendance TYPE ty_attendance READ-ONLY.
    "! sorted by date and order id
    DATA orders TYPE ty_orders READ-ONLY.
    DATA upkeep TYPE ty_upkeep READ-ONLY.
    "! where vehicles and crews without a home block start: south-west of every block
    DATA mill TYPE zcl_est_geo=>ty_point READ-ONLY.

    METHODS constructor
      IMPORTING estate_code TYPE zest_estate-estate
      RAISING   zcx_est_ai.

    "! The operations this release plans, lower case as in the ledger
    CLASS-METHODS operations
      RETURNING VALUE(result) TYPE string_table.

    "! Crew type that carries out an operation
    CLASS-METHODS crew_type_of
      IMPORTING operation     TYPE csequence
      RETURNING VALUE(result) TYPE zest_crew-crew_type.

    "! Ledger activities of an operation
    CLASS-METHODS activities_of
      IMPORTING operation     TYPE csequence
      RETURNING VALUE(result) TYPE string_table.

    CLASS-METHODS unit_of
      IMPORTING operation     TYPE csequence
      RETURNING VALUE(result) TYPE string.

    "! A number for a prompt or a sentence: rounded, trailing zeros dropped, no separators
    CLASS-METHODS num
      IMPORTING value         TYPE decfloat34
                decimals      TYPE i DEFAULT 2
      RETURNING VALUE(result) TYPE string.

    "! The first day beyond the estate's data: what "tomorrow" means for it
    METHODS default_plan_date
      RETURNING VALUE(result) TYPE d.

    "! The last day the ledger holds; today for a live estate
    METHODS data_end
      RETURNING VALUE(result) TYPE d.

    "! Recorded attendance on the day if the ledger has it, else the crew's mean attendance over
    "! the LOOKBACK days before, applied to its roll (0.85 when nothing is recorded)
    METHODS expected_present
      IMPORTING crew_code     TYPE zest_crew-crew_code
                on            TYPE d
                lookback      TYPE i
      RETURNING VALUE(result) TYPE ty_present.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcl_est_data IMPLEMENTATION.

  METHOD constructor.
    SELECT SINGLE * FROM zest_estate WHERE estate = @estate_code INTO @estate.
    IF sy-subrc <> 0.
      RAISE EXCEPTION NEW zcx_est_ai(
        message = |Estate { estate_code } does not exist; run ZCL_EST_SEED or import its blocks| ).
    ENDIF.

    SELECT * FROM zest_block WHERE estate = @estate_code INTO TABLE @DATA(block_rows).
    LOOP AT block_rows INTO DATA(row).
      DATA(block) = VALUE ty_block(
        block_key       = row-block_key
        division        = row-division
        block_code      = row-block_code
        label           = COND #( WHEN row-block_label IS NOT INITIAL THEN row-block_label ELSE row-block_key )
        planted_ha      = row-planted_ha
        palms           = row-palms
        abw_kg          = row-abw_kg
        rotation_days   = row-rotation_days
        gang_code       = row-gang_code
        road_condition  = row-road_condition
        bunches_per_day = row-bunches_per_day
        ring            = zcl_est_geo=>parse_ring( row-geometry ) ).
      block-centroid = COND #( WHEN row-centroid_lon IS NOT INITIAL
                               THEN VALUE #( lon = CONV f( row-centroid_lon ) lat = CONV f( row-centroid_lat ) )
                               ELSE zcl_est_geo=>centroid( block-ring ) ).
      INSERT block INTO TABLE blocks.
    ENDLOOP.

    IF blocks IS NOT INITIAL.
      mill-lon = 999.
      mill-lat = 999.
      LOOP AT blocks INTO block.
        mill-lon = nmin( val1 = mill-lon val2 = block-centroid-lon ).
        mill-lat = nmin( val1 = mill-lat val2 = block-centroid-lat ).
      ENDLOOP.
      mill-lon = mill-lon - '0.012'.
      mill-lat = mill-lat - '0.010'.
    ENDIF.

    SELECT * FROM zest_crew WHERE estate = @estate_code ORDER BY crew_code INTO TABLE @DATA(crew_rows).
    LOOP AT crew_rows INTO DATA(crew_row).
      DATA(crew) = CORRESPONDING ty_crew( crew_row ).
      LOOP AT blocks INTO block WHERE label = crew_row-home_block OR block_key = crew_row-home_block.
        crew-home_key = block-block_key.
        crew-home     = block-centroid.
        EXIT.
      ENDLOOP.
      IF crew-home_key IS INITIAL.
        crew-home = mill.
      ENDIF.
      APPEND crew TO crews.
    ENDLOOP.

    SELECT * FROM zest_attend WHERE estate = @estate_code INTO TABLE @attendance.
    SELECT * FROM zest_workord WHERE estate = @estate_code ORDER BY work_date, order_id INTO TABLE @orders.
    SELECT * FROM zest_upkeep WHERE estate = @estate_code INTO TABLE @upkeep.
  ENDMETHOD.


  METHOD operations.
    result = VALUE #( ( `harvest` ) ( `prune` ) ( `weed` ) ( `spray` ) ).
  ENDMETHOD.


  METHOD crew_type_of.
    result = SWITCH #( to_lower( operation )
                       WHEN op-harvest THEN 'harvest'
                       WHEN op-spray   THEN 'spray'
                       ELSE 'upkeep' ).
  ENDMETHOD.


  METHOD activities_of.
    result = SWITCH #( to_lower( operation )
                       WHEN op-harvest THEN VALUE #( ( `harvest` ) )
                       WHEN op-prune   THEN VALUE #( ( `pruning` ) )
                       WHEN op-weed    THEN VALUE #( ( `circle_weeding` ) ( `path_upkeep` ) )
                       WHEN op-spray   THEN VALUE #( ( `spraying` ) ) ).
  ENDMETHOD.


  METHOD unit_of.
    result = SWITCH #( to_lower( operation )
                       WHEN op-harvest THEN `bunches`
                       WHEN op-prune   THEN `palms`
                       ELSE `ha` ).
  ENDMETHOD.


  METHOD num.
    DATA(rounded) = round( val = value dec = decimals ).
    result = |{ rounded DECIMALS = decimals }|.
    IF decimals > 0 AND result CA '.'.
      SHIFT result RIGHT DELETING TRAILING '0'.
      SHIFT result RIGHT DELETING TRAILING '.'.
      CONDENSE result.
    ENDIF.
    IF result = `-0`.
      result = `0`.
    ENDIF.
  ENDMETHOD.


  METHOD data_end.
    result = COND #( WHEN estate-data_end IS NOT INITIAL THEN estate-data_end
                     ELSE cl_abap_context_info=>get_system_date( ) ).
  ENDMETHOD.


  METHOD default_plan_date.
    result = data_end( ) + 1.
  ENDMETHOD.


  METHOD expected_present.
    DATA(crew) = VALUE #( crews[ crew_code = crew_code ] OPTIONAL ).

    DATA(recorded) = VALUE #( attendance[ crew_code = crew_code work_date = on ] OPTIONAL ).
    IF recorded IS NOT INITIAL AND recorded-on_roll > 0.
      result = VALUE #( on_roll        = recorded-on_roll
                        present        = recorded-present
                        attendance_pct = round( val = CONV decfloat34( recorded-present ) * 100 / recorded-on_roll dec = 1 )
                        basis          = `recorded attendance on the day` ).
      RETURN.
    ENDIF.

    DATA(upto) = CONV d( nmin( val1 = CONV i( on - 1 ) val2 = CONV i( data_end( ) ) ) ).
    DATA(present) = 0.
    DATA(on_roll) = 0.
    DATA(days) = 0.
    " the newest LOOKBACK days up to the day before
    LOOP AT attendance INTO DATA(day) WHERE crew_code = crew_code AND work_date <= upto.
      present = present + day-present.
      on_roll = on_roll + day-on_roll.
      days = days + 1.
    ENDLOOP.
    IF days > lookback.
      present = 0.
      on_roll = 0.
      DATA(skip) = days - lookback.
      LOOP AT attendance INTO day WHERE crew_code = crew_code AND work_date <= upto.
        IF skip > 0.
          skip = skip - 1.
          CONTINUE.
        ENDIF.
        present = present + day-present.
        on_roll = on_roll + day-on_roll.
      ENDLOOP.
    ENDIF.

    DATA(rate) = COND decfloat34( WHEN on_roll > 0 THEN CONV decfloat34( present ) / on_roll ELSE '0.85' ).
    result = VALUE #( on_roll        = crew-establishment
                      present        = round( val = crew-establishment * rate dec = 0 )
                      attendance_pct = round( val = 100 * rate dec = 1 )
                      basis          = |mean attendance over the trailing { lookback } days, applied to the roll| ).
  ENDMETHOD.

ENDCLASS.
