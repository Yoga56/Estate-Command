CLASS zcl_est_ai_test DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcl_est_ai_test IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.
    " One small call per active provider: proves arrangement, key and response parsing.
    SELECT * FROM zest_ai_prov WHERE is_active = @abap_true ORDER BY provider_id INTO TABLE @DATA(providers).

    LOOP AT providers INTO DATA(config).
      TRY.
          DATA(answer) = zcl_est_ai_factory=>create( config )->complete(
            system_prompt = `You are a concise assistant.`
            user_prompt   = `Reply with the single word OK.` ).
          out->write( |{ config-provider_id } ({ config-model_id }): { answer-text } | &&
                      |[{ answer-input_tokens } in / { answer-output_tokens } out]| ).
        CATCH zcx_est_ai INTO DATA(error).
          out->write( |{ config-provider_id }: FAILED - { error->get_text( ) }| ).
      ENDTRY.
    ENDLOOP.

    " the whole chain on the sample estate, outside RAP: data, scheduler, words, audit
    LOOP AT zcl_est_data=>operations( ) INTO DATA(operation).
      TRY.
          DATA(plan) = zcl_est_plan_builder=>build( estate = 'SMPL' operation = CONV #( operation ) ).
          out->write( |SMPL { operation } { plan-header-plandate DATE = ISO } [{ plan-header-status }]: | &&
                      |{ plan-header-blocksassigned } of { plan-header-blocksdue } due blocks, | &&
                      |gap to bound { plan-header-gappercent }%, audit { plan-header-auditchecked } checked, | &&
                      |unverified: { COND string( WHEN plan-header-auditunverified IS INITIAL THEN `none`
                                                  ELSE plan-header-auditunverified ) }| ).
          out->write( |  { plan-header-headline }| ).
          IF plan-header-errortext IS NOT INITIAL.
            out->write( |  AI: { plan-header-errortext }| ).
          ENDIF.
        CATCH zcx_est_ai INTO DATA(plan_error).
          out->write( |SMPL { operation }: FAILED - { plan_error->get_text( ) }| ).
      ENDTRY.
    ENDLOOP.

    LOOP AT zcl_est_stores=>overview( 'SMPL' ) INTO DATA(material).
      out->write( |Stores { material-material }: { material-headline } / { material-leadsentence }| ).
    ENDLOOP.

    DATA(fires) = zcl_est_firms=>around( 'SMPL' ).
    out->write( |Fires: { fires-status }| ).
    LOOP AT fires-hotspots INTO DATA(hotspot) TO 5.
      out->write( |  { hotspot-acq_date DATE = ISO } { hotspot-acq_time } UTC { hotspot-satellite } { hotspot-confidence }, | &&
                  |FRP { hotspot-frp } MW, { hotspot-distance_km } km from block { hotspot-nearest_block }| ).
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
