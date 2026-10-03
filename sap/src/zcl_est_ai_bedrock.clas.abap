CLASS zcl_est_ai_bedrock DEFINITION
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
    " Response of POST /model/{modelId}/converse (camelCase in JSON)
    TYPES:
      BEGIN OF ty_content,
        text TYPE string,
      END OF ty_content,
      BEGIN OF ty_message,
        role    TYPE string,
        content TYPE STANDARD TABLE OF ty_content WITH EMPTY KEY,
      END OF ty_message,
      BEGIN OF ty_output,
        message TYPE ty_message,
      END OF ty_output,
      BEGIN OF ty_usage,
        input_tokens  TYPE i,
        output_tokens TYPE i,
      END OF ty_usage,
      BEGIN OF ty_response,
        output      TYPE ty_output,
        stop_reason TYPE string,
        usage       TYPE ty_usage,
      END OF ty_response.

    DATA config TYPE zcl_est_ai_http=>ty_config.
ENDCLASS.



CLASS zcl_est_ai_bedrock IMPLEMENTATION.

  METHOD constructor.
    me->config = config.
  ENDMETHOD.


  METHOD zif_est_ai_provider~complete.
    DATA response TYPE ty_response.

    " Converse has no schema parameter for Nova, so the schema travels in the system prompt.
    DATA(instructions) = system_prompt.
    IF json_schema IS NOT INITIAL.
      instructions = |{ instructions }\nAnswer with one JSON object only, no markdown, following this JSON schema:\n{ json_schema }|.
    ENDIF.

    DATA(max_tokens) = COND i( WHEN config-max_tokens > 0 THEN config-max_tokens ELSE 2000 ).
    DATA(body) =
      |\{"system":[\{"text":"{ zcl_est_ai_http=>escape_json( instructions ) }"\}],| &&
      |"messages":[\{"role":"user","content":[\{"text":"{ zcl_est_ai_http=>escape_json( user_prompt ) }"\}]\}],| &&
      |"inferenceConfig":\{"maxTokens":{ max_tokens },"temperature":{ config-temperature }\}\}|.

    DATA(path) = replace( val = CONV string( config-api_path ) sub = '{model}' with = config-model_id ).

    result-raw = zcl_est_ai_http=>post(
      config  = config
      path    = path
      headers = VALUE #( ( name = 'Authorization' value = |Bearer { zcl_est_ai_http=>get_api_key( config ) }| ) )
      body    = body ).

    /ui2/cl_json=>deserialize( EXPORTING json        = result-raw
                                         pretty_name = /ui2/cl_json=>pretty_mode-camel_case
                               CHANGING  data        = response ).

    LOOP AT response-output-message-content INTO DATA(content).
      result-text = result-text && content-text.
    ENDLOOP.
    result-input_tokens  = response-usage-input_tokens.
    result-output_tokens = response-usage-output_tokens.

    IF result-text IS INITIAL.
      RAISE EXCEPTION NEW zcx_est_ai(
        message = |{ config-provider_id }: no model output (stop reason { response-stop_reason })| ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
