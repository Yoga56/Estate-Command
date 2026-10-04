CLASS zcl_est_scheduler DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Tomorrow's assignment: which crew goes to which blocks, and why
    "! (port of gis/models/scheduler.py).
    "!
    "! Maximise value recovered per man-day, subject to capacity. Four terms, all in rupiah:
    "! deferral (what leaving the block one more cycle costs), contiguity (a bonus for a block
    "! next to one the crew already has), travel (time in transit at the man-day cost) and
    "! capacity (man-days the crew has tomorrow). Greedy by value density, round-robin across
    "! crews, then a swap-improvement pass. Not an LP: every line has to be defended to a
    "! mandor who disagrees with it. The gap to a relaxed upper bound (fractional knapsack,
    "! no geography) is reported so the greedy choice is accountable, and what contiguity
    "! cost is measured by running the plan again without it.
    TYPES ty_amount TYPE decfloat34.
    TYPES:
      BEGIN OF ty_overrides,
        "! crew left out of the plan
        crew_out       TYPE zest_crew-crew_code,
        "! headcount set on the plan for one crew
        crew_code      TYPE zest_crew-crew_code,
        present        TYPE i,
        present_set    TYPE abap_bool,
        "! rain on the day, set by hand; replaces the forecast
        rain_mm        TYPE decfloat34,
        rain_set       TYPE abap_bool,
        "! block held back (label or key)
        block_held     TYPE zest_block-block_label,
        contiguity_pct TYPE decfloat34,
        contiguity_set TYPE abap_bool,
        division       TYPE zest_block-division,
      END OF ty_overrides.
    TYPES:
      BEGIN OF ty_assignment,
        item           TYPE zcl_est_demand=>ty_item,
        seq            TYPE i,
        share          TYPE decfloat34,
        man_days       TYPE decfloat34,
        travel_km      TYPE f,
        travel_idr     TYPE ty_amount,
        contiguity_idr TYPE ty_amount,
        contiguous     TYPE abap_bool,
        score          TYPE ty_amount,
      END OF ty_assignment,
      ty_assignments TYPE STANDARD TABLE OF ty_assignment WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_crew,
        crew_code    TYPE zest_crew-crew_code,
        crew_name    TYPE zest_crew-crew_name,
        division     TYPE zest_crew-division,
        on_roll      TYPE i,
        present      TYPE i,
        basis        TYPE string,
        edited       TYPE abap_bool,
        capacity_md  TYPE decfloat34,
        remaining_md TYPE decfloat34,
        home         TYPE zcl_est_geo=>ty_point,
        home_key     TYPE zest_block-block_key,
        position     TYPE zcl_est_geo=>ty_point,
        range_label  TYPE string,
        assigned     TYPE ty_assignments,
      END OF ty_crew,
      ty_crews TYPE STANDARD TABLE OF ty_crew WITH EMPTY KEY.
    TYPES:
      "! a block held back because a fire hotspot burns this close to it
      BEGIN OF ty_fire_hold,
        item     TYPE zcl_est_demand=>ty_item,
        km       TYPE decfloat34,
        hotspot  TYPE zcl_est_firms=>ty_hotspot,
      END OF ty_fire_hold,
      ty_fire_holds TYPE STANDARD TABLE OF ty_fire_hold WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_plan,
        crews              TYPE ty_crews,
        items              TYPE zcl_est_demand=>ty_items,
        not_reached        TYPE zcl_est_demand=>ty_items,
        fire_held          TYPE ty_fire_holds,
        weather            TYPE zcl_est_weather=>ty_weather,
        stops_work         TYPE abap_bool,
        stop_reason        TYPE string,
        swaps              TYPE i,
        capacity_md        TYPE decfloat34,
        need_md            TYPE decfloat34,
        present            TYPE i,
        deferral_due       TYPE ty_amount,
        achieved           TYPE ty_amount,
        upper_bound        TYPE ty_amount,
        gap_pct            TYPE decfloat34,
        contiguity_pct     TYPE decfloat34,
        achieved_without   TYPE ty_amount,
        contiguity_cost    TYPE ty_amount,
        not_reached_per_day TYPE ty_amount,
        "! the constraint that decided the plan, in a sentence
        binding            TYPE string,
        used               TYPE string_table,
      END OF ty_plan.

    METHODS constructor
      IMPORTING data TYPE REF TO zcl_est_data.

    METHODS plan
      IMPORTING operation     TYPE zest_plan-operation
                on            TYPE d
                overrides     TYPE ty_overrides OPTIONAL
                weather       TYPE zcl_est_weather=>ty_weather OPTIONAL
                fires         TYPE zcl_est_firms=>ty_result OPTIONAL
      RETURNING VALUE(result) TYPE ty_plan.

  PROTECTED SECTION.
  PRIVATE SECTION.
    "! A crew stops taking work below this many man-days left in its day
    CONSTANTS min_remaining_md TYPE decfloat34 VALUE '0.35'.
    "! A later block may be started partially if at least this share of it fits
    CONSTANTS min_partial_share TYPE decfloat34 VALUE '0.3'.
    CONSTANTS max_swap_passes TYPE i VALUE 4.
    CONSTANTS max_swap_evals TYPE i VALUE 40000.

    TYPES:
      BEGIN OF ty_taken,
        block_key TYPE zest_block-block_key,
        crew_code TYPE zest_crew-crew_code,
      END OF ty_taken,
      ty_taken_set TYPE HASHED TABLE OF ty_taken WITH UNIQUE KEY block_key.

    DATA data TYPE REF TO zcl_est_data.
    DATA adjacency TYPE zcl_est_geo=>ty_adjacency.
    DATA man_day_cost TYPE ty_amount.
    DATA work_day_hours TYPE decfloat34.
    DATA transport_kmh TYPE decfloat34.

    METHODS build_crews
      IMPORTING operation     TYPE zest_plan-operation
                on            TYPE d
                overrides     TYPE ty_overrides
      RETURNING VALUE(result) TYPE ty_crews.

    METHODS in_pool
      IMPORTING crew          TYPE ty_crew
                item          TYPE zcl_est_demand=>ty_item
      RETURNING VALUE(result) TYPE abap_bool.

    METHODS travel_cost
      IMPORTING present       TYPE i
                km            TYPE f
      RETURNING VALUE(result) TYPE ty_amount.

    METHODS is_contiguous
      IMPORTING block_key     TYPE zest_block-block_key
                previous      TYPE ty_assignments
                home_key      TYPE zest_block-block_key
      RETURNING VALUE(result) TYPE abap_bool.

    METHODS greedy
      IMPORTING items      TYPE zcl_est_demand=>ty_items
                contiguity TYPE decfloat34
      CHANGING  crews      TYPE ty_crews
                taken      TYPE ty_taken_set.

    "! The crew's whole objective along its assignment order
    METHODS crew_objective
      IMPORTING crew          TYPE ty_crew
                contiguity    TYPE decfloat34
      RETURNING VALUE(result) TYPE ty_amount.

    METHODS swap_pass
      IMPORTING items         TYPE zcl_est_demand=>ty_items
                contiguity    TYPE decfloat34
      CHANGING  crews         TYPE ty_crews
                taken         TYPE ty_taken_set
      RETURNING VALUE(result) TYPE i.

    "! Recomputes each block's terms along the final order, for the Why view
    METHODS finalise
      IMPORTING contiguity TYPE decfloat34
      CHANGING  crews      TYPE ty_crews.

    METHODS upper_bound
      IMPORTING crews         TYPE ty_crews
                items         TYPE zcl_est_demand=>ty_items
      RETURNING VALUE(result) TYPE ty_amount.

    METHODS achieved
      IMPORTING crews         TYPE ty_crews
      RETURNING VALUE(result) TYPE ty_amount.
ENDCLASS.



CLASS zcl_est_scheduler IMPLEMENTATION.

  METHOD constructor.
    me->data = data.

    DATA(shapes) = VALUE zcl_est_geo=>ty_shapes( FOR block IN data->blocks
                                                  ( block_key = block-block_key
                                                    centroid  = block-centroid
                                                    ring      = block-ring ) ).
    adjacency = zcl_est_geo=>adjacency( shapes ).

    man_day_cost   = zcl_est_assumptions=>value( 'man_day_cost_idr' ).
    work_day_hours = nmax( val1 = zcl_est_assumptions=>value( 'work_day_hours' ) val2 = 1 ).
    transport_kmh  = nmax( val1 = zcl_est_assumptions=>value( 'crew_transport_km_per_hour' ) val2 = 1 ).
  ENDMETHOD.


  METHOD plan.
    DATA taken TYPE ty_taken_set.
    DATA demand TYPE zcl_est_demand=>ty_result.

    DATA(op) = to_lower( operation ).
    result-weather = weather.
    result-contiguity_pct = COND #( WHEN overrides-contiguity_set = abap_true THEN overrides-contiguity_pct
                                    ELSE zcl_est_assumptions=>value( 'contiguity_bonus_pct' ) ).
    result-used = VALUE #( ( `man_day_cost_idr` ) ( `contiguity_bonus_pct` ) ( `crew_transport_km_per_hour` )
                           ( `work_day_hours` ) ( `rain_cutoff_mm` ) ( `attendance_lookback_days` ) ).

    " the rain the plan decides on: set by hand, else the forecast
    IF overrides-rain_set = abap_true.
      result-weather-rain_mm  = overrides-rain_mm.
      result-weather-known    = abap_true.
      result-weather-source   = `set on the plan`.
    ENDIF.
    IF result-weather-known = abap_true.
      DATA(cutoff) = zcl_est_assumptions=>value( 'rain_cutoff_mm' ).
      DATA(washoff) = zcl_est_assumptions=>value( 'spray_rain_mm' ).
      IF op = zcl_est_data=>op-spray AND result-weather-rain_mm >= washoff.
        result-stops_work  = abap_true.
        result-stop_reason = |{ zcl_est_data=>num( value = result-weather-rain_mm decimals = 0 ) } mm on the day: | &&
                             |herbicide washes off above { zcl_est_data=>num( value = washoff decimals = 0 ) } mm|.
        APPEND `spray_rain_mm` TO result-used.
      ELSEIF result-weather-rain_mm >= cutoff.
        result-stops_work  = abap_true.
        result-stop_reason = |{ zcl_est_data=>num( value = result-weather-rain_mm decimals = 0 ) } mm on the day, | &&
                             |above the { zcl_est_data=>num( value = cutoff decimals = 0 ) } mm cutoff|.
      ENDIF.
    ENDIF.

    demand = zcl_est_demand=>demand( data = data operation = CONV #( op ) on = on ).
    APPEND LINES OF demand-used TO result-used.
    SORT result-used.
    DELETE ADJACENT DUPLICATES FROM result-used.

    " a block this close to a fire hotspot is held back for the crews' safety (0 holds none)
    DATA(hold_km) = CONV f( zcl_est_assumptions=>value( 'fire_hold_km' ) ).
    IF fires-hotspots IS NOT INITIAL.
      APPEND `fire_hold_km` TO result-used.
    ENDIF.

    " what the plan may not touch
    LOOP AT demand-items INTO DATA(candidate).
      CHECK candidate-man_days > 0.
      CHECK overrides-block_held IS INITIAL
         OR ( candidate-block_label <> overrides-block_held AND candidate-block_key <> overrides-block_held ).
      CHECK overrides-division IS INITIAL OR candidate-division = overrides-division.
      IF hold_km > 0 AND fires-hotspots IS NOT INITIAL.
        DATA(nearest) = VALUE ty_fire_hold( item = candidate km = -1 ).
        LOOP AT fires-hotspots INTO DATA(hotspot).
          DATA(km) = zcl_est_geo=>km( a = candidate-centroid
                                      b = VALUE #( lon = hotspot-longitude lat = hotspot-latitude ) ).
          IF nearest-km < 0 OR km < nearest-km.
            nearest-km      = km.
            nearest-hotspot = hotspot.
          ENDIF.
        ENDLOOP.
        IF nearest-km >= 0 AND nearest-km <= hold_km.
          nearest-km = round( val = nearest-km dec = 2 ).
          APPEND nearest TO result-fire_held.
          CONTINUE.
        ENDIF.
      ENDIF.
      APPEND candidate TO result-items.
    ENDLOOP.

    DATA(crews) = build_crews( operation = CONV #( op ) on = on overrides = overrides ).

    IF result-stops_work = abap_false AND crews IS NOT INITIAL AND result-items IS NOT INITIAL.
      " the plan without the contiguity bonus: what keeping crews together costs
      IF result-contiguity_pct > 0.
        DATA(scattered) = crews.
        DATA(scattered_taken) = VALUE ty_taken_set( ).
        greedy( EXPORTING items = result-items contiguity = 0 CHANGING crews = scattered taken = scattered_taken ).
        swap_pass( EXPORTING items = result-items contiguity = 0 CHANGING crews = scattered taken = scattered_taken ).
        result-achieved_without = achieved( scattered ).
      ENDIF.

      greedy( EXPORTING items = result-items contiguity = result-contiguity_pct CHANGING crews = crews taken = taken ).
      result-swaps = swap_pass( EXPORTING items = result-items contiguity = result-contiguity_pct
                                CHANGING crews = crews taken = taken ).
      finalise( EXPORTING contiguity = result-contiguity_pct CHANGING crews = crews ).
      result-upper_bound = upper_bound( crews = crews items = result-items ).
    ENDIF.

    LOOP AT crews ASSIGNING FIELD-SYMBOL(<crew>).
      <crew>-range_label = zcl_est_geo=>range_label(
        VALUE #( FOR assignment IN <crew>-assigned ( assignment-item-block_code ) ) ).
      result-capacity_md = result-capacity_md + <crew>-capacity_md.
      result-present     = result-present + <crew>-present.
    ENDLOOP.
    SORT crews BY division crew_code.
    result-crews = crews.

    result-achieved = achieved( crews ).
    IF result-contiguity_pct > 0 AND result-achieved_without > 0.
      result-contiguity_cost = nmax( val1 = result-achieved_without - result-achieved val2 = 0 ).
    ENDIF.
    IF result-upper_bound > 0.
      result-gap_pct = round( val = 100 * ( result-upper_bound - result-achieved ) / result-upper_bound dec = 1 ).
    ENDIF.

    LOOP AT result-items INTO DATA(item).
      result-need_md      = result-need_md + item-man_days.
      result-deferral_due = result-deferral_due + item-deferral_idr.
      IF NOT line_exists( taken[ block_key = item-block_key ] ).
        APPEND item TO result-not_reached.
        result-not_reached_per_day = result-not_reached_per_day + item-deferral_per_day.
      ENDIF.
    ENDLOOP.

    DATA(crew_word) = SWITCH string( op WHEN zcl_est_data=>op-harvest THEN `gangs`
                                        WHEN zcl_est_data=>op-spray THEN `teams` ELSE `crews` ).
    IF result-stops_work = abap_true.
      result-binding = |Weather: { result-stop_reason }. Nothing is assigned.|.
    ELSEIF crews IS INITIAL.
      result-binding = |No { crew_word } on the roll for this operation.|.
    ELSEIF result-need_md > result-capacity_md.
      result-binding = |Crew capacity: { zcl_est_data=>num( value = result-capacity_md decimals = 0 ) } man-days | &&
                       |available against { zcl_est_data=>num( value = result-need_md decimals = 0 ) } needed for | &&
                       |everything due. { lines( result-not_reached ) } blocks are not reached.|.
    ELSE.
      result-binding = |Demand: everything due is reached with | &&
                       |{ zcl_est_data=>num( value = result-capacity_md - result-need_md decimals = 0 ) } man-days | &&
                       |to spare across { lines( crews ) } { crew_word }.|.
    ENDIF.
  ENDMETHOD.


  METHOD build_crews.
    DATA(wanted_type) = zcl_est_data=>crew_type_of( operation ).
    DATA(lookback) = CONV i( zcl_est_assumptions=>value( 'attendance_lookback_days' ) ).

    LOOP AT data->crews INTO DATA(crew) WHERE crew_type = wanted_type.
      CHECK crew-crew_code <> overrides-crew_out.
      CHECK overrides-division IS INITIAL OR crew-division IS INITIAL OR crew-division = overrides-division.

      DATA(expected) = data->expected_present( crew_code = crew-crew_code on = on lookback = lookback ).
      DATA(edited) = xsdbool( overrides-present_set = abap_true AND overrides-crew_code = crew-crew_code ).
      IF edited = abap_true.
        expected-present = nmax( val1 = 0 val2 = nmin( val1 = overrides-present val2 = expected-on_roll ) ).
        expected-basis   = `set on the plan`.
      ENDIF.

      " a harvest gang's capacity is its cutters, not its carriers and mandor
      DATA(man_days) = COND decfloat34(
        WHEN operation = zcl_est_data=>op-harvest AND crew-harvesters > 0 AND crew-establishment > 0
        THEN round( val = CONV decfloat34( expected-present ) * crew-harvesters / crew-establishment dec = 0 )
        ELSE expected-present ).

      APPEND VALUE #( crew_code    = crew-crew_code
                      crew_name    = crew-crew_name
                      division     = crew-division
                      on_roll      = expected-on_roll
                      present      = expected-present
                      basis        = expected-basis
                      edited       = edited
                      capacity_md  = man_days
                      remaining_md = man_days
                      home         = crew-home
                      home_key     = crew-home_key
                      position     = crew-home ) TO result.
    ENDLOOP.
  ENDMETHOD.


  METHOD in_pool.
    result = xsdbool( crew-division IS INITIAL OR item-division = crew-division ).
  ENDMETHOD.


  METHOD travel_cost.
    result = km / transport_kmh * present * man_day_cost / work_day_hours.
  ENDMETHOD.


  METHOD is_contiguous.
    LOOP AT previous INTO DATA(before).
      IF line_exists( adjacency[ block_key = block_key neighbour = before-item-block_key ] ).
        result = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
    result = xsdbool( previous IS INITIAL AND home_key IS NOT INITIAL
                      AND line_exists( adjacency[ block_key = block_key neighbour = home_key ] ) ).
  ENDMETHOD.


  METHOD greedy.
    TYPES:
      BEGIN OF ty_order,
        index     TYPE i,
        remaining TYPE decfloat34,
      END OF ty_order.
    DATA order TYPE STANDARD TABLE OF ty_order WITH EMPTY KEY.

    DATA(progress) = abap_true.
    WHILE progress = abap_true.
      progress = abap_false.

      " each round the crew with most of its day left chooses first
      order = VALUE #( FOR c IN crews INDEX INTO i ( index = i remaining = c-remaining_md ) ).
      SORT order BY remaining DESCENDING index ASCENDING.

      LOOP AT order INTO DATA(turn).
        ASSIGN crews[ turn-index ] TO FIELD-SYMBOL(<crew>).
        CHECK <crew>-remaining_md >= min_remaining_md.

        DATA(best) = 0.
        DATA(best_density) = CONV decfloat34( 0 ).
        DATA(best_share) = CONV decfloat34( 1 ).
        DATA(best_assignment) = VALUE ty_assignment( ).

        LOOP AT items INTO DATA(item).
          DATA(item_index) = sy-tabix.
          CHECK in_pool( crew = <crew> item = item ) = abap_true.
          CHECK NOT line_exists( taken[ block_key = item-block_key ] ).

          DATA(km) = zcl_est_geo=>km( a = <crew>-position b = item-centroid ).
          DATA(travel) = travel_cost( present = <crew>-present km = km ).
          DATA(contiguous) = is_contiguous( block_key = item-block_key previous = <crew>-assigned
                                            home_key = <crew>-home_key ).
          DATA(bonus) = COND ty_amount( WHEN contiguous = abap_true THEN contiguity / 100 * item-value_idr ).
          DATA(score) = item-deferral_idr + bonus - travel.
          CHECK score > 0.

          DATA(share) = CONV decfloat34( 1 ).
          IF item-man_days > <crew>-remaining_md.
            share = <crew>-remaining_md / item-man_days.
            " a crew's first block can be a multi-day job it merely starts; a later block has
            " to mostly fit, or the day fragments
            CHECK share >= min_partial_share OR <crew>-assigned IS INITIAL.
          ENDIF.

          DATA(density) = score / item-man_days.
          IF best = 0 OR density > best_density.
            best = item_index.
            best_density = density.
            best_share = share.
            best_assignment = VALUE #( item           = item
                                       travel_km      = km
                                       travel_idr     = round( val = travel dec = 0 )
                                       contiguity_idr = round( val = bonus dec = 0 )
                                       contiguous     = contiguous
                                       score          = score ).
          ENDIF.
        ENDLOOP.

        CHECK best > 0.
        best_assignment-share    = round( val = best_share dec = 3 ).
        best_assignment-man_days = best_assignment-item-man_days * best_share.
        best_assignment-seq      = lines( <crew>-assigned ) + 1.
        APPEND best_assignment TO <crew>-assigned.
        <crew>-remaining_md = <crew>-remaining_md - best_assignment-man_days.
        <crew>-position     = best_assignment-item-centroid.
        INSERT VALUE #( block_key = best_assignment-item-block_key crew_code = <crew>-crew_code ) INTO TABLE taken.
        progress = abap_true.
      ENDLOOP.
    ENDWHILE.
  ENDMETHOD.


  METHOD crew_objective.
    DATA seen TYPE ty_assignments.
    DATA(position) = crew-home.

    LOOP AT crew-assigned INTO DATA(assignment).
      DATA(km) = zcl_est_geo=>km( a = position b = assignment-item-centroid ).
      DATA(travel) = travel_cost( present = crew-present km = km ).
      DATA(contiguous) = is_contiguous( block_key = assignment-item-block_key previous = seen
                                        home_key = crew-home_key ).
      DATA(bonus) = COND ty_amount( WHEN contiguous = abap_true THEN contiguity / 100 * assignment-item-value_idr ).
      result = result + assignment-item-deferral_idr * assignment-share + bonus * assignment-share - travel.
      position = assignment-item-centroid.
      APPEND assignment TO seen.
    ENDLOOP.
  ENDMETHOD.


  METHOD swap_pass.
    DATA(evaluations) = 0.

    DO max_swap_passes TIMES.
      DATA(improved) = abap_false.

      LOOP AT crews ASSIGNING FIELD-SYMBOL(<crew>).
        DATA(base) = crew_objective( crew = <crew> contiguity = contiguity ).

        LOOP AT <crew>-assigned ASSIGNING FIELD-SYMBOL(<slot>).
          CHECK <slot>-share >= 1.
          DATA(room) = <crew>-remaining_md + <slot>-man_days.

          LOOP AT items INTO DATA(candidate).
            CHECK in_pool( crew = <crew> item = candidate ) = abap_true.
            CHECK NOT line_exists( taken[ block_key = candidate-block_key ] ).
            CHECK candidate-man_days <= room.

            evaluations = evaluations + 1.
            IF evaluations > max_swap_evals.
              RETURN.
            ENDIF.

            DATA(old) = <slot>.
            <slot> = VALUE #( item = candidate share = 1 man_days = candidate-man_days seq = old-seq ).
            DATA(trial) = crew_objective( crew = <crew> contiguity = contiguity ).
            IF trial > base + 1.
              <crew>-remaining_md = room - candidate-man_days.
              DELETE taken WHERE block_key = old-item-block_key.
              INSERT VALUE #( block_key = candidate-block_key crew_code = <crew>-crew_code ) INTO TABLE taken.
              base = trial.
              result = result + 1.
              improved = abap_true.
              room = <crew>-remaining_md + <slot>-man_days.
            ELSE.
              <slot> = old.
            ENDIF.
          ENDLOOP.
        ENDLOOP.
      ENDLOOP.

      IF improved = abap_false.
        EXIT.
      ENDIF.
    ENDDO.
  ENDMETHOD.


  METHOD finalise.
    LOOP AT crews ASSIGNING FIELD-SYMBOL(<crew>).
      DATA(position) = <crew>-home.
      DATA(seen) = VALUE ty_assignments( ).
      LOOP AT <crew>-assigned ASSIGNING FIELD-SYMBOL(<assignment>).
        DATA(km) = zcl_est_geo=>km( a = position b = <assignment>-item-centroid ).
        DATA(travel) = travel_cost( present = <crew>-present km = km ).
        DATA(contiguous) = is_contiguous( block_key = <assignment>-item-block_key previous = seen
                                          home_key = <crew>-home_key ).
        DATA(bonus) = COND ty_amount( WHEN contiguous = abap_true
                                      THEN contiguity / 100 * <assignment>-item-value_idr ).
        <assignment>-travel_km      = km.
        <assignment>-travel_idr     = round( val = travel dec = 0 ).
        <assignment>-contiguity_idr = round( val = bonus dec = 0 ).
        <assignment>-contiguous     = contiguous.
        <assignment>-score          = round( val = <assignment>-item-deferral_idr * <assignment>-share
                                                   + bonus * <assignment>-share - travel dec = 0 ).
        position = <assignment>-item-centroid.
        APPEND <assignment> TO seen.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD upper_bound.
    TYPES:
      BEGIN OF ty_pool,
        division TYPE zest_crew-division,
        capacity TYPE decfloat34,
      END OF ty_pool.
    TYPES:
      BEGIN OF ty_ranked,
        density TYPE decfloat34,
        item    TYPE zcl_est_demand=>ty_item,
      END OF ty_ranked.
    DATA pools TYPE STANDARD TABLE OF ty_pool WITH EMPTY KEY.
    DATA ranked TYPE STANDARD TABLE OF ty_ranked WITH EMPTY KEY.

    " crews without a division share one pool over every block
    LOOP AT crews INTO DATA(crew).
      ASSIGN pools[ division = crew-division ] TO FIELD-SYMBOL(<pool>).
      IF sy-subrc <> 0.
        APPEND VALUE #( division = crew-division ) TO pools ASSIGNING <pool>.
      ENDIF.
      <pool>-capacity = <pool>-capacity + crew-capacity_md.
    ENDLOOP.

    LOOP AT pools INTO DATA(pool).
      ranked = VALUE #( FOR item IN items
                        WHERE ( man_days > 0 )
                        ( density = item-deferral_idr / item-man_days item = item ) ).
      IF pool-division IS NOT INITIAL.
        DELETE ranked WHERE item-division <> pool-division.
      ENDIF.
      SORT ranked BY density DESCENDING.

      DATA(left) = pool-capacity.
      LOOP AT ranked INTO DATA(line).
        IF left <= 0.
          EXIT.
        ENDIF.
        DATA(take) = nmin( val1 = CONV decfloat34( 1 ) val2 = left / line-item-man_days ).
        result = result + line-item-deferral_idr * take.
        left = left - line-item-man_days * take.
      ENDLOOP.
    ENDLOOP.
    result = round( val = result dec = 0 ).
  ENDMETHOD.


  METHOD achieved.
    LOOP AT crews INTO DATA(crew).
      LOOP AT crew-assigned INTO DATA(assignment).
        result = result + assignment-item-deferral_idr * assignment-share.
      ENDLOOP.
    ENDLOOP.
    result = round( val = result dec = 0 ).
  ENDMETHOD.

ENDCLASS.
