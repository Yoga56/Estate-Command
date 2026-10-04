CLASS zcl_est_plan_builder DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Tomorrow's assignment as a document a manager can accept, reject or defer.
    "!
    "! The server computes, the model writes: every figure comes from ZCL_EST_SCHEDULER and is
    "! handed to the model as the evidence; the model only words it. The guardrail is checked,
    "! not trusted: ZCL_EST_AUDIT re-reads every number and block label in the words and looks
    "! for it in the evidence, with one self-correction pass. Nothing generated is
    "! load-bearing: when every provider fails, the plan still carries its figures (status F).
    TYPES ty_amount TYPE decfloat34.
    " Component names equal the CDS element names of ZR_EST_PLAN / ZR_EST_PLAN_L,
    " so the behavior handler can move them with CORRESPONDING.
    TYPES:
      BEGIN OF ty_header,
        estate            TYPE zest_plan-estate,
        operation         TYPE zest_plan-operation,
        plandate          TYPE d,
        status            TYPE zest_plan-status,
        statuscriticality TYPE int1,
        crews             TYPE i,
        present           TYPE i,
        capacitymd        TYPE decfloat34,
        blocksdue         TYPE i,
        mandaysdue        TYPE decfloat34,
        blocksassigned    TYPE i,
        mandaysassigned   TYPE decfloat34,
        deferraldue       TYPE ty_amount,
        valuerecovered    TYPE ty_amount,
        upperbound        TYPE ty_amount,
        gappercent        TYPE decfloat34,
        contiguitycost    TYPE ty_amount,
        contiguitypercent TYPE decfloat34,
        swaps             TYPE i,
        rainmm            TYPE decfloat34,
        rainprobability   TYPE i,
        weathersource     TYPE zest_plan-weather_source,
        stopswork         TYPE abap_bool,
        stopreason        TYPE zest_plan-stop_reason,
        overrides         TYPE string,
        headline          TYPE zest_plan-headline,
        summary           TYPE string,
        whytext           TYPE string,
        auditchecked      TYPE i,
        auditunverified   TYPE zest_plan-audit_unverified,
        auditcriticality  TYPE int1,
        providerid        TYPE zest_plan-provider_id,
        modelid           TYPE zest_plan-model_id,
        inputtokens       TYPE i,
        outputtokens      TYPE i,
        errortext         TYPE zest_plan-error_text,
        prompt            TYPE string,
        rawresponse       TYPE string,
      END OF ty_header.
    TYPES:
      BEGIN OF ty_line,
        linenumber    TYPE i,
        isassigned    TYPE abap_bool,
        crewcode      TYPE zest_plan_l-crew_code,
        crewrange     TYPE zest_plan_l-crew_range,
        crewpresent   TYPE i,
        sequenceno    TYPE i,
        blockkey      TYPE zest_plan_l-block_key,
        blocklabel    TYPE zest_plan_l-block_label,
        division      TYPE zest_plan_l-division,
        activity      TYPE zest_plan_l-activity,
        quantity      TYPE decfloat34,
        qtyunit       TYPE zest_plan_l-qty_unit,
        mandays       TYPE decfloat34,
        workshare     TYPE decfloat34,
        urgency       TYPE decfloat34,
        dayssince     TYPE i,
        targetdays    TYPE i,
        blockvalue    TYPE ty_amount,
        deferral      TYPE ty_amount,
        contiguity    TYPE ty_amount,
        travelkm      TYPE decfloat34,
        travelcost    TYPE ty_amount,
        score         TYPE ty_amount,
        iscontiguous  TYPE abap_bool,
        roadcondition TYPE zest_plan_l-road_condition,
        criticality   TYPE int1,
        linenote      TYPE zest_plan_l-line_note,
      END OF ty_line,
      ty_lines TYPE STANDARD TABLE OF ty_line WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_plan,
        header TYPE ty_header,
        lines  TYPE ty_lines,
      END OF ty_plan.
    TYPES:
      BEGIN OF ty_answer,
        answer          TYPE string,
        modelid         TYPE zest_plan-model_id,
        auditchecked    TYPE i,
        auditunverified TYPE zest_plan-audit_unverified,
      END OF ty_answer.
    TYPES:
      "! component names match ZA_EST_HANDOVER
      BEGIN OF ty_handover,
        handoverheadline TYPE zest_plan-headline,
        decided          TYPE string,
        openpositions    TYPE string,
        watchlist        TYPE string,
        handovernote     TYPE string,
        modelid          TYPE zest_plan-model_id,
        auditunverified  TYPE zest_plan-audit_unverified,
      END OF ty_handover.
    TYPES:
      "! component names match ZA_EST_OUTCOME
      BEGIN OF ty_outcome,
        blocklabel    TYPE zest_plan_l-block_label,
        crewcode      TYPE zest_plan_l-crew_code,
        activity      TYPE zest_plan_l-activity,
        plannedqty    TYPE decfloat34,
        actualqty     TYPE decfloat34,
        qtyunit       TYPE zest_plan_l-qty_unit,
        adherencepct  TYPE decfloat34,
        outcomestatus TYPE c LENGTH 20,
        orderids      TYPE c LENGTH 80,
        criticality   TYPE int1,
      END OF ty_outcome,
      ty_outcomes TYPE STANDARD TABLE OF ty_outcome WITH EMPTY KEY.

    CONSTANTS:
      BEGIN OF status,
        proposed     TYPE zest_plan-status VALUE 'P',
        figures_only TYPE zest_plan-status VALUE 'F',
        accepted     TYPE zest_plan-status VALUE 'A',
        rejected     TYPE zest_plan-status VALUE 'R',
        deferred     TYPE zest_plan-status VALUE 'D',
      END OF status,
      BEGIN OF criticality,
        neutral  TYPE int1 VALUE 0,
        negative TYPE int1 VALUE 1,
        critical TYPE int1 VALUE 2,
        positive TYPE int1 VALUE 3,
      END OF criticality.

    "! Plans one operation of one estate for a day and lets the model word it.
    "! @parameter plan_date | blank = the first day beyond the estate's data
    CLASS-METHODS build
      IMPORTING estate        TYPE zest_plan-estate
                operation     TYPE zest_plan-operation
                plan_date     TYPE d OPTIONAL
                overrides     TYPE zcl_est_scheduler=>ty_overrides OPTIONAL
                provider_id   TYPE zest_plan-provider_id OPTIONAL
      RETURNING VALUE(result) TYPE ty_plan
      RAISING   zcx_est_ai.

    "! New words from the model on the figures stored with the plan; nothing is recomputed.
    CLASS-METHODS refresh_words
      IMPORTING header        TYPE ty_header
                provider_id   TYPE zest_plan-provider_id OPTIONAL
      RETURNING VALUE(result) TYPE ty_header.

    CLASS-METHODS ask
      IMPORTING header        TYPE ty_header
                question      TYPE string
      RETURNING VALUE(result) TYPE ty_answer
      RAISING   zcx_est_ai.

    "! The assignment as a work document: the lines are filled in by the system, the model
    "! writes the instructions. Nothing is sent and nothing is posted.
    CLASS-METHODS draft_artifact
      IMPORTING header        TYPE ty_header
                lines         TYPE ty_lines
      RETURNING VALUE(result) TYPE string.

    "! The shift handover note: what was decided, what is open, what goes wrong first.
    CLASS-METHODS handover
      IMPORTING estate        TYPE zest_plan-estate
      RETURNING VALUE(result) TYPE ty_handover
      RAISING   zcx_est_ai.

    "! An accepted plan read back against the ledger once its date has passed.
    CLASS-METHODS outcomes
      IMPORTING header        TYPE ty_header
                lines         TYPE ty_lines
      RETURNING VALUE(result) TYPE ty_outcomes.

    "! The overrides of a replan as stored on the plan, and back
    CLASS-METHODS overrides_to_json
      IMPORTING overrides     TYPE zcl_est_scheduler=>ty_overrides
      RETURNING VALUE(result) TYPE string.

    CLASS-METHODS overrides_from_json
      IMPORTING json          TYPE string
      RETURNING VALUE(result) TYPE zcl_est_scheduler=>ty_overrides.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_words,
        headline TYPE string,
        summary  TYPE string,
        why      TYPE string,
        risks    TYPE string_table,
      END OF ty_words.
    TYPES:
      BEGIN OF ty_artifact_words,
        purpose      TYPE string,
        instructions TYPE string_table,
        acceptance   TYPE string,
        caveat       TYPE string,
      END OF ty_artifact_words.
    TYPES:
      BEGIN OF ty_handover_words,
        headline TYPE string,
        decided  TYPE string_table,
        open     TYPE string_table,
        watch    TYPE string_table,
        note     TYPE string,
      END OF ty_handover_words.

    "! Lines for the not-reached list on the plan, most valuable first
    CONSTANTS max_not_reached_lines TYPE i VALUE 40.

    CLASS-METHODS evidence
      IMPORTING data          TYPE REF TO zcl_est_data
                header        TYPE ty_header
                plan          TYPE zcl_est_scheduler=>ty_plan
      RETURNING VALUE(result) TYPE string.

    CLASS-METHODS to_lines
      IMPORTING plan          TYPE zcl_est_scheduler=>ty_plan
      RETURNING VALUE(result) TYPE ty_lines.

    "! Asks the providers in turn, audits the words, and allows one rewrite
    CLASS-METHODS write_words
      IMPORTING provider_id TYPE zest_plan-provider_id
      CHANGING  header      TYPE ty_header.

    CLASS-METHODS candidates
      IMPORTING estate        TYPE zest_plan-estate
                provider_id   TYPE zest_plan-provider_id
      RETURNING VALUE(result) TYPE zcl_est_ai_factory=>ty_configs.

    "! Free text from the first provider that answers
    CLASS-METHODS ask_text
      IMPORTING estate        TYPE zest_plan-estate
                provider_id   TYPE zest_plan-provider_id OPTIONAL
                instructions  TYPE string
                prompt        TYPE string
                json_schema   TYPE string OPTIONAL
      EXPORTING model_id      TYPE zest_plan-model_id
      RETURNING VALUE(result) TYPE string
      RAISING   zcx_est_ai.

    "! The JSON object between the outer braces of a model answer
    CLASS-METHODS json_object
      IMPORTING text          TYPE string
      RETURNING VALUE(result) TYPE string
      RAISING   zcx_est_ai.

    CLASS-METHODS words_prompt
      RETURNING VALUE(result) TYPE string.

    CLASS-METHODS words_schema
      RETURNING VALUE(result) TYPE string.

    CLASS-METHODS bullets
      IMPORTING lines         TYPE string_table
      RETURNING VALUE(result) TYPE string.

    CLASS-METHODS figures_only_headline
      IMPORTING header        TYPE ty_header
      RETURNING VALUE(result) TYPE string.
ENDCLASS.



CLASS zcl_est_plan_builder IMPLEMENTATION.

  METHOD build.
    DATA(data) = NEW zcl_est_data( estate ).
    DATA(op) = CONV zest_plan-operation( to_lower( operation ) ).
    DATA(operations) = zcl_est_data=>operations( ).
    IF NOT line_exists( operations[ table_line = op ] ).
      RAISE EXCEPTION NEW zcx_est_ai( message = |Operation { operation } is not planned here; | &&
                                                |use harvest, prune, weed or spray| ).
    ENDIF.
    DATA(day) = COND d( WHEN plan_date IS NOT INITIAL THEN plan_date ELSE data->default_plan_date( ) ).

    DATA(weather) = zcl_est_weather=>forecast( latitude  = CONV #( data->estate-latitude )
                                               longitude = CONV #( data->estate-longitude )
                                               on        = day ).
    DATA(plan) = NEW zcl_est_scheduler( data )->plan( operation = op
                                                      on        = day
                                                      overrides = overrides
                                                      weather   = weather ).

    result-header = VALUE #(
      estate            = estate
      operation         = op
      plandate          = day
      crews             = lines( plan-crews )
      present           = plan-present
      capacitymd        = round( val = plan-capacity_md dec = 2 )
      blocksdue         = lines( plan-items )
      mandaysdue        = round( val = plan-need_md dec = 2 )
      deferraldue       = round( val = plan-deferral_due dec = 0 )
      valuerecovered    = plan-achieved
      upperbound        = plan-upper_bound
      gappercent        = plan-gap_pct
      contiguitycost    = plan-contiguity_cost
      contiguitypercent = plan-contiguity_pct
      swaps             = plan-swaps
      rainmm            = COND #( WHEN plan-weather-known = abap_true THEN plan-weather-rain_mm )
      rainprobability   = plan-weather-probability
      weathersource     = plan-weather-source
      stopswork         = plan-stops_work
      stopreason        = plan-stop_reason
      overrides         = overrides_to_json( overrides ) ).

    result-lines = to_lines( plan ).
    LOOP AT result-lines INTO DATA(line) WHERE isassigned = abap_true.
      result-header-blocksassigned  = result-header-blocksassigned + 1.
      result-header-mandaysassigned = result-header-mandaysassigned + line-mandays.
    ENDLOOP.

    result-header-prompt = evidence( data = data header = result-header plan = plan ).
    write_words( EXPORTING provider_id = COND #( WHEN provider_id IS NOT INITIAL THEN provider_id
                                                 ELSE data->estate-default_provider )
                 CHANGING  header      = result-header ).
  ENDMETHOD.


  METHOD refresh_words.
    result = header.
    write_words( EXPORTING provider_id = provider_id CHANGING header = result ).
  ENDMETHOD.


  METHOD to_lines.
    DATA(number) = 0.

    LOOP AT plan-crews INTO DATA(crew).
      LOOP AT crew-assigned INTO DATA(assignment).
        number = number + 1.
        APPEND VALUE #(
          linenumber    = number
          isassigned    = abap_true
          crewcode      = crew-crew_code
          crewrange     = crew-range_label
          crewpresent   = crew-present
          sequenceno    = assignment-seq
          blockkey      = assignment-item-block_key
          blocklabel    = assignment-item-block_label
          division      = assignment-item-division
          activity      = assignment-item-activity
          quantity      = round( val = assignment-item-qty * assignment-share dec = 2 )
          qtyunit       = assignment-item-unit
          mandays       = round( val = assignment-man_days dec = 2 )
          workshare     = assignment-share
          urgency       = assignment-item-urgency
          dayssince     = assignment-item-days_since
          targetdays    = assignment-item-target_days
          blockvalue    = round( val = assignment-item-value_idr * assignment-share dec = 0 )
          deferral      = round( val = assignment-item-deferral_idr * assignment-share dec = 0 )
          contiguity    = assignment-contiguity_idr
          travelkm      = round( val = CONV decfloat34( assignment-travel_km ) dec = 2 )
          travelcost    = assignment-travel_idr
          score         = assignment-score
          iscontiguous  = assignment-contiguous
          roadcondition = assignment-item-road_condition
          criticality   = COND #( WHEN assignment-item-urgency >= '1.5' THEN criticality-negative
                                  WHEN assignment-item-urgency >= 1 THEN criticality-critical
                                  ELSE criticality-positive )
          linenote      = COND #( WHEN assignment-share < 1
                                  THEN |started: { zcl_est_data=>num( value = assignment-share * 100 decimals = 0 ) }% of the job fits the day|
                                  WHEN assignment-item-in_progress = abap_true THEN `continues a round in progress` ) ) TO result.
      ENDLOOP.
    ENDLOOP.

    " what nobody reaches tomorrow, so the cost of the day's limits is on the same page
    LOOP AT plan-not_reached INTO DATA(item).
      IF sy-tabix > max_not_reached_lines.
        EXIT.
      ENDIF.
      number = number + 1.
      APPEND VALUE #(
        linenumber    = number
        isassigned    = abap_false
        blockkey      = item-block_key
        blocklabel    = item-block_label
        division      = item-division
        activity      = item-activity
        quantity      = item-qty
        qtyunit       = item-unit
        mandays       = item-man_days
        workshare     = 0
        urgency       = item-urgency
        dayssince     = item-days_since
        targetdays    = item-target_days
        blockvalue    = item-value_idr
        deferral      = item-deferral_idr
        roadcondition = item-road_condition
        criticality   = criticality-negative
        linenote      = |not reached: { zcl_est_data=>num( value = item-deferral_per_day decimals = 0 ) } IDR lost per day it waits| ) TO result.
    ENDLOOP.
  ENDMETHOD.


  METHOD evidence.
    DATA(op) = header-operation.
    result =
      |Estate { header-estate } ({ data->estate-estate_name }), operation { op }, plan for { header-plandate DATE = ISO }.\n| &&
      |Money is in IDR. Every figure below is SCHEDULED: computed by the scheduler for a day that has not happened, | &&
      |from the work-order ledger, the block register and the assumption register. | &&
      COND string( WHEN data->estate-is_sample = abap_true
                   THEN |The estate is SAMPLE data generated for a demonstration, not the client's records.\n|
                   ELSE |Block areas and the ledger come from the estate's own records.\n| ) &&
      |\nWEATHER\n| &&
      COND string( WHEN header-rainmm IS NOT INITIAL OR plan-weather-known = abap_true
                   THEN |Rain on the day: { zcl_est_data=>num( value = header-rainmm decimals = 1 ) } mm | &&
                        |({ header-weathersource }), chance of rain { header-rainprobability }%\n|
                   ELSE |Rain on the day: unknown ({ header-weathersource })\n| ) &&
      COND string( WHEN header-stopswork = abap_true THEN |Work stops: { header-stopreason }\n| ) &&
      |\nCAPACITY\n| &&
      |{ header-crews } crews, { header-present } people expected, { zcl_est_data=>num( header-capacitymd ) } man-days | &&
      |available; { zcl_est_data=>num( header-mandaysdue ) } man-days needed for everything due.\n| &&
      |Binding constraint: { plan-binding }\n| &&
      |\nPLAN\n| &&
      |Blocks due: { header-blocksdue }, deferral value of everything due: { zcl_est_data=>num( value = header-deferraldue decimals = 0 ) }\n| &&
      |Blocks assigned: { header-blocksassigned }, man-days assigned: { zcl_est_data=>num( header-mandaysassigned ) }, | &&
      |deferral value recovered: { zcl_est_data=>num( value = header-valuerecovered decimals = 0 ) }\n| &&
      |Relaxed upper bound (fractional, no geography): { zcl_est_data=>num( value = header-upperbound decimals = 0 ) }, | &&
      |gap to it: { zcl_est_data=>num( value = header-gappercent decimals = 1 ) }%\n| &&
      |Contiguity bonus: { zcl_est_data=>num( value = header-contiguitypercent decimals = 0 ) }% of block value; | &&
      |keeping crews on adjacent blocks gave up { zcl_est_data=>num( value = header-contiguitycost decimals = 0 ) } | &&
      |in deferral value against the scattered plan\n| &&
      |Swap improvements accepted: { header-swaps }\n|.

    result = result && |\nCREWS\n|.
    LOOP AT plan-crews INTO DATA(crew).
      result = result &&
        |- { crew-crew_code } ({ crew-crew_name }, division { crew-division }): { crew-present } of { crew-on_roll } | &&
        |expected ({ crew-basis }), { zcl_est_data=>num( crew-capacity_md ) } man-days| &&
        COND string( WHEN crew-assigned IS INITIAL THEN |, nothing assigned\n|
                     ELSE |, blocks { crew-range_label }:\n| ).
      LOOP AT crew-assigned INTO DATA(assignment).
        result = result &&
          |  { assignment-seq }. block { assignment-item-block_label } { assignment-item-activity }: | &&
          |{ zcl_est_data=>num( value = assignment-item-qty * assignment-share decimals = 0 ) } { assignment-item-unit }, | &&
          |{ zcl_est_data=>num( assignment-man_days ) } man-days, { assignment-item-days_since } days since last done | &&
          |against a { assignment-item-target_days }-day round (urgency { zcl_est_data=>num( assignment-item-urgency ) }), | &&
          |deferral { zcl_est_data=>num( value = assignment-item-deferral_idr * assignment-share decimals = 0 ) }, | &&
          |travel { zcl_est_data=>num( value = CONV decfloat34( assignment-travel_km ) decimals = 1 ) } km| &&
          COND string( WHEN assignment-contiguous = abap_true THEN `, next to the crew's previous block` ) &&
          COND string( WHEN assignment-item-road_condition IS NOT INITIAL THEN |, road { assignment-item-road_condition }| ) &&
          |\n|.
      ENDLOOP.
    ENDLOOP.

    IF plan-not_reached IS NOT INITIAL.
      result = result && |\nNOT REACHED ({ lines( plan-not_reached ) } blocks, { zcl_est_data=>num( value = plan-not_reached_per_day decimals = 0 ) } | &&
                         |lost per day they wait; most valuable first)\n|.
      LOOP AT plan-not_reached INTO DATA(item).
        IF sy-tabix > 10.
          EXIT.
        ENDIF.
        result = result &&
          |- block { item-block_label } { item-activity }: urgency { zcl_est_data=>num( item-urgency ) }, | &&
          |{ zcl_est_data=>num( value = item-deferral_per_day decimals = 0 ) } per day, { zcl_est_data=>num( item-man_days ) } man-days\n|.
      ENDLOOP.
    ENDIF.

    result = result && |\nASSUMPTIONS\n{ zcl_est_assumptions=>describe( plan-used ) }|.
  ENDMETHOD.


  METHOD words_prompt.
    result =
      |You write the plan note an oil-palm estate's Assistant Manager reads before approving tomorrow's | &&
      |crew assignment. The scheduler has already decided; you explain the decision.\n| &&
      |CRITICAL NUMERIC GUARDRAIL: quote only figures given in the user message, verbatim. Never add up, | &&
      |convert, scale or estimate. A figure you work out yourself is reported as unverified.\n| &&
      |Every figure is scheduled, not recorded: never write that work was done or an order was sent. | &&
      |If the data is sample data, say so once.\n| &&
      |headline: one sentence under 120 characters, leading with what the crews do tomorrow.\n| &&
      |summary: two or three sentences: which crews go where, what is left and what it costs per day.\n| &&
      |why: two to four sentences: why these blocks first (urgency and deferral value per man-day), the binding | &&
      |constraint, the gap to the upper bound and what contiguity cost.\n| &&
      |risks: at most three short lines a manager should check before approving (weather, roads, a thin crew).\n| &&
      |Name blocks by their label and crews by their code. Return one JSON object only.|.
  ENDMETHOD.


  METHOD words_schema.
    result =
      |\{"type":"object","properties":\{| &&
      |"headline":\{"type":"string"\},"summary":\{"type":"string"\},"why":\{"type":"string"\},| &&
      |"risks":\{"type":"array","items":\{"type":"string"\}\}\},| &&
      |"required":["headline","summary","why","risks"]\}|.
  ENDMETHOD.


  METHOD candidates.
    TRY.
        result = zcl_est_ai_factory=>get_candidates( provider_id ).
      CATCH zcx_est_ai.
        " the provider asked for was removed or switched off since: take the estate's default
        TRY.
            SELECT SINGLE default_provider FROM zest_estate WHERE estate = @estate INTO @DATA(default_provider).
            result = zcl_est_ai_factory=>get_candidates( default_provider ).
          CATCH zcx_est_ai.
            CLEAR result.
        ENDTRY.
    ENDTRY.
  ENDMETHOD.


  METHOD write_words.
    DATA words TYPE ty_words.

    CLEAR: header-errortext, header-auditunverified, header-auditchecked.
    DATA(configs) = candidates( estate = header-estate provider_id = provider_id ).
    IF configs IS INITIAL.
      header-errortext = `No active AI provider; run ZCL_EST_SEED and maintain the API key`.
    ENDIF.

    LOOP AT configs INTO DATA(config).
      CLEAR words.
      TRY.
          DATA(provider) = zcl_est_ai_factory=>create( config ).
          DATA(answer) = provider->complete( system_prompt = words_prompt( )
                                             user_prompt   = header-prompt
                                             json_schema   = words_schema( ) ).
          /ui2/cl_json=>deserialize( EXPORTING json = json_object( answer-text ) CHANGING data = words ).
          IF words-headline IS INITIAL.
            RAISE EXCEPTION NEW zcx_est_ai( message = |{ config-provider_id }: answer has no headline| ).
          ENDIF.

          DATA(text) = |{ words-headline }\n{ words-summary }\n{ words-why }\n{ bullets( words-risks ) }|.
          DATA(audit) = zcl_est_audit=>audit( answer = text evidence = header-prompt ).

          " one self-correction pass: name the figures that are not in the data
          IF audit-clean = abap_false.
            DATA(retry) = provider->complete(
              system_prompt = words_prompt( )
              user_prompt   = |{ header-prompt }\n\nYOUR PREVIOUS ANSWER\n{ answer-text }\n\n| &&
                              |These figures in it appear nowhere above: { zcl_est_audit=>summary( audit ) }. | &&
                              |Rewrite the answer without them, quoting only the figures given.|
              json_schema   = words_schema( ) ).
            DATA(rewritten) = VALUE ty_words( ).
            /ui2/cl_json=>deserialize( EXPORTING json = json_object( retry-text ) CHANGING data = rewritten ).
            DATA(retext) = |{ rewritten-headline }\n{ rewritten-summary }\n{ rewritten-why }\n{ bullets( rewritten-risks ) }|.
            DATA(reaudit) = zcl_est_audit=>audit( answer = retext evidence = header-prompt ).
            IF rewritten-headline IS NOT INITIAL AND lines( reaudit-unverified ) < lines( audit-unverified ).
              words  = rewritten.
              audit  = reaudit.
              answer-text          = retry-text.
              answer-input_tokens  = answer-input_tokens + retry-input_tokens.
              answer-output_tokens = answer-output_tokens + retry-output_tokens.
            ENDIF.
          ENDIF.

        CATCH zcx_est_ai cx_sy_conversion_error INTO DATA(error).
          " every provider's failure, the one asked for first, each cut short
          DATA(failure) = error->get_text( ).
          failure = substring( val = failure len = nmin( val1 = strlen( failure ) val2 = 100 ) ).
          header-errortext = COND #( WHEN header-errortext IS INITIAL THEN failure
                                     ELSE |{ header-errortext }; { failure }| ).
          CONTINUE.
      ENDTRY.

      header-providerid       = config-provider_id.
      header-modelid          = config-model_id.
      header-rawresponse      = answer-text.
      header-inputtokens      = answer-input_tokens.
      header-outputtokens     = answer-output_tokens.
      header-headline         = words-headline.
      header-summary          = |{ words-summary }{ COND string( WHEN words-risks IS NOT INITIAL
                                                                 THEN |\n\nCheck before approving:\n{ bullets( words-risks ) }| ) }|.
      header-whytext          = words-why.
      header-auditchecked     = audit-checked.
      header-auditunverified  = zcl_est_audit=>summary( audit ).
      header-auditcriticality = COND #( WHEN audit-clean = abap_true THEN criticality-positive ELSE criticality-critical ).
      header-status           = status-proposed.
      header-statuscriticality = criticality-critical.
      CLEAR header-errortext.
      RETURN.
    ENDLOOP.

    " every provider failed: the figures stand on their own
    header-status            = status-figures_only.
    header-statuscriticality = criticality-critical.
    header-headline          = figures_only_headline( header ).
    header-summary           = `The AI step failed; the plan below is the scheduler's own, with every figure computed.`.
    header-auditcriticality  = criticality-neutral.
  ENDMETHOD.


  METHOD figures_only_headline.
    result = COND #(
      WHEN header-stopswork = abap_true
      THEN |{ header-operation } { header-plandate DATE = ISO }: no work - { header-stopreason }|
      ELSE |{ header-operation } { header-plandate DATE = ISO }: { header-blocksassigned } blocks to { header-crews } crews, | &&
           |{ zcl_est_data=>num( header-mandaysassigned ) } man-days, { header-blocksdue - header-blocksassigned } due blocks not reached| ).
  ENDMETHOD.


  METHOD bullets.
    LOOP AT lines INTO DATA(line) WHERE table_line IS NOT INITIAL.
      result = |{ result }- { line }\n|.
    ENDLOOP.
  ENDMETHOD.


  METHOD json_object.
    " models sometimes wrap the object in a markdown fence: keep what is between the outer braces
    DATA(first_brace) = find( val = text sub = '{' ).
    DATA(last_brace) = find( val = text sub = '}' occ = -1 ).
    IF first_brace < 0 OR last_brace < first_brace.
      RAISE EXCEPTION NEW zcx_est_ai( message = `The model's answer is not JSON` ).
    ENDIF.
    result = substring( val = text off = first_brace len = last_brace - first_brace + 1 ).
  ENDMETHOD.


  METHOD ask_text.
    DATA first_error TYPE REF TO zcx_est_ai.

    DATA(configs) = candidates( estate = estate provider_id = provider_id ).
    IF configs IS INITIAL.
      RAISE EXCEPTION NEW zcx_est_ai( message = `No active AI provider; run ZCL_EST_SEED and maintain the API key` ).
    ENDIF.

    LOOP AT configs INTO DATA(config).
      TRY.
          result = zcl_est_ai_factory=>create( config )->complete( system_prompt = instructions
                                                                  user_prompt   = prompt
                                                                  json_schema   = json_schema )-text.
          model_id = config-model_id.
          RETURN.
        CATCH zcx_est_ai INTO DATA(failure).
          IF first_error IS NOT BOUND.
            first_error = failure.
          ENDIF.
      ENDTRY.
    ENDLOOP.

    RAISE EXCEPTION first_error.
  ENDMETHOD.


  METHOD ask.
    DATA model_id TYPE zest_plan-model_id.

    DATA(prompt) = |{ header-prompt }\n\nTHE PLAN NOTE\n{ header-headline }\n{ header-summary }\n{ header-whytext }\n| &&
                   |\nQUESTION\n{ question }|.
    result-answer = ask_text(
      EXPORTING estate       = header-estate
                provider_id  = header-providerid
                instructions = |You are the analyst beside an oil-palm estate manager looking at tomorrow's plan. | &&
                               |Answer from the figures given and nothing else. Quote figures verbatim; never add up, | &&
                               |convert or estimate - a figure you compute is reported as unverified. A scheduled | &&
                               |figure is a plan, never a record. If the data cannot answer, say what is missing. | &&
                               |Lead with the finding. At most five sentences. Name blocks by their label.|
                prompt       = prompt
      IMPORTING model_id     = model_id ).
    result-modelid = model_id.

    DATA(audit) = zcl_est_audit=>audit( answer = result-answer evidence = prompt ).
    result-auditchecked    = audit-checked.
    result-auditunverified = zcl_est_audit=>summary( audit ).
  ENDMETHOD.


  METHOD draft_artifact.
    DATA words TYPE ty_artifact_words.
    DATA model_id TYPE zest_plan-model_id.

    DATA(kind) = SWITCH string( header-operation WHEN zcl_est_data=>op-harvest THEN `Harvest assignment`
                                                 ELSE `Upkeep assignment` ).
    DATA(document) =
      |{ kind } - DRAFT, nothing sent, nothing posted\n| &&
      |Estate { header-estate }, { header-operation }, work date { header-plandate DATE = ISO }\n| &&
      |Approver: Assistant Manager\n\n|.

    DATA(crew) = VALUE zest_plan_l-crew_code( ).
    LOOP AT lines INTO DATA(line) WHERE isassigned = abap_true.
      IF line-crewcode <> crew.
        crew = line-crewcode.
        document = |{ document }{ line-crewcode } ({ line-crewpresent } expected), blocks { line-crewrange }\n|.
      ENDIF.
      document = |{ document }  { line-sequenceno }. block { line-blocklabel } { line-activity }: | &&
                 |{ zcl_est_data=>num( value = line-quantity decimals = 0 ) } { line-qtyunit }, | &&
                 |{ zcl_est_data=>num( line-mandays ) } man-days{ COND string( WHEN line-linenote IS NOT INITIAL
                                                                              THEN | ({ line-linenote })| ) }\n|.
    ENDLOOP.
    IF crew IS INITIAL.
      document = |{ document }No block is assigned{ COND string( WHEN header-stopreason IS NOT INITIAL
                                                                 THEN |: { header-stopreason }| ) }.\n|.
    ENDIF.

    TRY.
        DATA(answer) = ask_text(
          EXPORTING estate       = header-estate
                    provider_id  = header-providerid
                    instructions =
                      |You write the instruction text on an estate work document. The lines and routing are already | &&
                      |filled in. Your reader is a field supervisor: write plainly, in the imperative. Quote only the | &&
                      |figures in the document, verbatim. This is a DRAFT: never write that it was sent or approved. | &&
                      |Return one JSON object: purpose (one sentence citing the figure that triggered it), | &&
                      |instructions (2 to 4 steps), acceptance (what completion looks like and what to record on | &&
                      |return), caveat (the assumption a supervisor should know, or empty).|
                    prompt       = |{ document }\nEVIDENCE\n{ header-prompt }|
                    json_schema  = |\{"type":"object","properties":\{"purpose":\{"type":"string"\},| &&
                                   |"instructions":\{"type":"array","items":\{"type":"string"\}\},| &&
                                   |"acceptance":\{"type":"string"\},"caveat":\{"type":"string"\}\},| &&
                                   |"required":["purpose","instructions","acceptance","caveat"]\}|
          IMPORTING model_id     = model_id ).
        /ui2/cl_json=>deserialize( EXPORTING json = json_object( answer ) CHANGING data = words ).
        document = |{ document }\nPURPOSE\n{ words-purpose }\n\nINSTRUCTIONS\n{ bullets( words-instructions ) }| &&
                   |\nON COMPLETION\n{ words-acceptance }\n| &&
                   COND string( WHEN words-caveat IS NOT INITIAL THEN |\nNOTE\n{ words-caveat }\n| ) &&
                   |\n(instructions written by { model_id }; figures from the scheduler)\n|.
      CATCH zcx_est_ai cx_sy_conversion_error.
        document = |{ document }\n(instructions not written: the AI step failed; the lines above stand on their own)\n|.
    ENDTRY.

    result = document.
  ENDMETHOD.


  METHOD handover.
    DATA words TYPE ty_handover_words.
    DATA model_id TYPE zest_plan-model_id.

    GET TIME STAMP FIELD DATA(now).
    DATA(since) = cl_abap_tstmp=>subtractsecs( tstmp = now secs = 7 * 86400 ).

    SELECT operation, plan_date, status, headline, decided_by, decided_at, decision_note, due_date,
           expected_effect, blocks_due, blocks_assigned, value_recovered, deferral_due, stop_reason
      FROM zest_plan
      WHERE estate = @estate AND created_at >= @since
      ORDER BY plan_date DESCENDING, created_at DESCENDING
      INTO TABLE @DATA(plans).

    DATA(prompt) = |Estate { estate }. Plans of the last seven days, newest first. Status: P proposed and waiting, | &&
                   |F figures only (AI failed) and waiting, A accepted, R rejected, D deferred. Money in IDR, scheduled.\n|.
    LOOP AT plans INTO DATA(plan).
      prompt = prompt &&
        |- { plan-operation } for { plan-plan_date DATE = ISO }, status { plan-status }: { plan-headline }. | &&
        |Blocks due { plan-blocks_due }, assigned { plan-blocks_assigned }, deferral value recovered | &&
        |{ zcl_est_data=>num( value = CONV decfloat34( plan-value_recovered ) decimals = 0 ) } of | &&
        |{ zcl_est_data=>num( value = CONV decfloat34( plan-deferral_due ) decimals = 0 ) } due| &&
        COND string( WHEN plan-decided_by IS NOT INITIAL THEN |; decided by { plan-decided_by }| ) &&
        COND string( WHEN plan-decision_note IS NOT INITIAL THEN |; note: { plan-decision_note }| ) &&
        COND string( WHEN plan-due_date IS NOT INITIAL THEN |; deferred to { plan-due_date DATE = ISO }| ) &&
        COND string( WHEN plan-expected_effect IS NOT INITIAL THEN |; expected: { plan-expected_effect }| ) &&
        COND string( WHEN plan-stop_reason IS NOT INITIAL THEN |; weather: { plan-stop_reason }| ) && |\n|.
    ENDLOOP.
    IF plans IS INITIAL.
      prompt = prompt && |No plan was made in the last seven days.\n|.
    ENDIF.

    DATA(answer) = ask_text(
      EXPORTING estate       = estate
                instructions =
                  |You are writing the shift handover note for an oil-palm estate management team, for someone | &&
                  |arriving cold. Answer in order: what was decided, what is still open, what goes wrong first if | &&
                  |nobody acts. Quote only the figures given, verbatim; never add up or estimate. Nothing was posted | &&
                  |to any system: never imply an order was sent or a crew dispatched. A deferred plan has a clock | &&
                  |on it: give it its own line. A rejection is a decision, not a failure. Return one JSON object: | &&
                  |headline (one sentence), decided, open, watch (lists of at most five short lines), note (two or | &&
                  |three sentences). An empty log is a fact worth stating plainly.|
                prompt       = prompt
                json_schema  = |\{"type":"object","properties":\{"headline":\{"type":"string"\},| &&
                               |"decided":\{"type":"array","items":\{"type":"string"\}\},| &&
                               |"open":\{"type":"array","items":\{"type":"string"\}\},| &&
                               |"watch":\{"type":"array","items":\{"type":"string"\}\},"note":\{"type":"string"\}\},| &&
                               |"required":["headline","decided","open","watch","note"]\}|
      IMPORTING model_id     = model_id ).

    TRY.
        /ui2/cl_json=>deserialize( EXPORTING json = json_object( answer ) CHANGING data = words ).
      CATCH cx_sy_conversion_error.
        RAISE EXCEPTION NEW zcx_est_ai( message = `The handover answer could not be read` ).
    ENDTRY.

    result = VALUE #( handoverheadline = words-headline
                      decided          = bullets( words-decided )
                      openpositions    = bullets( words-open )
                      watchlist        = bullets( words-watch )
                      handovernote     = words-note
                      modelid          = model_id
                      auditunverified  = zcl_est_audit=>summary( zcl_est_audit=>audit(
                                           answer   = |{ words-headline }\n{ bullets( words-decided ) }{ bullets( words-open ) }| &&
                                                      |{ bullets( words-watch ) }{ words-note }|
                                           evidence = prompt ) ) ).
  ENDMETHOD.


  METHOD outcomes.
    SELECT order_id, block_key, crew_code, activity, planned_qty, actual_qty, qty_unit, status
      FROM zest_workord
      WHERE estate = @header-estate AND work_date = @header-plandate AND operation = @header-operation
      INTO TABLE @DATA(orders).

    LOOP AT lines INTO DATA(line) WHERE isassigned = abap_true.
      DATA(outcome) = VALUE ty_outcome( blocklabel = line-blocklabel
                                        crewcode   = line-crewcode
                                        activity   = line-activity
                                        plannedqty = line-quantity
                                        qtyunit    = line-qtyunit ).
      DATA(found) = abap_false.
      LOOP AT orders INTO DATA(order) WHERE block_key = line-blockkey.
        found = abap_true.
        outcome-actualqty = outcome-actualqty + order-actual_qty.
        outcome-orderids  = COND #( WHEN outcome-orderids IS INITIAL THEN order-order_id
                                    ELSE |{ outcome-orderids } { order-order_id }| ).
        outcome-outcomestatus = order-status.
      ENDLOOP.

      IF found = abap_false.
        outcome-outcomestatus = COND #( WHEN header-plandate >= cl_abap_context_info=>get_system_date( )
                                        THEN 'not yet due' ELSE 'not in ledger' ).
        outcome-criticality   = criticality-neutral.
      ELSE.
        outcome-adherencepct = COND #( WHEN outcome-plannedqty > 0
                                       THEN round( val = 100 * outcome-actualqty / outcome-plannedqty dec = 1 ) ).
        outcome-criticality  = COND #( WHEN outcome-adherencepct >= 90 THEN criticality-positive
                                       WHEN outcome-adherencepct >= 60 THEN criticality-critical
                                       ELSE criticality-negative ).
      ENDIF.
      APPEND outcome TO result.
    ENDLOOP.
  ENDMETHOD.


  METHOD overrides_to_json.
    CHECK overrides IS NOT INITIAL.
    result = /ui2/cl_json=>serialize( data = overrides compress = abap_true pretty_name = /ui2/cl_json=>pretty_mode-camel_case ).
  ENDMETHOD.


  METHOD overrides_from_json.
    CHECK json IS NOT INITIAL.
    /ui2/cl_json=>deserialize( EXPORTING json = json pretty_name = /ui2/cl_json=>pretty_mode-camel_case
                               CHANGING  data = result ).
  ENDMETHOD.

ENDCLASS.
