CLASS zcl_est_stores DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Stores: what to order, when, and why (port of gis/stores.py and gis/models/leadtime,
    "! consumption and safety_stock). Every answer leads with a sentence - "Order by 31 July:
    "! 250 t", "1 in 10 orders from Pupuk Kaltim takes 66 days or more" - and carries its
    "! figures beside it.
    "!
    "! Lead time is what each supplier really takes, from order to the receipt that completed
    "! it; use is the trailing daily issue rate with its weekly spread; the reorder point is the
    "! service-level quantile of 2,000 simulated lead-time demands. With the stock model
    "! switched off in the register, SAP's own reorder point is used instead.
    TYPES ty_qty TYPE decfloat34.
    " component names match the elements of the custom entity ZI_EST_STORES
    TYPES:
      BEGIN OF ty_row,
        estate            TYPE zest_estate-estate,
        material          TYPE zest_mm_mock-material,
        materialname      TYPE zest_mm_mock-material_name,
        materialgroup     TYPE zest_mm_mock-material_group,
        qtyunit           TYPE zest_mm_mock-qty_unit,
        supplier          TYPE zest_mm_mock-supplier,
        suppliername      TYPE zest_mm_mock-supplier_name,
        stockonhand       TYPE ty_qty,
        onorder           TYPE ty_qty,
        dailyuse          TYPE ty_qty,
        quoteddays        TYPE i,
        usualdays         TYPE i,
        latedays          TYPE i,
        verylatepct       TYPE i,
        ordersmeasured    TYPE i,
        reorderpoint      TYPE ty_qty,
        sapreorderpoint   TYPE ty_qty,
        safetystock       TYPE ty_qty,
        bufferfordelivery TYPE ty_qty,
        bufferforuse      TYPE ty_qty,
        orderbydate       TYPE d,
        orderqty          TYPE ty_qty,
        stockstatus       TYPE c LENGTH 12,
        statuscriticality TYPE int1,
        headline          TYPE c LENGTH 160,
        leadsentence      TYPE c LENGTH 255,
        buffersentence    TYPE c LENGTH 255,
        policysource      TYPE c LENGTH 20,
        issample          TYPE abap_bool,
      END OF ty_row,
      ty_rows TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.

    CONSTANTS draws TYPE i VALUE 2000.
    "! more than this many days past the usual time counts as very late
    CONSTANTS very_late_days TYPE i VALUE 18.

    CLASS-METHODS overview
      IMPORTING estate        TYPE zest_estate-estate
      RETURNING VALUE(result) TYPE ty_rows.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES ty_values TYPE STANDARD TABLE OF decfloat34 WITH EMPTY KEY.

    CLASS-METHODS material_row
      IMPORTING mm            TYPE REF TO zcl_est_mm_data
                material      TYPE zcl_est_mm_data=>ty_material
                today         TYPE d
      RETURNING VALUE(result) TYPE ty_row.

    "! value at quantile Q (0..1) of a sorted table
    CLASS-METHODS quantile
      IMPORTING sorted        TYPE ty_values
                q             TYPE decfloat34
      RETURNING VALUE(result) TYPE decfloat34.

    CLASS-METHODS mean
      IMPORTING values        TYPE ty_values
      RETURNING VALUE(result) TYPE decfloat34.

    CLASS-METHODS round_up
      IMPORTING quantity      TYPE decfloat34
                step          TYPE decfloat34
      RETURNING VALUE(result) TYPE decfloat34.
ENDCLASS.



CLASS zcl_est_stores IMPLEMENTATION.

  METHOD overview.
    SELECT SINGLE * FROM zest_estate WHERE estate = @estate INTO @DATA(estate_row).
    CHECK sy-subrc = 0.

    DATA(today) = cl_abap_context_info=>get_system_date( ).
    DATA(mm) = NEW zcl_est_mm_data( estate_row ).

    LOOP AT mm->materials INTO DATA(material).
      DATA(row) = material_row( mm = mm material = material today = today ).
      row-estate = estate.
      APPEND row TO result.
    ENDLOOP.

    SORT result BY statuscriticality ASCENDING orderbydate ASCENDING.
  ENDMETHOD.


  METHOD material_row.
    DATA lead_times TYPE ty_values.
    DATA weekly TYPE ty_values.
    DATA ddlt TYPE ty_values.
    DATA ddlt_lead_only TYPE ty_values.

    DATA(service) = zcl_est_assumptions=>value( 'service_level_pct' ) / 100.
    DATA(cover_weeks) = zcl_est_assumptions=>value( 'order_cover_weeks' ).
    DATA(window) = nmax( val1 = CONV i( zcl_est_assumptions=>value( 'consumption_window_days' ) ) val2 = 7 ).
    DATA(use_model) = xsdbool( zcl_est_assumptions=>value( 'use_stock_model' ) >= 1 ).

    result = VALUE #( material        = material-material
                      materialname    = material-material_name
                      materialgroup   = material-material_group
                      qtyunit         = material-unit
                      supplier        = material-supplier
                      suppliername    = material-supplier_name
                      quoteddays      = material-quoted_days
                      sapreorderpoint = material-reorder_point
                      stockonhand     = VALUE #( mm->stock[ material = material-material ]-quantity OPTIONAL )
                      issample        = mm->is_sample ).

    " lead time: order to the receipt that completed it, main supplier first, else every supplier
    LOOP AT mm->orders INTO DATA(order) WHERE material = material-material.
      IF order-is_open = abap_true.
        result-onorder = result-onorder + order-quantity.
      ELSEIF order-supplier = material-supplier AND order-received_on >= order-ordered_on.
        APPEND CONV decfloat34( order-received_on - order-ordered_on ) TO lead_times.
      ENDIF.
    ENDLOOP.
    IF lines( lead_times ) < 3.
      CLEAR lead_times.
      LOOP AT mm->orders INTO order WHERE material = material-material AND is_open = abap_false.
        CHECK order-received_on >= order-ordered_on.
        APPEND CONV decfloat34( order-received_on - order-ordered_on ) TO lead_times.
      ENDLOOP.
    ENDIF.
    result-ordersmeasured = lines( lead_times ).
    " too few orders to learn from: the quote, give or take a fifth
    IF lines( lead_times ) < 3.
      DATA(quote) = CONV decfloat34( nmax( val1 = material-quoted_days val2 = 1 ) ).
      lead_times = VALUE #( ( quote * '0.8' ) ( quote ) ( quote ) ( quote * '1.2' ) ).
    ENDIF.
    SORT lead_times BY table_line.
    result-usualdays = round( val = quantile( sorted = lead_times q = '0.5' ) dec = 0 ).
    result-latedays  = round( val = quantile( sorted = lead_times q = '0.9' ) dec = 0 ).
    DATA(very_late) = REDUCE i( INIT n = 0 FOR t IN lead_times WHERE ( table_line > result-usualdays + very_late_days )
                                NEXT n = n + 1 ).
    result-verylatepct = round( val = CONV decfloat34( very_late ) * 100 / lines( lead_times ) dec = 0 ).

    " use: the trailing window's daily rate, and the spread of its weeks
    DATA(since) = CONV d( today - window ).
    DATA(used) = CONV decfloat34( 0 ).
    DATA(weeks) = window DIV 7.
    DO weeks TIMES.
      APPEND CONV decfloat34( 0 ) TO weekly.
    ENDDO.
    LOOP AT mm->issues INTO DATA(issue) WHERE material = material-material AND issued_on > since AND issued_on <= today.
      used = used + issue-quantity.
      DATA(week) = nmin( val1 = weeks val2 = 1 + ( issue-issued_on - since - 1 ) DIV 7 ).
      weekly[ week ] = weekly[ week ] + issue-quantity.
    ENDLOOP.
    result-dailyuse = round( val = used / window dec = 3 ).
    DATA(weekly_mean) = mean( weekly ).
    DATA(variance) = REDUCE decfloat34( INIT v = CONV decfloat34( 0 ) FOR w IN weekly
                                        NEXT v = v + ( w - weekly_mean ) * ( w - weekly_mean ) ).
    DATA(weekly_sd) = COND decfloat34( WHEN weeks > 1 THEN sqrt( CONV f( variance / ( weeks - 1 ) ) ) ).

    " 2,000 lead-time demands: a lead time drawn from the record, use over it with its spread
    " a fixed seed: the same records give the same reorder point on every call
    DATA(random) = cl_abap_random_float=>create( seed = 20250524 ).
    DO draws TIMES.
      DATA(pick) = nmin( val1 = lines( lead_times ) val2 = 1 + CONV i( floor( random->get_next( ) * lines( lead_times ) ) ) ).
      DATA(lead) = lead_times[ pick ].
      " Box-Muller: one standard normal draw
      DATA(u1) = nmax( val1 = random->get_next( ) val2 = CONV f( '1E-12' ) ).
      DATA(u2) = random->get_next( ).
      DATA(z) = sqrt( -2 * log( u1 ) ) * cos( 2 * '3.14159265358979' * u2 ).
      DATA(base) = result-dailyuse * lead.
      APPEND base TO ddlt_lead_only.
      APPEND nmax( val1 = CONV decfloat34( 0 ) val2 = base + z * weekly_sd * sqrt( CONV f( lead / 7 ) ) ) TO ddlt.
    ENDDO.
    SORT ddlt BY table_line.
    SORT ddlt_lead_only BY table_line.

    DATA(mean_ddlt) = result-dailyuse * mean( lead_times ).
    DATA(learned_rop) = round( val = quantile( sorted = ddlt q = service ) dec = 0 ).
    result-safetystock       = nmax( val1 = learned_rop - mean_ddlt val2 = 0 ).
    result-bufferfordelivery = nmax( val1 = quantile( sorted = ddlt_lead_only q = service ) - mean_ddlt val2 = 0 ).
    result-bufferfordelivery = round( val = nmin( val1 = result-bufferfordelivery val2 = result-safetystock ) dec = 0 ).
    result-bufferforuse      = round( val = result-safetystock - result-bufferfordelivery dec = 0 ).
    result-safetystock       = round( val = result-safetystock dec = 0 ).

    IF use_model = abap_true OR material-reorder_point <= 0.
      result-reorderpoint = learned_rop.
      result-policysource = 'learned'.
    ELSE.
      result-reorderpoint = material-reorder_point.
      result-policysource = 'SAP settings'.
    ENDIF.

    " order by: the last day stock on hand plus on order stays above the reorder point
    DATA(position) = result-stockonhand + result-onorder.
    DATA(days_cover) = COND decfloat34( WHEN result-dailyuse > 0
                                        THEN floor( ( position - result-reorderpoint ) / result-dailyuse )
                                        ELSE 99999 ).
    DATA(days_left) = CONV i( nmax( val1 = -99999 val2 = nmin( val1 = 99999 val2 = days_cover ) ) ).
    result-orderbydate = COND #( WHEN days_left < 0 THEN today
                                 WHEN days_left > 3650 THEN VALUE #( )
                                 ELSE today + days_left ).
    result-orderqty = round_up( quantity = cover_weeks * 7 * result-dailyuse
                                           + nmax( val1 = result-reorderpoint - position val2 = 0 )
                                step     = material-rounding ).

    DATA(unit) = to_lower( material-unit ).
    IF days_left <= 0.
      result-stockstatus       = 'order_now'.
      result-statuscriticality = 1.
      result-headline = |Order now: { zcl_est_data=>num( value = result-orderqty decimals = 0 ) } { unit } | &&
                        |({ zcl_est_data=>num( value = position decimals = 0 ) } on hand and on order, reorder point | &&
                        |{ zcl_est_data=>num( value = result-reorderpoint decimals = 0 ) })|.
    ELSEIF days_left <= 7.
      result-stockstatus       = 'this_week'.
      result-statuscriticality = 2.
      result-headline = |Order by { result-orderbydate DATE = ISO }: { zcl_est_data=>num( value = result-orderqty decimals = 0 ) } { unit }|.
    ELSEIF result-dailyuse > 0 AND position > result-reorderpoint + 2 * cover_weeks * 7 * result-dailyuse.
      result-stockstatus       = 'overstocked'.
      result-statuscriticality = 0.
      result-headline = |Overstocked: { zcl_est_data=>num( value = CONV #( days_left ) decimals = 0 ) } days of use above the reorder point|.
    ELSE.
      result-stockstatus       = 'covered'.
      result-statuscriticality = 3.
      result-headline = COND #( WHEN result-orderbydate IS NOT INITIAL
                                THEN |Covered; order by { result-orderbydate DATE = ISO }: { zcl_est_data=>num( value = result-orderqty decimals = 0 ) } { unit }|
                                ELSE |Covered: no use recorded in the last { window } days| ).
    ENDIF.

    result-leadsentence =
      |{ COND string( WHEN result-suppliername IS NOT INITIAL THEN result-suppliername ELSE `The supplier` ) } usually takes | &&
      |{ result-usualdays } days against a quote of { result-quoteddays }; 1 in 10 orders takes { result-latedays } days or more| &&
      COND string( WHEN result-ordersmeasured < 3 THEN |, from the quote alone (only { result-ordersmeasured } orders measured)|
                   ELSE |, from { result-ordersmeasured } orders| ) &&
      COND string( WHEN result-verylatepct > 0 THEN |; { result-verylatepct }% arrive very late| ).
    result-buffersentence =
      |{ zcl_est_data=>num( value = result-safetystock decimals = 0 ) } { unit } of safety stock: | &&
      |{ zcl_est_data=>num( value = result-bufferfordelivery decimals = 0 ) } because deliveries vary, | &&
      |{ zcl_est_data=>num( value = result-bufferforuse decimals = 0 ) } because use varies | &&
      |(service level { zcl_est_data=>num( value = service * 100 decimals = 1 ) }%, { draws } simulated lead times)|.
  ENDMETHOD.


  METHOD quantile.
    DATA(count) = lines( sorted ).
    CHECK count > 0.
    DATA(index) = nmax( val1 = 1 val2 = nmin( val1 = count val2 = CONV i( ceil( q * count ) ) ) ).
    result = sorted[ index ].
  ENDMETHOD.


  METHOD mean.
    CHECK values IS NOT INITIAL.
    result = REDUCE decfloat34( INIT s = CONV decfloat34( 0 ) FOR v IN values NEXT s = s + v ) / lines( values ).
  ENDMETHOD.


  METHOD round_up.
    IF step <= 0.
      result = ceil( quantity ).
      RETURN.
    ENDIF.
    result = ceil( quantity / step ) * step.
  ENDMETHOD.

ENDCLASS.
