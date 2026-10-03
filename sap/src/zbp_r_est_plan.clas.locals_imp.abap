CLASS lhc_plan DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    TYPES ty_line_creates TYPE TABLE FOR CREATE zr_est_plan\_Lines.

    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR plan RESULT result.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR plan RESULT result.

    METHODS generateplan FOR MODIFY
      IMPORTING keys FOR ACTION plan~GeneratePlan RESULT result.

    METHODS handover FOR MODIFY
      IMPORTING keys FOR ACTION plan~Handover RESULT result.

    METHODS replan FOR MODIFY
      IMPORTING keys FOR ACTION plan~Replan RESULT result.

    METHODS refreshwords FOR MODIFY
      IMPORTING keys FOR ACTION plan~RefreshWords RESULT result.

    METHODS accept FOR MODIFY
      IMPORTING keys FOR ACTION plan~Accept RESULT result.

    METHODS reject FOR MODIFY
      IMPORTING keys FOR ACTION plan~Reject RESULT result.

    METHODS defer FOR MODIFY
      IMPORTING keys FOR ACTION plan~Defer RESULT result.

    METHODS draftartifact FOR MODIFY
      IMPORTING keys FOR ACTION plan~DraftArtifact RESULT result.

    METHODS ask FOR MODIFY
      IMPORTING keys FOR ACTION plan~Ask RESULT result.

    METHODS outcomes FOR MODIFY
      IMPORTING keys FOR ACTION plan~Outcomes RESULT result.

    METHODS line_targets
      IMPORTING lines         TYPE zcl_est_plan_builder=>ty_lines
      RETURNING VALUE(result) TYPE ty_line_creates.

ENDCLASS.

CLASS lhc_plan IMPLEMENTATION.

  METHOD get_global_authorizations.
  ENDMETHOD.


  METHOD get_instance_features.
    READ ENTITIES OF zr_est_plan IN LOCAL MODE
      ENTITY plan
        FIELDS ( Status ) WITH CORRESPONDING #( keys )
      RESULT DATA(plans).

    " a plan can be decided, or planned again, until it is accepted or rejected
    LOOP AT plans INTO DATA(plan).
      APPEND VALUE #( %tky = plan-%tky ) TO result ASSIGNING FIELD-SYMBOL(<features>).
      IF plan-Status = zcl_est_plan_builder=>status-accepted OR plan-Status = zcl_est_plan_builder=>status-rejected.
        <features>-%action-Accept = if_abap_behv=>fc-o-disabled.
        <features>-%action-Reject = if_abap_behv=>fc-o-disabled.
        <features>-%action-Defer  = if_abap_behv=>fc-o-disabled.
        <features>-%action-Replan = if_abap_behv=>fc-o-disabled.
      ELSE.
        <features>-%action-Accept = if_abap_behv=>fc-o-enabled.
        <features>-%action-Reject = if_abap_behv=>fc-o-enabled.
        <features>-%action-Defer  = if_abap_behv=>fc-o-enabled.
        <features>-%action-Replan = if_abap_behv=>fc-o-enabled.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD line_targets.
    CHECK lines IS NOT INITIAL.

    APPEND INITIAL LINE TO result ASSIGNING FIELD-SYMBOL(<parent>).
    LOOP AT lines INTO DATA(line).
      APPEND CORRESPONDING #( line ) TO <parent>-%target ASSIGNING FIELD-SYMBOL(<target>).
      <target>-%cid = |LINE{ sy-tabix }|.
    ENDLOOP.
  ENDMETHOD.


  METHOD generateplan.
    DATA headers TYPE TABLE FOR CREATE zr_est_plan.

    LOOP AT keys INTO DATA(key).
      TRY.
          DATA(plan) = zcl_est_plan_builder=>build( estate      = key-%param-Estate
                                                    operation   = key-%param-Operation
                                                    plan_date   = key-%param-PlanDate
                                                    provider_id = key-%param-ProviderId ).
        CATCH zcx_est_ai INTO DATA(error).
          APPEND VALUE #( %cid = key-%cid ) TO failed-plan.
          APPEND VALUE #( %cid = key-%cid
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                        text     = error->get_text( ) ) ) TO reported-plan.
          CONTINUE.
      ENDTRY.

      headers = VALUE #( ( CORRESPONDING #( plan-header ) ) ).
      headers[ 1 ]-%cid = 'PLAN'.
      DATA(lines) = line_targets( plan-lines ).
      LOOP AT lines ASSIGNING FIELD-SYMBOL(<lines>).
        <lines>-%cid_ref = 'PLAN'.
      ENDLOOP.

      MODIFY ENTITIES OF zr_est_plan IN LOCAL MODE
        ENTITY plan
          CREATE SET FIELDS WITH headers
          CREATE BY \_Lines SET FIELDS WITH lines
        MAPPED DATA(created)
        FAILED DATA(create_failed).

      IF create_failed IS NOT INITIAL OR created-plan IS INITIAL.
        APPEND VALUE #( %cid = key-%cid ) TO failed-plan.
        APPEND VALUE #( %cid = key-%cid
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                      text     = `The plan could not be saved` ) ) TO reported-plan.
        CONTINUE.
      ENDIF.

      READ ENTITIES OF zr_est_plan IN LOCAL MODE
        ENTITY plan
          ALL FIELDS WITH VALUE #( ( %tky = created-plan[ 1 ]-%tky ) )
        RESULT DATA(plans).
      APPEND VALUE #( %cid = key-%cid %param = plans[ 1 ] ) TO result.

      IF plan-header-status = zcl_est_plan_builder=>status-figures_only.
        APPEND VALUE #( %cid = key-%cid
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-information
                                                      text     = |Figures only: { plan-header-errortext }| ) )
          TO reported-plan.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD replan.
    DATA updates TYPE TABLE FOR UPDATE zr_est_plan.

    READ ENTITIES OF zr_est_plan IN LOCAL MODE
      ENTITY plan
        ALL FIELDS WITH CORRESPONDING #( keys )
        RESULT DATA(plans)
      ENTITY plan BY \_Lines
        FIELDS ( LineUuid ) WITH CORRESPONDING #( keys )
        RESULT DATA(old_lines).

    LOOP AT plans INTO DATA(current).
      DATA(param) = keys[ %tky = current-%tky ]-%param.

      " changes add up: a second replan keeps the first one's crew out unless cleared
      DATA(overrides) = COND zcl_est_scheduler=>ty_overrides(
        WHEN param-ClearChanges = abap_true THEN VALUE #( )
        ELSE zcl_est_plan_builder=>overrides_from_json( current-Overrides ) ).
      IF param-CrewOut IS NOT INITIAL.
        overrides-crew_out = to_upper( param-CrewOut ).
      ENDIF.
      IF param-CrewCode IS NOT INITIAL.
        overrides-crew_code   = to_upper( param-CrewCode ).
        overrides-present     = param-CrewPresent.
        overrides-present_set = abap_true.
      ENDIF.
      IF param-BlockHeld IS NOT INITIAL.
        overrides-block_held = param-BlockHeld.
      ENDIF.
      TRY.
          IF param-RainMm IS NOT INITIAL.
            overrides-rain_mm  = CONV decfloat34( condense( param-RainMm ) ).
            overrides-rain_set = abap_true.
          ENDIF.
          IF param-ContiguityPct IS NOT INITIAL.
            overrides-contiguity_pct = CONV decfloat34( condense( param-ContiguityPct ) ).
            overrides-contiguity_set = abap_true.
          ENDIF.
        CATCH cx_sy_conversion_error.
          APPEND VALUE #( %tky = current-%tky ) TO failed-plan.
          APPEND VALUE #( %tky = current-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                        text     = `Rain and contiguity are numbers, for example 12.5` ) )
            TO reported-plan.
          CONTINUE.
      ENDTRY.

      TRY.
          DATA(plan) = zcl_est_plan_builder=>build(
            estate      = current-Estate
            operation   = current-Operation
            plan_date   = current-PlanDate
            overrides   = overrides
            provider_id = COND #( WHEN param-ProviderId IS NOT INITIAL THEN param-ProviderId
                                  ELSE current-ProviderId ) ).
        CATCH zcx_est_ai INTO DATA(error).
          APPEND VALUE #( %tky = current-%tky ) TO failed-plan.
          APPEND VALUE #( %tky = current-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                        text     = error->get_text( ) ) ) TO reported-plan.
          CONTINUE.
      ENDTRY.

      updates = VALUE #( ( CORRESPONDING #( plan-header ) ) ).
      updates[ 1 ]-%tky = current-%tky.
      DATA(lines) = line_targets( plan-lines ).
      LOOP AT lines ASSIGNING FIELD-SYMBOL(<lines>).
        <lines>-%tky = current-%tky.
      ENDLOOP.

      MODIFY ENTITIES OF zr_est_plan IN LOCAL MODE
        ENTITY line
          DELETE FROM VALUE #( FOR old IN old_lines WHERE ( PlanUuid = current-PlanUuid ) ( %tky = old-%tky ) )
        ENTITY plan
          UPDATE FIELDS ( Status StatusCriticality Crews Present CapacityMd BlocksDue ManDaysDue BlocksAssigned
                          ManDaysAssigned DeferralDue ValueRecovered UpperBound GapPercent ContiguityCost
                          ContiguityPercent Swaps RainMm RainProbability WeatherSource StopsWork StopReason
                          Overrides Headline Summary WhyText AuditChecked AuditUnverified AuditCriticality
                          ProviderId ModelId InputTokens OutputTokens ErrorText Prompt RawResponse
                          DecidedBy DecidedAt DecisionNote DueDate ExpectedEffect ArtifactText )
            WITH updates
          CREATE BY \_Lines SET FIELDS WITH lines
        FAILED DATA(update_failed).

      IF update_failed IS NOT INITIAL.
        APPEND VALUE #( %tky = current-%tky ) TO failed-plan.
        APPEND VALUE #( %tky = current-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                      text     = `The new plan could not be saved` ) ) TO reported-plan.
      ENDIF.
    ENDLOOP.

    READ ENTITIES OF zr_est_plan IN LOCAL MODE
      ENTITY plan
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(refreshed).
    result = VALUE #( FOR row IN refreshed ( %tky = row-%tky %param = row ) ).
  ENDMETHOD.


  METHOD refreshwords.
    DATA updates TYPE TABLE FOR UPDATE zr_est_plan.

    READ ENTITIES OF zr_est_plan IN LOCAL MODE
      ENTITY plan
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(plans).

    LOOP AT plans INTO DATA(current).
      DATA(header) = zcl_est_plan_builder=>refresh_words(
        header      = CORRESPONDING #( current )
        provider_id = VALUE #( keys[ %tky = current-%tky ]-%param-ProviderId OPTIONAL ) ).

      " a decided plan keeps its decision; only the words change
      IF current-Status = zcl_est_plan_builder=>status-accepted
         OR current-Status = zcl_est_plan_builder=>status-rejected
         OR current-Status = zcl_est_plan_builder=>status-deferred.
        header-status            = current-Status.
        header-statuscriticality = current-StatusCriticality.
      ENDIF.

      updates = VALUE #( ( CORRESPONDING #( header ) ) ).
      updates[ 1 ]-%tky = current-%tky.
      MODIFY ENTITIES OF zr_est_plan IN LOCAL MODE
        ENTITY plan
          UPDATE FIELDS ( Status StatusCriticality Headline Summary WhyText AuditChecked AuditUnverified
                          AuditCriticality ProviderId ModelId InputTokens OutputTokens ErrorText RawResponse )
            WITH updates.

      IF header-errortext IS NOT INITIAL.
        APPEND VALUE #( %tky = current-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-information
                                                      text     = CONV #( header-errortext ) ) ) TO reported-plan.
      ENDIF.
    ENDLOOP.

    READ ENTITIES OF zr_est_plan IN LOCAL MODE
      ENTITY plan
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(refreshed).
    result = VALUE #( FOR row IN refreshed ( %tky = row-%tky %param = row ) ).
  ENDMETHOD.


  METHOD accept.
    GET TIME STAMP FIELD DATA(now).
    DATA(user) = cl_abap_context_info=>get_user_technical_name( ).

    MODIFY ENTITIES OF zr_est_plan IN LOCAL MODE
      ENTITY plan
        UPDATE FIELDS ( Status StatusCriticality DecidedBy DecidedAt DecisionNote DueDate ExpectedEffect )
          WITH VALUE #( FOR key IN keys
                        ( %tky              = key-%tky
                          Status            = zcl_est_plan_builder=>status-accepted
                          StatusCriticality = zcl_est_plan_builder=>criticality-positive
                          DecidedBy         = user
                          DecidedAt         = now
                          DecisionNote      = key-%param-DecisionNote
                          DueDate           = key-%param-DueDate
                          ExpectedEffect    = key-%param-ExpectedEffect ) )
      FAILED DATA(update_failed).
    failed-plan = CORRESPONDING #( update_failed-plan ).

    READ ENTITIES OF zr_est_plan IN LOCAL MODE
      ENTITY plan
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(refreshed).
    result = VALUE #( FOR row IN refreshed ( %tky = row-%tky %param = row ) ).
  ENDMETHOD.


  METHOD reject.
    GET TIME STAMP FIELD DATA(now).
    DATA(user) = cl_abap_context_info=>get_user_technical_name( ).

    MODIFY ENTITIES OF zr_est_plan IN LOCAL MODE
      ENTITY plan
        UPDATE FIELDS ( Status StatusCriticality DecidedBy DecidedAt DecisionNote DueDate ExpectedEffect )
          WITH VALUE #( FOR key IN keys
                        ( %tky              = key-%tky
                          Status            = zcl_est_plan_builder=>status-rejected
                          StatusCriticality = zcl_est_plan_builder=>criticality-negative
                          DecidedBy         = user
                          DecidedAt         = now
                          DecisionNote      = key-%param-DecisionNote
                          DueDate           = key-%param-DueDate
                          ExpectedEffect    = key-%param-ExpectedEffect ) )
      FAILED DATA(update_failed).
    failed-plan = CORRESPONDING #( update_failed-plan ).

    READ ENTITIES OF zr_est_plan IN LOCAL MODE
      ENTITY plan
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(refreshed).
    result = VALUE #( FOR row IN refreshed ( %tky = row-%tky %param = row ) ).
  ENDMETHOD.


  METHOD defer.
    GET TIME STAMP FIELD DATA(now).
    DATA(user) = cl_abap_context_info=>get_user_technical_name( ).

    READ ENTITIES OF zr_est_plan IN LOCAL MODE
      ENTITY plan
        FIELDS ( PlanDate ) WITH CORRESPONDING #( keys )
      RESULT DATA(plans).

    " a deferral is the entry with a clock on it: without a date it comes back the next day
    MODIFY ENTITIES OF zr_est_plan IN LOCAL MODE
      ENTITY plan
        UPDATE FIELDS ( Status StatusCriticality DecidedBy DecidedAt DecisionNote DueDate ExpectedEffect )
          WITH VALUE #( FOR plan IN plans
                        LET param = keys[ %tky = plan-%tky ]-%param IN
                        ( %tky              = plan-%tky
                          Status            = zcl_est_plan_builder=>status-deferred
                          StatusCriticality = zcl_est_plan_builder=>criticality-critical
                          DecidedBy         = user
                          DecidedAt         = now
                          DecisionNote      = param-DecisionNote
                          DueDate           = COND #( WHEN param-DueDate IS NOT INITIAL THEN param-DueDate
                                                      ELSE plan-PlanDate + 1 )
                          ExpectedEffect    = param-ExpectedEffect ) )
      FAILED DATA(update_failed).
    failed-plan = CORRESPONDING #( update_failed-plan ).

    READ ENTITIES OF zr_est_plan IN LOCAL MODE
      ENTITY plan
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(refreshed).
    result = VALUE #( FOR row IN refreshed ( %tky = row-%tky %param = row ) ).
  ENDMETHOD.


  METHOD draftartifact.
    READ ENTITIES OF zr_est_plan IN LOCAL MODE
      ENTITY plan
        ALL FIELDS WITH CORRESPONDING #( keys )
        RESULT DATA(plans)
      ENTITY plan BY \_Lines
        ALL FIELDS WITH CORRESPONDING #( keys )
        RESULT DATA(lines).
    SORT lines BY LineNo.

    LOOP AT plans INTO DATA(current).
      DATA(text) = zcl_est_plan_builder=>draft_artifact(
        header = CORRESPONDING #( current )
        lines  = VALUE #( FOR line IN lines WHERE ( PlanUuid = current-PlanUuid ) ( CORRESPONDING #( line ) ) ) ).

      MODIFY ENTITIES OF zr_est_plan IN LOCAL MODE
        ENTITY plan
          UPDATE FIELDS ( ArtifactText ) WITH VALUE #( ( %tky = current-%tky ArtifactText = text ) ).
    ENDLOOP.

    READ ENTITIES OF zr_est_plan IN LOCAL MODE
      ENTITY plan
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(refreshed).
    result = VALUE #( FOR row IN refreshed ( %tky = row-%tky %param = row ) ).
  ENDMETHOD.


  METHOD ask.
    READ ENTITIES OF zr_est_plan IN LOCAL MODE
      ENTITY plan
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(plans).

    LOOP AT keys INTO DATA(key).
      DATA(current) = VALUE #( plans[ %tky = key-%tky ] OPTIONAL ).
      CHECK current IS NOT INITIAL.

      TRY.
          DATA(answer) = zcl_est_plan_builder=>ask( header   = CORRESPONDING #( current )
                                                    question = CONV #( key-%param-Question ) ).
          APPEND VALUE #( %tky = key-%tky %param = CORRESPONDING #( answer ) ) TO result.
        CATCH zcx_est_ai INTO DATA(error).
          APPEND VALUE #( %tky = key-%tky ) TO failed-plan.
          APPEND VALUE #( %tky = key-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                        text     = error->get_text( ) ) ) TO reported-plan.
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.


  METHOD handover.
    LOOP AT keys INTO DATA(key).
      TRY.
          DATA(note) = zcl_est_plan_builder=>handover( key-%param-Estate ).
          APPEND VALUE #( %cid = key-%cid %param = CORRESPONDING #( note ) ) TO result.
        CATCH zcx_est_ai INTO DATA(error).
          APPEND VALUE #( %cid = key-%cid ) TO failed-plan.
          APPEND VALUE #( %cid = key-%cid
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                        text     = error->get_text( ) ) ) TO reported-plan.
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.


  METHOD outcomes.
    READ ENTITIES OF zr_est_plan IN LOCAL MODE
      ENTITY plan
        ALL FIELDS WITH CORRESPONDING #( keys )
        RESULT DATA(plans)
      ENTITY plan BY \_Lines
        ALL FIELDS WITH CORRESPONDING #( keys )
        RESULT DATA(lines).

    LOOP AT plans INTO DATA(current).
      LOOP AT zcl_est_plan_builder=>outcomes(
                header = CORRESPONDING #( current )
                lines  = VALUE #( FOR line IN lines WHERE ( PlanUuid = current-PlanUuid ) ( CORRESPONDING #( line ) ) ) )
           INTO DATA(outcome).
        APPEND VALUE #( %tky = current-%tky %param = CORRESPONDING #( outcome ) ) TO result.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
