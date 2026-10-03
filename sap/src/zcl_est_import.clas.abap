CLASS zcl_est_import DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Loads the estate's CSV extracts into the Estate Command tables. The files are the ones
    "! sap/tools/export_sap_seed.py writes (and, for crews, attendance, orders and upkeep, the
    "! feeds in gis/data/synthetic as they are). Lines starting with # are comments; the header
    "! row names the columns, so their order does not matter.
    "!
    "! PARSE runs in the RAP interaction phase and touches no table; FLUSH runs in the save
    "! phase and replaces the estate's rows of that kind.
    TYPES:
      BEGIN OF ty_batch,
        kind       TYPE zest_import-data_kind,
        estate     TYPE zest_estate-estate,
        rows       TYPE i,
        "! operations present in an ORDERS file: only their ledger rows are replaced
        operations TYPE string_table,
        blocks     TYPE STANDARD TABLE OF zest_block WITH EMPTY KEY,
        crews      TYPE STANDARD TABLE OF zest_crew WITH EMPTY KEY,
        attendance TYPE STANDARD TABLE OF zest_attend WITH EMPTY KEY,
        orders     TYPE STANDARD TABLE OF zest_workord WITH EMPTY KEY,
        upkeep     TYPE STANDARD TABLE OF zest_upkeep WITH EMPTY KEY,
        mm         TYPE STANDARD TABLE OF zest_mm_mock WITH EMPTY KEY,
      END OF ty_batch.

    CONSTANTS:
      BEGIN OF kind,
        blocks     TYPE zest_import-data_kind VALUE 'BLOCKS',
        crews      TYPE zest_import-data_kind VALUE 'CREWS',
        attendance TYPE zest_import-data_kind VALUE 'ATTENDANCE',
        orders     TYPE zest_import-data_kind VALUE 'ORDERS',
        upkeep     TYPE zest_import-data_kind VALUE 'UPKEEP',
        mm         TYPE zest_import-data_kind VALUE 'MM',
      END OF kind.

    CLASS-METHODS parse
      IMPORTING data_kind     TYPE zest_import-data_kind
                estate        TYPE zest_estate-estate
                content       TYPE xstring
      RETURNING VALUE(result) TYPE ty_batch
      RAISING   zcx_est_ai.

    CLASS-METHODS queue
      IMPORTING batch TYPE ty_batch.

    "! Writes every queued batch; called from the save phase
    CLASS-METHODS flush.

    CLASS-METHODS clear_queue.

    "! Writes one batch now; for class runs outside RAP
    CLASS-METHODS write
      IMPORTING batch TYPE ty_batch.

    "! "1-32" from division 1 and block 32; leading zeros and blanks dropped
    CLASS-METHODS block_key
      IMPORTING division      TYPE csequence
                block_code    TYPE csequence
      RETURNING VALUE(result) TYPE zest_block-block_key.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_column,
        name  TYPE string,
        index TYPE i,
      END OF ty_column,
      ty_columns TYPE HASHED TABLE OF ty_column WITH UNIQUE KEY name.

    CLASS-DATA batches TYPE STANDARD TABLE OF ty_batch WITH EMPTY KEY.

    CLASS-METHODS split_line
      IMPORTING line          TYPE string
      RETURNING VALUE(result) TYPE string_table.

    CLASS-METHODS cell
      IMPORTING columns       TYPE ty_columns
                cells         TYPE string_table
                name          TYPE string
      RETURNING VALUE(result) TYPE string.

    CLASS-METHODS to_date
      IMPORTING text          TYPE string
      RETURNING VALUE(result) TYPE d.

    CLASS-METHODS to_number
      IMPORTING text          TYPE string
      RETURNING VALUE(result) TYPE decfloat34.

    CLASS-METHODS trim_number
      IMPORTING text          TYPE csequence
      RETURNING VALUE(result) TYPE string.
ENDCLASS.



CLASS zcl_est_import IMPLEMENTATION.

  METHOD parse.
    DATA columns TYPE ty_columns.
    DATA operations TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line.

    result-kind   = to_upper( data_kind ).
    result-estate = to_upper( estate ).
    IF result-estate IS INITIAL.
      RAISE EXCEPTION NEW zcx_est_ai( message = `Name the estate the file belongs to` ).
    ENDIF.

    DATA(text) = ``.
    TRY.
        text = cl_abap_conv_codepage=>create_in( codepage = `UTF-8` )->convert( source = content ).
      CATCH cx_root INTO DATA(conversion_error).
        RAISE EXCEPTION NEW zcx_est_ai( message = |The file is not UTF-8 text: { conversion_error->get_text( ) }| ).
    ENDTRY.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN text WITH cl_abap_char_utilities=>newline.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN text WITH `,`.
    SPLIT text AT cl_abap_char_utilities=>newline INTO TABLE DATA(file_lines).

    DATA(row_id) = 0.
    LOOP AT file_lines INTO DATA(line).
      " a byte-order mark, comment lines and blank lines carry no row
      line = replace( val = line pcre = `^\x{FEFF}` with = `` ).
      IF strlen( line ) > 0 AND substring( val = line len = 1 ) = `#`.
        CONTINUE.
      ENDIF.
      DATA(trimmed) = condense( line ).
      CHECK trimmed IS NOT INITIAL.

      DATA(cells) = split_line( line ).
      IF columns IS INITIAL.
        LOOP AT cells INTO DATA(header).
          INSERT VALUE #( name = to_lower( condense( header ) ) index = sy-tabix ) INTO TABLE columns.
        ENDLOOP.
        CONTINUE.
      ENDIF.

      CASE result-kind.
        WHEN kind-blocks.
          DATA(division) = cell( columns = columns cells = cells name = `division_code` ).
          DATA(code) = cell( columns = columns cells = cells name = `block_code` ).
          DATA(label) = cell( columns = columns cells = cells name = `block_label` ).
          APPEND VALUE #(
            estate          = result-estate
            block_key       = block_key( division = division block_code = code )
            division        = trim_number( division )
            block_code      = trim_number( code )
            block_label     = COND #( WHEN label IS NOT INITIAL THEN label ELSE block_key( division = division block_code = code ) )
            planted_ha      = to_number( cell( columns = columns cells = cells name = `planted_ha` ) )
            palms           = to_number( cell( columns = columns cells = cells name = `palms` ) )
            planted_year    = to_number( cell( columns = columns cells = cells name = `planted_year` ) )
            abw_kg          = to_number( cell( columns = columns cells = cells name = `abw_kg` ) )
            rotation_days   = to_number( cell( columns = columns cells = cells name = `rotation_target_days` ) )
            gang_code       = cell( columns = columns cells = cells name = `gang_code` )
            road_condition  = cell( columns = columns cells = cells name = `road_condition` )
            bunches_per_day = to_number( cell( columns = columns cells = cells name = `bunches_per_day` ) )
            centroid_lon    = to_number( cell( columns = columns cells = cells name = `centroid_lon` ) )
            centroid_lat    = to_number( cell( columns = columns cells = cells name = `centroid_lat` ) )
            geometry        = cell( columns = columns cells = cells name = `geometry` ) ) TO result-blocks.

        WHEN kind-crews.
          APPEND VALUE #(
            estate        = result-estate
            crew_code     = to_upper( cell( columns = columns cells = cells name = `crew_code` ) )
            crew_type     = to_lower( cell( columns = columns cells = cells name = `crew_type` ) )
            crew_name     = cell( columns = columns cells = cells name = `name` )
            division      = trim_number( cell( columns = columns cells = cells name = `division_code` ) )
            establishment = to_number( cell( columns = columns cells = cells name = `establishment` ) )
            harvesters    = to_number( cell( columns = columns cells = cells name = `harvesters` ) )
            home_block    = cell( columns = columns cells = cells name = `home_block` ) ) TO result-crews.

        WHEN kind-attendance.
          APPEND VALUE #(
            estate    = result-estate
            crew_code = to_upper( cell( columns = columns cells = cells name = `crew_code` ) )
            work_date = to_date( cell( columns = columns cells = cells name = `date` ) )
            on_roll   = to_number( cell( columns = columns cells = cells name = `on_roll` ) )
            present   = to_number( cell( columns = columns cells = cells name = `present` ) ) ) TO result-attendance.

        WHEN kind-orders.
          DATA(operation) = to_lower( cell( columns = columns cells = cells name = `operation` ) ).
          INSERT operation INTO TABLE operations.
          APPEND VALUE #(
            estate           = result-estate
            order_id         = cell( columns = columns cells = cells name = `order_id` )
            work_date        = to_date( cell( columns = columns cells = cells name = `date` ) )
            operation        = operation
            activity         = to_lower( cell( columns = columns cells = cells name = `activity` ) )
            division         = trim_number( cell( columns = columns cells = cells name = `division_code` ) )
            block_key        = block_key( division   = cell( columns = columns cells = cells name = `division_code` )
                                          block_code = cell( columns = columns cells = cells name = `block_code` ) )
            crew_code        = to_upper( cell( columns = columns cells = cells name = `crew_code` ) )
            headcount_plan   = to_number( cell( columns = columns cells = cells name = `headcount_plan` ) )
            headcount_actual = to_number( cell( columns = columns cells = cells name = `headcount_actual` ) )
            planned_qty      = to_number( cell( columns = columns cells = cells name = `planned_qty` ) )
            actual_qty       = to_number( cell( columns = columns cells = cells name = `actual_qty` ) )
            qty_unit         = cell( columns = columns cells = cells name = `unit` )
            man_days_plan    = to_number( cell( columns = columns cells = cells name = `man_days_plan` ) )
            man_days_actual  = to_number( cell( columns = columns cells = cells name = `man_days_actual` ) )
            status           = to_lower( cell( columns = columns cells = cells name = `status` ) )
            carried_to       = cell( columns = columns cells = cells name = `carried_to` ) ) TO result-orders.

        WHEN kind-upkeep.
          APPEND VALUE #(
            estate        = result-estate
            block_key     = block_key( division   = cell( columns = columns cells = cells name = `division_code` )
                                       block_code = cell( columns = columns cells = cells name = `block_code` ) )
            activity      = to_lower( cell( columns = columns cells = cells name = `activity` ) )
            last_done     = to_date( cell( columns = columns cells = cells name = `last_done` ) )
            interval_days = to_number( cell( columns = columns cells = cells name = `interval_days` ) ) ) TO result-upkeep.

        WHEN kind-mm.
          row_id = row_id + 1.
          APPEND VALUE #(
            estate         = result-estate
            row_id         = row_id
            kind           = to_upper( cell( columns = columns cells = cells name = `kind` ) )
            material       = cell( columns = columns cells = cells name = `material` )
            material_name  = cell( columns = columns cells = cells name = `material_name` )
            material_group = cell( columns = columns cells = cells name = `material_group` )
            supplier       = cell( columns = columns cells = cells name = `supplier` )
            supplier_name  = cell( columns = columns cells = cells name = `supplier_name` )
            document       = cell( columns = columns cells = cells name = `document` )
            date_offset    = to_number( cell( columns = columns cells = cells name = `date_offset` ) )
            date2_offset   = to_number( cell( columns = columns cells = cells name = `date2_offset` ) )
            quantity       = to_number( cell( columns = columns cells = cells name = `quantity` ) )
            qty_unit       = cell( columns = columns cells = cells name = `qty_unit` )
            quoted_days    = to_number( cell( columns = columns cells = cells name = `quoted_days` ) )
            reorder_point  = to_number( cell( columns = columns cells = cells name = `reorder_point` ) )
            safety_stock   = to_number( cell( columns = columns cells = cells name = `safety_stock` ) )
            rounding       = to_number( cell( columns = columns cells = cells name = `rounding` ) )
            price          = to_number( cell( columns = columns cells = cells name = `price` ) ) ) TO result-mm.

        WHEN OTHERS.
          RAISE EXCEPTION NEW zcx_est_ai(
            message = |Kind { result-kind } is not known; use BLOCKS, CREWS, ATTENDANCE, ORDERS, UPKEEP or MM| ).
      ENDCASE.
      result-rows = result-rows + 1.
    ENDLOOP.

    IF result-rows = 0.
      RAISE EXCEPTION NEW zcx_est_ai( message = `The file has a header row and nothing under it` ).
    ENDIF.
    result-operations = VALUE #( FOR operation_name IN operations ( operation_name ) ).
  ENDMETHOD.


  METHOD queue.
    APPEND batch TO batches.
  ENDMETHOD.


  METHOD flush.
    LOOP AT batches INTO DATA(batch).
      write( batch ).
    ENDLOOP.
    CLEAR batches.
  ENDMETHOD.


  METHOD clear_queue.
    CLEAR batches.
  ENDMETHOD.


  METHOD write.
    CASE batch-kind.
      WHEN kind-blocks.
        DELETE FROM zest_block WHERE estate = @batch-estate.
        INSERT zest_block FROM TABLE @batch-blocks ACCEPTING DUPLICATE KEYS.

        " an estate imported for the first time is created, centred on its blocks for the forecast
        SELECT SINGLE @abap_true FROM zest_estate WHERE estate = @batch-estate INTO @DATA(exists).
        IF exists = abap_false.
          DATA(latitude) = CONV decfloat34( 0 ).
          DATA(longitude) = CONV decfloat34( 0 ).
          DATA(placed) = 0.
          LOOP AT batch-blocks INTO DATA(block) WHERE centroid_lat IS NOT INITIAL.
            latitude  = latitude + block-centroid_lat.
            longitude = longitude + block-centroid_lon.
            placed    = placed + 1.
          ENDLOOP.
          GET TIME STAMP FIELD DATA(now).
          DATA(estate) = VALUE zest_estate( estate          = batch-estate
                                            estate_name     = batch-estate
                                            currency        = 'IDR'
                                            created_by      = cl_abap_context_info=>get_user_technical_name( )
                                            created_at      = now
                                            last_changed_by = cl_abap_context_info=>get_user_technical_name( )
                                            last_changed_at = now
                                            local_last_changed_at = now ).
          IF placed > 0.
            estate-latitude  = latitude / placed.
            estate-longitude = longitude / placed.
          ENDIF.
          INSERT zest_estate FROM @estate.
        ENDIF.

      WHEN kind-crews.
        DELETE FROM zest_crew WHERE estate = @batch-estate.
        INSERT zest_crew FROM TABLE @batch-crews ACCEPTING DUPLICATE KEYS.

      WHEN kind-attendance.
        DELETE FROM zest_attend WHERE estate = @batch-estate.
        INSERT zest_attend FROM TABLE @batch-attendance ACCEPTING DUPLICATE KEYS.

      WHEN kind-orders.
        LOOP AT batch-operations INTO DATA(operation).
          DELETE FROM zest_workord WHERE estate = @batch-estate AND operation = @operation.
        ENDLOOP.
        INSERT zest_workord FROM TABLE @batch-orders ACCEPTING DUPLICATE KEYS.

      WHEN kind-upkeep.
        DELETE FROM zest_upkeep WHERE estate = @batch-estate.
        INSERT zest_upkeep FROM TABLE @batch-upkeep ACCEPTING DUPLICATE KEYS.

      WHEN kind-mm.
        DELETE FROM zest_mm_mock WHERE estate = @batch-estate.
        INSERT zest_mm_mock FROM TABLE @batch-mm ACCEPTING DUPLICATE KEYS.
    ENDCASE.
  ENDMETHOD.


  METHOD block_key.
    result = |{ trim_number( division ) }-{ trim_number( block_code ) }|.
  ENDMETHOD.


  METHOD trim_number.
    result = condense( CONV string( text ) ).
    " "07" and "7.0" are block 7; a code with letters stays as it is
    IF result CO '0123456789.' AND result IS NOT INITIAL.
      TRY.
          result = |{ CONV i( CONV decfloat34( result ) ) }|.
        CATCH cx_sy_conversion_error.
          RETURN.
      ENDTRY.
    ENDIF.
  ENDMETHOD.


  METHOD split_line.
    DATA(current) = ``.
    DATA(quoted) = abap_false.
    DATA(length) = strlen( line ).
    DATA(position) = 0.

    WHILE position < length.
      DATA(char) = substring( val = line off = position len = 1 ).
      IF char = `"`.
        " a doubled quote inside quotes is one quote character
        IF quoted = abap_true AND position + 1 < length AND substring( val = line off = position + 1 len = 1 ) = `"`.
          current = current && `"`.
          position = position + 1.
        ELSE.
          quoted = xsdbool( quoted = abap_false ).
        ENDIF.
      ELSEIF char = `,` AND quoted = abap_false.
        APPEND current TO result.
        current = ``.
      ELSE.
        current = current && char.
      ENDIF.
      position = position + 1.
    ENDWHILE.
    APPEND current TO result.
  ENDMETHOD.


  METHOD cell.
    DATA(column) = VALUE #( columns[ name = name ] OPTIONAL ).
    CHECK column-index > 0.
    result = condense( VALUE #( cells[ column-index ] OPTIONAL ) ).
  ENDMETHOD.


  METHOD to_date.
    DATA(digits) = replace( val = text sub = `-` with = `` occ = 0 ).
    IF strlen( digits ) = 8 AND digits CO '0123456789'.
      result = digits.
    ENDIF.
  ENDMETHOD.


  METHOD to_number.
    CHECK text IS NOT INITIAL.
    TRY.
        result = CONV decfloat34( text ).
      CATCH cx_sy_conversion_error.
        CLEAR result.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
