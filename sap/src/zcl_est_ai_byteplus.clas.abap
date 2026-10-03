CLASS zcl_est_ai_byteplus DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_est_ai_provider.

    METHODS constructor
      IMPORTING
        config TYPE zcl_est_ai_http=>ty_config.

  PROTECTED SECTION.
  PRIVATE SECTION.
    " Response of POST /api/v3/chat/completions (BytePlus ModelArk, OpenAI-compatible)
    TYPES:
      BEGIN OF ty_message,
        role    TYPE string,
        content TYPE string,
      END OF ty_message,
      BEGIN OF ty_choice,
        message       TYPE ty_message,
        finish_reason TYPE string,
      END OF ty_choice,
      BEGIN OF ty_usage,
        prompt_tokens     TYPE i,
        completion_tokens TYPE i,
      END OF ty_usage,
      BEGIN OF ty_response,
        choices TYPE STANDARD TABLE OF ty_choice WITH EMPTY KEY,
        usage   TYPE ty_usage,
      END OF ty_response.

    DATA config TYPE zcl_est_ai_http=>ty_config.
ENDCLASS.



CLASS zcl_est_ai_byteplus IMPLEMENTATION.

  METHOD constructor.
    me->config = config.
  ENDMETHOD.


  METHOD zif_est_ai_provider~complete.
    DATA response TYPE ty_response.

    " not every ModelArk model takes a response format, so the schema travels in the system prompt
    DATA(instructions) = system_prompt.
    IF json_schema IS NOT INITIAL.
      instructions = |{ instructions }\nAnswer with one JSON object only, no markdown, following this JSON schema:\n{ json_schema }|.
    ENDIF.

    DATA(max_tokens) = COND i( WHEN config-max_tokens > 0 THEN config-max_tokens ELSE 2000 ).
    DATA(body) =
      |\{"model":"{ config-model_id }",| &&
      |"messages":[\{"role":"system","content":"{ zcl_est_ai_http=>escape_json( instructions ) }"\},| &&
      |\{"role":"user","content":"{ zcl_est_ai_http=>escape_json( user_prompt ) }"\}],| &&
      |"max_tokens":{ max_tokens },"temperature":{ config-temperature }\}|.

    result-raw = zcl_est_ai_http=>post(
      config  = config
      path    = CONV #( config-api_path )
      headers = VALUE #( ( name = 'Authorization' value = |Bearer { zcl_est_ai_http=>get_api_key( config ) }| ) )
      body    = body ).

    /ui2/cl_json=>deserialize( EXPORTING json = result-raw CHANGING data = response ).

    LOOP AT response-choices INTO DATA(choice).
      result-text = result-text && choice-message-content.
    ENDLOOP.
    result-input_tokens  = response-usage-prompt_tokens.
    result-output_tokens = response-usage-completion_tokens.

    IF result-text IS INITIAL.
      RAISE EXCEPTION NEW zcx_est_ai(
        message = |{ config-provider_id }: no model output ({ substring( val = result-raw len = nmin( val1 = strlen( result-raw ) val2 = 200 ) ) })| ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
