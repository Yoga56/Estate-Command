CLASS zcl_est_assumptions DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Every number a plan is priced with, in one place (port of gis/assumptions.py).
    "! The defaults live here; ZEST_ASSUMP holds the register as the estate maintains it.
    "! Readers always go through VALUE( ), never through a constant, so an edit in the
    "! Assumptions app reprices the next plan.
    TYPES ty_value TYPE decfloat34.
    TYPES ty_rows TYPE STANDARD TABLE OF zest_assump WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_entry,
        name  TYPE zest_assump-assumption_key,
        value TYPE ty_value,
      END OF ty_entry,
      ty_values TYPE HASHED TABLE OF ty_entry WITH UNIQUE KEY name.

    CONSTANTS:
      BEGIN OF source,
        literature TYPE zest_assump-value_source VALUE 'literature',
        calibrated TYPE zest_assump-value_source VALUE 'calibrated',
        derived    TYPE zest_assump-value_source VALUE 'derived',
        assumed    TYPE zest_assump-value_source VALUE 'assumed',
        client     TYPE zest_assump-value_source VALUE 'client',
      END OF source.

    "! The register as shipped: what ZCL_EST_SEED writes and ResetToDefault goes back to.
    CLASS-METHODS defaults
      RETURNING VALUE(result) TYPE ty_rows.

    "! The value in force for every key: the register row, else the shipped default.
    CLASS-METHODS values
      RETURNING VALUE(result) TYPE ty_values.

    CLASS-METHODS value
      IMPORTING key           TYPE csequence
      RETURNING VALUE(result) TYPE ty_value.

    "! One line per key, for a prompt: "label: value unit (source)".
    CLASS-METHODS describe
      IMPORTING keys          TYPE string_table
      RETURNING VALUE(result) TYPE string.

    CLASS-METHODS clear_cache.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-DATA cache TYPE ty_values.

    CLASS-METHODS add
      IMPORTING key      TYPE csequence
                label    TYPE csequence
                value    TYPE ty_value
                unit     TYPE csequence
                src      TYPE zest_assump-value_source
                basis    TYPE csequence
                used_by  TYPE csequence
                min      TYPE ty_value
                max      TYPE ty_value
                group    TYPE csequence
      CHANGING  rows     TYPE ty_rows.
ENDCLASS.



CLASS zcl_est_assumptions IMPLEMENTATION.

  METHOD add.
    APPEND VALUE #( assumption_key   = key
                    assumption_label = label
                    assumption_value = value
                    default_value    = value
                    value_unit       = unit
                    value_source     = src
                    basis            = basis
                    used_by          = used_by
                    min_value        = min
                    max_value        = max
                    assumption_group = group
                    sort_order       = lines( rows ) + 1 ) TO rows.
  ENDMETHOD.


  METHOD defaults.
    " pricing
    add( EXPORTING key = 'ffb_price_idr_kg' label = 'FFB farmgate price' value = 2600 unit = 'IDR/kg' src = source-assumed
                   basis = 'Indonesian FFB farmgate, 2025-26 band 2,300-3,200 IDR/kg.'
                   used_by = 'value recovered; cost of deferral' min = 1500 max = 4500 group = 'pricing'
         CHANGING rows = result ).
    add( EXPORTING key = 'abw_kg' label = 'Average bunch weight' value = 8 unit = 'kg' src = source-calibrated
                   basis = 'Back-solved so the estate lands at 23 t/ha/yr; the fallback where a block carries no weight.'
                   used_by = 'tonnes on every harvest plan' min = 5 max = 18 group = 'pricing'
         CHANGING rows = result ).
    add( EXPORTING key = 'man_day_cost_idr' label = 'Cost of one man-day' value = 150000 unit = 'IDR' src = source-assumed
                   basis = 'Provincial minimum wage, about 165k a day with the mandor share; rounded down for daily rates.'
                   used_by = 'travel penalty; value per man-day' min = 80000 max = 400000 group = 'pricing'
         CHANGING rows = result ).
    " harvest
    add( EXPORTING key = 'harvest_loss_pct_per_day_overdue' label = 'Crop value lost per day past the round' value = '1.5'
                   unit = '% per day' src = source-literature
                   basis = 'Overripe bunches shed loose fruit and FFA climbs; field trials put it at 1-2% a day.'
                   used_by = 'cost of deferral (harvest)' min = '0.2' max = 5 group = 'harvest'
         CHANGING rows = result ).
    add( EXPORTING key = 'harvest_bunches_per_man_day' label = 'Flat harvester quota' value = 138 unit = 'bunches'
                   src = source-derived basis = 'Estate-wide mean from the worker-day feed; the fallback per block.'
                   used_by = 'man-days needed per block' min = 60 max = 250 group = 'harvest'
         CHANGING rows = result ).
    add( EXPORTING key = 'harvest_ripening_lookback_days' label = 'Ripening rate lookback' value = 30 unit = 'days'
                   src = source-assumed basis = 'Trailing window over which a block''s bunches per day is measured.'
                   used_by = 'bunches ready per block' min = 14 max = 90 group = 'harvest'
         CHANGING rows = result ).
    " upkeep
    add( EXPORTING key = 'prune_palms_per_man_day' label = 'Pruning rate' value = 55 unit = 'palms' src = source-literature
                   basis = 'Mature palm, chisel and pole: 50-70 palms a day.'
                   used_by = 'man-days per pruning job' min = 20 max = 120 group = 'upkeep'
         CHANGING rows = result ).
    add( EXPORTING key = 'circle_weed_ha_per_man_day' label = 'Circle weeding rate' value = '1.1' unit = 'ha'
                   src = source-literature basis = 'Manual circle weeding at 130-140 palms/ha: about a hectare a day.'
                   used_by = 'man-days per weeding job' min = '0.4' max = 3 group = 'upkeep'
         CHANGING rows = result ).
    add( EXPORTING key = 'path_upkeep_ha_per_man_day' label = 'Path upkeep rate' value = '1.5' unit = 'ha'
                   src = source-literature basis = 'Harvest path slashing, mature stand.'
                   used_by = 'man-days per path job' min = '0.5' max = 4 group = 'upkeep'
         CHANGING rows = result ).
    add( EXPORTING key = 'spray_ha_per_man_day' label = 'Spraying rate' value = '2.6' unit = 'ha' src = source-literature
                   basis = 'Knapsack herbicide round, 15 L tank, mixed spot and blanket.'
                   used_by = 'man-days per spray job' min = 1 max = 6 group = 'upkeep'
         CHANGING rows = result ).
    add( EXPORTING key = 'upkeep_loss_pct_per_day_overdue' label = 'Yield lost per day an upkeep round is overdue'
                   value = '0.03' unit = '% of annual yield per day' src = source-assumed
                   basis = 'A round a month late costs about 1% of the block''s year. Nobody has measured it here.'
                   used_by = 'cost of deferral (prune, weed, spray)' min = 0 max = '0.3' group = 'upkeep'
         CHANGING rows = result ).
    add( EXPORTING key = 'prune_interval_days' label = 'Pruning round' value = 240 unit = 'days' src = source-literature
                   basis = 'Standard pruning round for mature palms.'
                   used_by = 'days overdue (prune)' min = 90 max = 400 group = 'upkeep'
         CHANGING rows = result ).
    add( EXPORTING key = 'circle_weed_interval_days' label = 'Circle weeding round' value = 75 unit = 'days'
                   src = source-literature basis = 'Standard circle weeding round.'
                   used_by = 'days overdue (weed)' min = 30 max = 180 group = 'upkeep'
         CHANGING rows = result ).
    add( EXPORTING key = 'path_upkeep_interval_days' label = 'Path upkeep round' value = 110 unit = 'days'
                   src = source-literature basis = 'Standard harvest path round.'
                   used_by = 'days overdue (weed)' min = 30 max = 240 group = 'upkeep'
         CHANGING rows = result ).
    add( EXPORTING key = 'spray_interval_days' label = 'Spray round' value = 100 unit = 'days' src = source-literature
                   basis = 'Standard herbicide round.'
                   used_by = 'days overdue (spray)' min = 30 max = 240 group = 'upkeep'
         CHANGING rows = result ).
    " scheduling
    add( EXPORTING key = 'work_day_hours' label = 'Field working day' value = 7 unit = 'hours' src = source-assumed
                   basis = 'Muster to knock-off, less breaks.'
                   used_by = 'man-day capacity; travel penalty' min = 5 max = 10 group = 'scheduling'
         CHANGING rows = result ).
    add( EXPORTING key = 'rain_cutoff_mm' label = 'Rain that stops field work' value = 45 unit = 'mm on the day'
                   src = source-assumed basis = 'Above this the ledger shows crews weathered off.'
                   used_by = 'weather constraint in the plan' min = 10 max = 100 group = 'scheduling'
         CHANGING rows = result ).
    add( EXPORTING key = 'spray_rain_mm' label = 'Rain that washes off herbicide' value = 15 unit = 'mm on the day'
                   src = source-literature basis = 'Spray rounds stop at 15 mm because the herbicide washes off.'
                   used_by = 'spray go or hold' min = 5 max = 40 group = 'scheduling'
         CHANGING rows = result ).
    add( EXPORTING key = 'crew_transport_km_per_hour' label = 'Crew transport speed' value = 15 unit = 'km/h'
                   src = source-assumed basis = 'Tractor and trailer on estate roads.'
                   used_by = 'travel penalty' min = 5 max = 40 group = 'scheduling'
         CHANGING rows = result ).
    add( EXPORTING key = 'contiguity_bonus_pct' label = 'Contiguity bonus' value = 15 unit = '% of block value'
                   src = source-assumed
                   basis = 'Value given up to keep a crew on adjacent blocks. Zero gives the scattered plan nobody executes.'
                   used_by = 'contiguity term; contiguity cost' min = 0 max = 60 group = 'scheduling'
         CHANGING rows = result ).
    add( EXPORTING key = 'attendance_lookback_days' label = 'Attendance lookback for tomorrow''s headcount' value = 14
                   unit = 'days' src = source-assumed
                   basis = 'Tomorrow''s present figure is the crew''s mean attendance over this many days, applied to its roll.'
                   used_by = 'expected present per crew' min = 3 max = 60 group = 'scheduling'
         CHANGING rows = result ).
    add( EXPORTING key = 'use_rain_forecast' label = 'Use the rain forecast' value = 1 unit = '1 on, 0 off'
                   src = source-assumed
                   basis = 'On: tomorrow''s rain comes from the Open-Meteo forecast. Off: unknown unless set on the plan.'
                   used_by = 'rain on the plan; spray go or hold' min = 0 max = 1 group = 'forecasting'
         CHANGING rows = result ).
    add( EXPORTING key = 'fire_radius_km' label = 'Fire watch radius' value = 10 unit = 'km'
                   src = source-assumed
                   basis = 'NASA FIRMS hotspots this far from the nearest block are shown on the map and in the plan.'
                   used_by = 'fire hotspots around the estate' min = 1 max = 50 group = 'forecasting'
         CHANGING rows = result ).
    add( EXPORTING key = 'fire_hold_km' label = 'Hold blocks this near a fire' value = 1 unit = 'km'
                   src = source-assumed
                   basis = 'A block whose centre is this close to a FIRMS hotspot is held back from tomorrow''s plan for the crews'' safety; 0 holds none.'
                   used_by = 'blocks held back for fire' min = 0 max = 10 group = 'forecasting'
         CHANGING rows = result ).
    add( EXPORTING key = 'fire_days' label = 'Fire watch days' value = 3 unit = 'days'
                   src = source-assumed
                   basis = 'Hotspots detected over this many past days (the FIRMS area API allows 1 to 5).'
                   used_by = 'fire hotspots around the estate' min = 1 max = 5 group = 'forecasting'
         CHANGING rows = result ).
    " stores
    add( EXPORTING key = 'use_stock_model' label = 'Use learned reorder points' value = 1 unit = '1 on, 0 off'
                   src = source-assumed
                   basis = 'On: reorder points from real lead times and use. Off: SAP''s own MRP settings.'
                   used_by = 'reorder point; order-by date' min = 0 max = 1 group = 'stores'
         CHANGING rows = result ).
    add( EXPORTING key = 'service_level_pct' label = 'Service level' value = 95 unit = '% of cycles without running out'
                   src = source-assumed basis = 'Share of replenishment cycles that should end without a rush buy.'
                   used_by = 'reorder point' min = 50 max = '99.5' group = 'stores'
         CHANGING rows = result ).
    add( EXPORTING key = 'order_cover_weeks' label = 'Cover per order' value = 6 unit = 'weeks of use'
                   src = source-assumed basis = 'A reorder brings stock up to the reorder point plus this much use.'
                   used_by = 'order quantity' min = 1 max = 26 group = 'stores'
         CHANGING rows = result ).
    add( EXPORTING key = 'consumption_window_days' label = 'Use measured over' value = 56 unit = 'days'
                   src = source-assumed basis = 'Trailing window of goods issues that daily use is measured on.'
                   used_by = 'daily use; demand over the lead time' min = 14 max = 365 group = 'stores'
         CHANGING rows = result ).
  ENDMETHOD.


  METHOD values.
    IF cache IS NOT INITIAL.
      result = cache.
      RETURN.
    ENDIF.

    SELECT assumption_key, assumption_value FROM zest_assump INTO TABLE @DATA(rows).
    LOOP AT defaults( ) INTO DATA(default).
      INSERT VALUE #( name  = default-assumption_key
                      value = VALUE #( rows[ assumption_key = default-assumption_key ]-assumption_value
                                       DEFAULT default-default_value ) ) INTO TABLE result.
    ENDLOOP.
    cache = result.
  ENDMETHOD.


  METHOD value.
    DATA(all) = values( ).
    result = VALUE #( all[ name = CONV zest_assump-assumption_key( key ) ]-value OPTIONAL ).
  ENDMETHOD.


  METHOD describe.
    SELECT assumption_key, assumption_label, assumption_value, value_unit, value_source
      FROM zest_assump INTO TABLE @DATA(rows).
    DATA(all) = defaults( ).
    LOOP AT keys INTO DATA(key).
      DATA(row) = VALUE #( rows[ assumption_key = key ] OPTIONAL ).
      IF row IS INITIAL.
        DATA(default) = VALUE #( all[ assumption_key = key ] OPTIONAL ).
        row = CORRESPONDING #( default ).
      ENDIF.
      CHECK row IS NOT INITIAL.
      result = result && |- { row-assumption_label }: { zcl_est_data=>num( CONV #( row-assumption_value ) ) } { row-value_unit } ({ row-value_source })\n|.
    ENDLOOP.
  ENDMETHOD.


  METHOD clear_cache.
    CLEAR cache.
  ENDMETHOD.

ENDCLASS.
