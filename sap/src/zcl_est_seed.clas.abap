CLASS zcl_est_seed DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Run with F9 after activation. Writes
    "!   - the AI provider rows (ZEST_AI_PROV), keeping keys already maintained;
    "!   - the assumption register (ZEST_ASSUMP), keeping values the estate already changed;
    "!   - estate SMPL: a small sample estate of 40 blocks with crews, attendance, a harvest
    "!     ledger, upkeep rounds and stores records, so every app has something to show before
    "!     the estate's own extracts are imported. Running again rebuilds SMPL only.
    "! The sample is generated from a fixed sequence: every run writes the same estate, dated
    "! up to yesterday.
    INTERFACES if_oo_adt_classrun.
  PROTECTED SECTION.
  PRIVATE SECTION.
    CONSTANTS sample TYPE zest_estate-estate VALUE 'SMPL'.
    CONSTANTS block_degrees TYPE decfloat34 VALUE '0.004'.

    DATA seed TYPE int8 VALUE 20250524.

    METHODS providers
      RETURNING VALUE(result) TYPE i.
    METHODS assumptions
      RETURNING VALUE(result) TYPE i.
    METHODS sample_estate
      IMPORTING out TYPE REF TO if_oo_adt_classrun_out.
    METHODS sample_stores
      RETURNING VALUE(result) TYPE i.
    "! next number of the fixed sequence, from 0 to BELOW - 1
    METHODS next
      IMPORTING below         TYPE i
      RETURNING VALUE(result) TYPE i.
ENDCLASS.



CLASS zcl_est_seed IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.
    out->write( |{ providers( ) } AI provider(s) written to ZEST_AI_PROV| ).
    out->write( |{ assumptions( ) } assumption(s) added to ZEST_ASSUMP| ).
    sample_estate( out ).
    out->write( |{ sample_stores( ) } sample stores record(s) written to ZEST_MM_MOCK| ).
    out->write( `Next: run ZCL_EST_AI_TEST, then preview ZUI_EST_CMD_O4 -> Plan -> Plan Tomorrow (estate SMPL)` ).
  ENDMETHOD.


  METHOD next.
    seed = ( seed * 1103515245 + 12345 ) MOD 2147483648.
    result = seed MOD below.
  ENDMETHOD.


  METHOD providers.
    DATA rows TYPE STANDARD TABLE OF zest_ai_prov WITH EMPTY KEY.
    GET TIME STAMP FIELD DATA(now).

    rows = VALUE #(
      created_by = sy-uname created_at = now last_changed_by = sy-uname last_changed_at = now
      local_last_changed_at = now is_active = abap_true max_tokens = 2000 temperature = '0.20'
      ( provider_id      = 'NOVA_PRO'
        priority         = 10
        provider_type    = zcl_est_ai_factory=>provider_type-bedrock
        description      = 'AWS Bedrock Nova Pro (reasoning)'
        model_id         = 'us.amazon.nova-pro-v1:0'
        comm_scenario    = 'ZEST_AI_BEDROCK'
        outbound_service = 'ZEST_AI_BEDROCK_REST'
        api_path         = '/model/{model}/converse'
        aws_region       = 'us-east-1'
        is_default       = abap_true )
      ( provider_id      = 'NOVA_LITE'
        priority         = 20
        provider_type    = zcl_est_ai_factory=>provider_type-bedrock
        description      = 'AWS Bedrock Nova Lite (short-form)'
        model_id         = 'us.amazon.nova-lite-v1:0'
        comm_scenario    = 'ZEST_AI_BEDROCK'
        outbound_service = 'ZEST_AI_BEDROCK_REST'
        api_path         = '/model/{model}/converse'
        aws_region       = 'us-east-1' )
      ( provider_id      = 'GEMINI_FLASH'
        priority         = 30
        provider_type    = zcl_est_ai_factory=>provider_type-gemini
        description      = 'Google Gemini Flash'
        model_id         = 'gemini-3.5-flash'
        comm_scenario    = 'ZEST_AI_GEMINI'
        outbound_service = 'ZEST_AI_GEMINI_REST'
        api_path         = '/v1beta/interactions'
        api_revision     = '2026-05-20' ) ).

    " re-running must not wipe keys maintained since; a new row takes a key of its scenario
    SELECT provider_id, comm_scenario, api_key FROM zest_ai_prov INTO TABLE @DATA(existing_keys).
    LOOP AT rows ASSIGNING FIELD-SYMBOL(<row>).
      <row>-api_key = VALUE #( existing_keys[ provider_id = <row>-provider_id ]-api_key OPTIONAL ).
      IF <row>-api_key IS INITIAL.
        LOOP AT existing_keys INTO DATA(existing) WHERE comm_scenario = <row>-comm_scenario AND api_key IS NOT INITIAL.
          <row>-api_key = existing-api_key.
          EXIT.
        ENDLOOP.
      ENDIF.
    ENDLOOP.

    MODIFY zest_ai_prov FROM TABLE @rows.
    result = sy-dbcnt.
  ENDMETHOD.


  METHOD assumptions.
    GET TIME STAMP FIELD DATA(now).
    SELECT assumption_key FROM zest_assump INTO TABLE @DATA(existing).

    DATA(rows) = zcl_est_assumptions=>defaults( ).
    " a value the estate changed stays; only new keys are added
    LOOP AT existing INTO DATA(kept).
      DELETE rows WHERE assumption_key = kept-assumption_key.
    ENDLOOP.
    LOOP AT rows ASSIGNING FIELD-SYMBOL(<row>).
      <row>-created_by            = sy-uname.
      <row>-created_at            = now.
      <row>-last_changed_by       = sy-uname.
      <row>-last_changed_at       = now.
      <row>-local_last_changed_at = now.
    ENDLOOP.
    IF rows IS NOT INITIAL.
      INSERT zest_assump FROM TABLE @rows.
    ENDIF.
    result = lines( rows ).
    zcl_est_assumptions=>clear_cache( ).
  ENDMETHOD.


  METHOD sample_estate.
    DATA blocks TYPE STANDARD TABLE OF zest_block WITH EMPTY KEY.
    DATA crews TYPE STANDARD TABLE OF zest_crew WITH EMPTY KEY.
    DATA attendance TYPE STANDARD TABLE OF zest_attend WITH EMPTY KEY.
    DATA orders TYPE STANDARD TABLE OF zest_workord WITH EMPTY KEY.
    DATA upkeep TYPE STANDARD TABLE OF zest_upkeep WITH EMPTY KEY.

    DATA(today) = cl_abap_context_info=>get_system_date( ).
    DATA(data_end) = CONV d( today - 1 ).
    GET TIME STAMP FIELD DATA(now).

    DELETE FROM zest_block WHERE estate = @sample.
    DELETE FROM zest_crew WHERE estate = @sample.
    DELETE FROM zest_attend WHERE estate = @sample.
    DELETE FROM zest_workord WHERE estate = @sample.
    DELETE FROM zest_upkeep WHERE estate = @sample.
    DELETE FROM zest_plan_l WHERE plan_uuid IN ( SELECT plan_uuid FROM zest_plan WHERE estate = @sample ).
    DELETE FROM zest_plan WHERE estate = @sample.

    MODIFY zest_estate FROM @( VALUE zest_estate( estate                = sample
                                        estate_name           = 'Sample Estate (generated)'
                                        latitude              = '-7.0300'
                                        longitude             = '140.8500'
                                        currency              = 'IDR'
                                        default_provider      = 'NOVA_PRO'
                                        is_sample             = abap_true
                                        data_end              = data_end
                                        created_by            = sy-uname
                                        created_at            = now
                                        last_changed_by       = sy-uname
                                        last_changed_at       = now
                                        local_last_changed_at = now ) ).

    " two divisions of 4 x 5 blocks, side by side, so neighbours share edges
    DATA(roads) = VALUE string_table( ( `good` ) ( `good` ) ( `fair` ) ( `fair` ) ( `poor` ) ).
    DO 2 TIMES.
      DATA(division) = sy-index.
      DO 20 TIMES.
        DATA(number) = sy-index.
        DATA(column) = ( number - 1 ) MOD 5.
        DATA(row) = ( number - 1 ) DIV 5.
        DATA(west) = CONV decfloat34( '140.8300' ) + ( ( division - 1 ) * 5 + column ) * block_degrees.
        DATA(south) = CONV decfloat34( '-7.0400' ) + row * block_degrees.
        DATA(east) = west + block_degrees.
        DATA(north) = south + block_degrees.
        DATA(ring) = VALUE zcl_est_geo=>ty_ring( ( lon = CONV f( west ) lat = CONV f( south ) )
                                                 ( lon = CONV f( east ) lat = CONV f( south ) )
                                                 ( lon = CONV f( east ) lat = CONV f( north ) )
                                                 ( lon = CONV f( west ) lat = CONV f( north ) )
                                                 ( lon = CONV f( west ) lat = CONV f( south ) ) ).
        DATA(ha) = CONV decfloat34( 22 + next( 9 ) ).
        DATA(planted) = 2008 + next( 12 ).
        APPEND VALUE #(
          estate          = sample
          block_key       = |{ division }-{ number }|
          division        = |{ division }|
          block_code      = |{ number }|
          block_label     = |{ division }-{ number }|
          planted_ha      = ha
          palms           = ha * 136
          planted_year    = planted
          abw_kg          = CONV decfloat34( next( 30 ) ) / 10 + 7
          rotation_days   = 7 + next( 4 )
          gang_code       = |G{ division }-0{ 1 + column DIV 3 }|
          road_condition  = roads[ 1 + next( 5 ) ]
          " about 23 t/ha/yr at 8 kg a bunch, older palms a little more
          bunches_per_day = round( val = ha * ( 7 + CONV decfloat34( 2020 - planted ) / 10 ) dec = 2 )
          centroid_lon    = ( west + east ) / 2
          centroid_lat    = ( south + north ) / 2
          geometry        = zcl_est_geo=>format_ring( ring ) ) TO blocks.
      ENDDO.

      APPEND VALUE #( estate = sample crew_code = |G{ division }-01| crew_type = 'harvest' crew_name = |Gang { division }-01|
                      division = |{ division }| establishment = 26 harvesters = 14 home_block = |{ division }-1| ) TO crews.
      APPEND VALUE #( estate = sample crew_code = |G{ division }-02| crew_type = 'harvest' crew_name = |Gang { division }-02|
                      division = |{ division }| establishment = 24 harvesters = 13 home_block = |{ division }-4| ) TO crews.
      APPEND VALUE #( estate = sample crew_code = |U{ division }-01| crew_type = 'upkeep' crew_name = |Upkeep { division }-01|
                      division = |{ division }| establishment = 18 home_block = |{ division }-11| ) TO crews.
    ENDDO.
    APPEND VALUE #( estate = sample crew_code = 'S-01' crew_type = 'spray' crew_name = 'Spray team 1'
                    establishment = 10 home_block = '1-16' ) TO crews.

    " 45 days of attendance; Sundays thin
    LOOP AT crews INTO DATA(crew).
      DO 45 TIMES.
        DATA(day) = CONV d( data_end - 45 + sy-index ).
        DATA(weekday) = ( day - CONV d( '19000101' ) ) MOD 7.   " 0 = Monday
        DATA(rate) = COND i( WHEN weekday = 6 THEN 55 + next( 15 ) ELSE 80 + next( 16 ) ).
        APPEND VALUE #( estate = sample crew_code = crew-crew_code work_date = day
                        on_roll = crew-establishment present = crew-establishment * rate / 100 ) TO attendance.
      ENDDO.
    ENDLOOP.

    " harvest ledger: every block cut on its round; what is cut falls short when it rains or the road is poor
    DATA(order_no) = 0.
    LOOP AT blocks INTO DATA(block).
      DATA(offset) = next( block-rotation_days ).
      DO 45 TIMES.
        day = CONV d( data_end - 45 + sy-index ).
        CHECK ( sy-index + offset ) MOD block-rotation_days = 0.
        order_no = order_no + 1.
        DATA(planned) = round( val = block-bunches_per_day * block-rotation_days dec = 0 ).
        DATA(share) = COND decfloat34( WHEN block-road_condition = `poor` THEN CONV decfloat34( 65 + next( 25 ) ) / 100
                                       ELSE CONV decfloat34( 80 + next( 21 ) ) / 100 ).
        DATA(actual) = round( val = planned * share dec = 0 ).
        DATA(gang) = |G{ block-division }-0{ COND i( WHEN block-gang_code CP '*-01' THEN 1 ELSE 2 ) }|.
        APPEND VALUE #(
          estate           = sample
          order_id         = |WO-{ day DATE = RAW }-H-{ order_no WIDTH = 4 ALIGN = RIGHT PAD = '0' }|
          work_date        = day
          operation        = 'harvest'
          activity         = 'harvest'
          division         = block-division
          block_key        = block-block_key
          crew_code        = gang
          headcount_plan   = 6
          headcount_actual = COND #( WHEN share < '0.8' THEN 5 ELSE 6 )
          planned_qty      = planned
          actual_qty       = actual
          qty_unit         = 'bunches'
          man_days_plan    = 6
          man_days_actual  = COND #( WHEN share < '0.8' THEN 5 ELSE 6 )
          status           = COND #( WHEN share >= '0.97' THEN 'completed' ELSE 'partial' ) ) TO orders.
      ENDDO.

      " upkeep rounds: spread so a share of blocks falls due in the next days
      APPEND VALUE #( estate = sample block_key = block-block_key activity = 'pruning'
                      last_done = data_end - 150 - next( 110 ) interval_days = 240 ) TO upkeep.
      APPEND VALUE #( estate = sample block_key = block-block_key activity = 'circle_weeding'
                      last_done = data_end - 40 - next( 45 ) interval_days = 75 ) TO upkeep.
      APPEND VALUE #( estate = sample block_key = block-block_key activity = 'path_upkeep'
                      last_done = data_end - 60 - next( 60 ) interval_days = 110 ) TO upkeep.
      APPEND VALUE #( estate = sample block_key = block-block_key activity = 'spraying'
                      last_done = data_end - 60 - next( 50 ) interval_days = 100 ) TO upkeep.
    ENDLOOP.

    INSERT zest_block FROM TABLE @blocks.
    INSERT zest_crew FROM TABLE @crews.
    INSERT zest_attend FROM TABLE @attendance.
    INSERT zest_workord FROM TABLE @orders.
    INSERT zest_upkeep FROM TABLE @upkeep.

    out->write( |Estate { sample }: { lines( blocks ) } blocks, { lines( crews ) } crews, | &&
                |{ lines( attendance ) } attendance days, { lines( orders ) } work orders, { lines( upkeep ) } upkeep rounds; | &&
                |data ends { data_end DATE = ISO }, so tomorrow is { today DATE = ISO }| ).
  ENDMETHOD.


  METHOD sample_stores.
    TYPES:
      BEGIN OF ty_material,
        material  TYPE zest_mm_mock-material,
        name      TYPE zest_mm_mock-material_name,
        group     TYPE zest_mm_mock-material_group,
        unit      TYPE zest_mm_mock-qty_unit,
        supplier  TYPE zest_mm_mock-supplier,
        vendor    TYPE zest_mm_mock-supplier_name,
        quoted    TYPE i,
        "! usual delivery, and how many days it can run over
        usual     TYPE i,
        spread    TYPE i,
        daily_use TYPE i,
        rop       TYPE i,
        rounding  TYPE i,
        price     TYPE i,
        stock     TYPE i,
      END OF ty_material.
    DATA materials TYPE STANDARD TABLE OF ty_material WITH EMPTY KEY.
    DATA rows TYPE STANDARD TABLE OF zest_mm_mock WITH EMPTY KEY.

    DELETE FROM zest_mm_mock WHERE estate = @sample.

    materials = VALUE #(
      ( material = 'FE-001' name = 'NPK 12-12-17-2' group = 'FERT' unit = 'KG' supplier = 'V101'
        vendor = 'PT Pupuk Sample (sea)' quoted = 30 usual = 41 spread = 25 daily_use = 900 rop = 30000
        rounding = 50 price = 8500 stock = 61000 )
      ( material = 'AC-001' name = 'Glyphosate 480 SL' group = 'AGCH' unit = 'L' supplier = 'V201'
        vendor = 'CV Agro Sample (road)' quoted = 14 usual = 16 spread = 10 daily_use = 18 rop = 300
        rounding = 20 price = 95000 stock = 520 )
      ( material = 'FU-001' name = 'Diesel B35' group = 'FUEL' unit = 'L' supplier = 'V301'
        vendor = 'PT Fuel Sample (road)' quoted = 5 usual = 6 spread = 4 daily_use = 650 rop = 4000
        rounding = 8000 price = 13250 stock = 7600 ) ).

    DATA(row_id) = 0.
    LOOP AT materials INTO DATA(material).
      row_id = row_id + 1.
      APPEND VALUE #( estate = sample row_id = row_id kind = 'M' material = material-material
                      material_name = material-name material_group = material-group qty_unit = material-unit
                      supplier = material-supplier supplier_name = material-vendor quoted_days = material-quoted
                      reorder_point = material-rop safety_stock = material-rop / 3 rounding = material-rounding
                      price = material-price ) TO rows.
      row_id = row_id + 1.
      APPEND VALUE #( estate = sample row_id = row_id kind = 'S' material = material-material
                      quantity = material-stock qty_unit = material-unit ) TO rows.

      " a year of issues, a little lumpy
      DATA(day) = -365.
      WHILE day < 0.
        row_id = row_id + 1.
        APPEND VALUE #( estate = sample row_id = row_id kind = 'I' material = material-material
                        date_offset = day qty_unit = material-unit
                        quantity = material-daily_use * 7 * ( 70 + next( 61 ) ) / 100 ) TO rows.
        day = day + 7.
      ENDWHILE.

      " purchase orders: placed every few weeks, delivered after the usual time plus a delay now and then
      day = -360.
      DATA(po) = 0.
      WHILE day < -5.
        po = po + 1.
        row_id = row_id + 1.
        DATA(lead) = material-usual - 4 + next( 9 ) + COND i( WHEN next( 10 ) = 0 THEN material-spread ELSE 0 ).
        DATA(received) = day + lead.
        APPEND VALUE #( estate = sample row_id = row_id
                        kind = COND #( WHEN received < 0 THEN 'P' ELSE 'O' )
                        material = material-material supplier = material-supplier supplier_name = material-vendor
                        document = |45{ row_id WIDTH = 8 ALIGN = RIGHT PAD = '0' }|
                        date_offset = day date2_offset = received qty_unit = material-unit
                        quantity = material-daily_use * 35 price = material-price ) TO rows.
        day = day + 35 + next( 10 ).
      ENDWHILE.
    ENDLOOP.

    INSERT zest_mm_mock FROM TABLE @rows.
    result = lines( rows ).
  ENDMETHOD.

ENDCLASS.
