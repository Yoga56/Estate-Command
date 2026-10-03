CLASS zcl_est_demand DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! What is due on a date, how urgent, and what deferring it costs (port of ops.demand).
    "! Every figure is computed here; the scheduler adds terms but invents no quantities.
    TYPES ty_amount TYPE decfloat34.
    TYPES:
      BEGIN OF ty_item,
        block_key           TYPE zest_block-block_key,
        block_label         TYPE zest_block-block_label,
        block_code          TYPE zest_block-block_code,
        division            TYPE zest_block-division,
        activity            TYPE zest_workord-activity,
        planted_ha          TYPE decfloat34,
        palms               TYPE i,
        last_done           TYPE d,
        days_since          TYPE i,
        target_days         TYPE i,
        urgency             TYPE decfloat34,
        in_progress         TYPE abap_bool,
        qty                 TYPE decfloat34,
        unit                TYPE string,
        rate_per_man_day    TYPE decfloat34,
        rate_source         TYPE string,
        man_days            TYPE decfloat34,
        tonnes_at_risk      TYPE decfloat34,
        value_idr           TYPE ty_amount,
        deferral_per_day    TYPE ty_amount,
        horizon_days        TYPE i,
        "! deferral per day times the horizon: what the scheduler ranks on
        deferral_idr        TYPE ty_amount,
        road_condition      TYPE zest_block-road_condition,
        centroid            TYPE zcl_est_geo=>ty_point,
        abw_kg              TYPE decfloat34,
      END OF ty_item,
      ty_items TYPE STANDARD TABLE OF ty_item WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_result,
        items   TYPE ty_items,
        not_due TYPE ty_items,
        "! the register keys the figures were priced with
        used    TYPE string_table,
      END OF ty_result.

    CLASS-METHODS demand
      IMPORTING data          TYPE REF TO zcl_est_data
                operation     TYPE zest_plan-operation
                on            TYPE d
      RETURNING VALUE(result) TYPE ty_result.

    "! Urgency weight on the cost of deferral: clamped to 0.2 .. 2.5
    CLASS-METHODS urgency_weight
      IMPORTING urgency       TYPE decfloat34
      RETURNING VALUE(result) TYPE decfloat34.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-METHODS harvest
      IMPORTING data          TYPE REF TO zcl_est_data
                on            TYPE d
      CHANGING  result        TYPE ty_result.

    CLASS-METHODS upkeep
      IMPORTING data          TYPE REF TO zcl_est_data
                operation     TYPE zest_plan-operation
                on            TYPE d
      CHANGING  result        TYPE ty_result.

    CLASS-METHODS interval_key
      IMPORTING activity      TYPE csequence
      RETURNING VALUE(result) TYPE string.

    CLASS-METHODS rate_key
      IMPORTING activity      TYPE csequence
      RETURNING VALUE(result) TYPE string.
ENDCLASS.



CLASS zcl_est_demand IMPLEMENTATION.

  METHOD demand.
    DATA(op) = to_lower( operation ).
    result-used = VALUE #( ( `ffb_price_idr_kg` ) ( `abw_kg` ) ).

    IF op = zcl_est_data=>op-harvest.
      harvest( EXPORTING data = data on = on CHANGING result = result ).
    ELSE.
      upkeep( EXPORTING data = data operation = CONV #( op ) on = on CHANGING result = result ).
    ENDIF.

    LOOP AT result-items ASSIGNING FIELD-SYMBOL(<item>).
      <item>-deferral_idr = <item>-deferral_per_day * <item>-horizon_days.
    ENDLOOP.
    SORT result-items BY deferral_per_day DESCENDING urgency DESCENDING.
    SORT result-not_due BY urgency DESCENDING.
  ENDMETHOD.


  METHOD urgency_weight.
    result = nmax( val1 = CONV decfloat34( '0.2' ) val2 = nmin( val1 = CONV decfloat34( '2.5' ) val2 = urgency ) ).
  ENDMETHOD.


  METHOD harvest.
    TYPES:
      BEGIN OF ty_cut,
        block_key TYPE zest_block-block_key,
        bunches   TYPE decfloat34,
        last_cut  TYPE d,
      END OF ty_cut.
    DATA cuts TYPE HASHED TABLE OF ty_cut WITH UNIQUE KEY block_key.

    DATA(price) = zcl_est_assumptions=>value( 'ffb_price_idr_kg' ).
    DATA(default_abw) = zcl_est_assumptions=>value( 'abw_kg' ).
    DATA(loss) = zcl_est_assumptions=>value( 'harvest_loss_pct_per_day_overdue' ) / 100.
    DATA(quota) = zcl_est_assumptions=>value( 'harvest_bunches_per_man_day' ).
    DATA(lookback) = CONV i( zcl_est_assumptions=>value( 'harvest_ripening_lookback_days' ) ).
    APPEND LINES OF VALUE string_table( ( `harvest_loss_pct_per_day_overdue` ) ( `harvest_bunches_per_man_day` )
                                        ( `harvest_ripening_lookback_days` ) ) TO result-used.
    DATA(since) = CONV d( on - lookback ).

    " what was cut over the lookback, and the last cutting day, per block
    LOOP AT data->orders INTO DATA(order)
         WHERE operation = zcl_est_data=>op-harvest AND work_date < on AND actual_qty > 0.
      ASSIGN cuts[ block_key = order-block_key ] TO FIELD-SYMBOL(<cut>).
      IF sy-subrc <> 0.
        INSERT VALUE #( block_key = order-block_key ) INTO TABLE cuts ASSIGNING <cut>.
      ENDIF.
      IF order-work_date >= since.
        <cut>-bunches = <cut>-bunches + order-actual_qty.
      ENDIF.
      " the ledger is sorted by date, so the last row seen is the last cut
      <cut>-last_cut = order-work_date.
    ENDLOOP.

    LOOP AT data->blocks INTO DATA(block).
      DATA(cut) = VALUE #( cuts[ block_key = block-block_key ] OPTIONAL ).
      DATA(target) = COND i( WHEN block-rotation_days > 0 THEN block-rotation_days ELSE 7 ).
      DATA(days_since) = COND i( WHEN cut-last_cut IS NOT INITIAL THEN on - cut-last_cut ELSE target ).
      DATA(ready) = cut-bunches / lookback * days_since.
      IF ready <= 0.
        ready = block-bunches_per_day * days_since.
      ENDIF.
      DATA(pressure) = CONV decfloat34( days_since ) / target.
      DATA(abw) = COND decfloat34( WHEN block-abw_kg > 0 THEN block-abw_kg ELSE default_abw ).
      DATA(tonnes) = ready * abw / 1000.
      DATA(value) = tonnes * 1000 * price.

      DATA(item) = VALUE ty_item(
        block_key        = block-block_key
        block_label      = block-label
        block_code       = block-block_code
        division         = block-division
        activity         = 'harvest'
        planted_ha       = block-planted_ha
        palms            = block-palms
        last_done        = cut-last_cut
        days_since       = days_since
        target_days      = target
        urgency          = round( val = pressure dec = 2 )
        qty              = round( val = ready dec = 0 )
        unit             = `bunches`
        rate_per_man_day = quota
        rate_source      = `flat quota assumption`
        man_days         = COND #( WHEN quota > 0 THEN round( val = ready / quota dec = 2 ) )
        tonnes_at_risk   = round( val = tonnes dec = 2 )
        value_idr        = round( val = value dec = 0 )
        deferral_per_day = round( val = value * loss * urgency_weight( pressure ) dec = 0 )
        horizon_days     = target
        road_condition   = block-road_condition
        centroid         = block-centroid
        abw_kg           = abw ).

      IF pressure >= '0.6'.
        APPEND item TO result-items.
      ELSE.
        APPEND item TO result-not_due.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD upkeep.
    DATA(price) = zcl_est_assumptions=>value( 'ffb_price_idr_kg' ).
    DATA(default_abw) = zcl_est_assumptions=>value( 'abw_kg' ).
    DATA(loss) = zcl_est_assumptions=>value( 'upkeep_loss_pct_per_day_overdue' ) / 100.
    APPEND `upkeep_loss_pct_per_day_overdue` TO result-used.

    DATA(activities) = zcl_est_data=>activities_of( operation ).
    LOOP AT activities INTO DATA(activity).
      APPEND rate_key( activity ) TO result-used.
      APPEND interval_key( activity ) TO result-used.
    ENDLOOP.

    LOOP AT data->blocks INTO DATA(block).
      DATA(abw) = COND decfloat34( WHEN block-abw_kg > 0 THEN block-abw_kg ELSE default_abw ).
      DATA(tonnes_year) = block-bunches_per_day * 365 * abw / 1000.
      DATA(value_year) = tonnes_year * 1000 * price.

      LOOP AT activities INTO activity.
        DATA(state) = VALUE #( data->upkeep[ block_key = block-block_key activity = activity ] OPTIONAL ).
        DATA(interval) = COND i( WHEN state-interval_days > 0 THEN state-interval_days
                                 ELSE CONV i( zcl_est_assumptions=>value( interval_key( activity ) ) ) ).

        " the last completed round before the day, else the state table, else a guess near due
        DATA(last_done) = VALUE d( ).
        DATA(first_order) = VALUE d( ).
        LOOP AT data->orders INTO DATA(order)
             WHERE block_key = block-block_key AND activity = activity AND work_date < on.
          IF first_order IS INITIAL.
            first_order = order-work_date.
          ENDIF.
          IF order-status = 'completed'.
            last_done = order-work_date.
          ENDIF.
        ENDLOOP.
        IF last_done IS INITIAL.
          last_done = state-last_done.
          IF last_done IS INITIAL OR last_done >= on.
            last_done = COND #( WHEN first_order IS NOT INITIAL THEN first_order - interval
                                ELSE on - interval * 9 / 10 ).
          ENDIF.
        ENDIF.

        DATA(full) = COND decfloat34( WHEN activity = `pruning` THEN block-palms ELSE block-planted_ha ).
        DATA(done_since) = CONV decfloat34( 0 ).
        DATA(started) = abap_false.
        LOOP AT data->orders INTO order
             WHERE block_key = block-block_key AND activity = activity AND work_date < on AND work_date > last_done.
          done_since = done_since + order-actual_qty.
          started = abap_true.
        ENDLOOP.
        DATA(remaining) = full - done_since.
        DATA(in_progress) = xsdbool( started = abap_true AND remaining < full ).
        DATA(qty) = COND decfloat34( WHEN in_progress = abap_true THEN nmax( val1 = remaining val2 = 0 ) ELSE full ).

        DATA(days_since) = CONV i( on - last_done ).
        DATA(urgency) = CONV decfloat34( days_since ) / interval.
        DATA(rate) = zcl_est_assumptions=>value( rate_key( activity ) ).

        DATA(item) = VALUE ty_item(
          block_key        = block-block_key
          block_label      = block-label
          block_code       = block-block_code
          division         = block-division
          activity         = activity
          planted_ha       = block-planted_ha
          palms            = block-palms
          last_done        = last_done
          days_since       = days_since
          target_days      = interval
          urgency          = round( val = urgency dec = 2 )
          in_progress      = in_progress
          qty              = round( val = qty dec = COND #( WHEN activity = `pruning` THEN 0 ELSE 2 ) )
          unit             = COND #( WHEN activity = `pruning` THEN `palms` ELSE `ha` )
          rate_per_man_day = rate
          rate_source      = `assumption register`
          man_days         = COND #( WHEN rate > 0 THEN round( val = qty / rate dec = 2 ) )
          tonnes_at_risk   = round( val = tonnes_year * loss * interval dec = 2 )
          value_idr        = round( val = value_year * loss * interval dec = 0 )
          deferral_per_day = round( val = value_year * loss * urgency_weight( urgency ) dec = 0 )
          horizon_days     = 7
          road_condition   = block-road_condition
          centroid         = block-centroid
          abw_kg           = abw ).

        IF urgency >= '0.85' OR in_progress = abap_true.
          APPEND item TO result-items.
        ELSE.
          APPEND item TO result-not_due.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD interval_key.
    result = SWITCH #( activity
                       WHEN `pruning`        THEN `prune_interval_days`
                       WHEN `circle_weeding` THEN `circle_weed_interval_days`
                       WHEN `path_upkeep`    THEN `path_upkeep_interval_days`
                       ELSE `spray_interval_days` ).
  ENDMETHOD.


  METHOD rate_key.
    result = SWITCH #( activity
                       WHEN `pruning`        THEN `prune_palms_per_man_day`
                       WHEN `circle_weeding` THEN `circle_weed_ha_per_man_day`
                       WHEN `path_upkeep`    THEN `path_upkeep_ha_per_man_day`
                       ELSE `spray_ha_per_man_day` ).
  ENDMETHOD.

ENDCLASS.
