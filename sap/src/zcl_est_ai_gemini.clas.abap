CLASS zcl_est_ai_gemini DEFINITION
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
    " Response of POST /v1beta/interactions
    TYPES:
      BEGIN OF ty_content,
        type TYPE string,
        text TYPE string,
      END OF ty_content,
      BEGIN OF ty_step,
        type    TYPE string,
        content TYPE STANDARD TABLE OF ty_content WITH EMPTY KEY,
      END OF ty_step,
      BEGIN OF ty_usage,
        total_input_tokens  TYPE i,
        total_output_tokens TYPE i,
      END OF ty_usage,
      BEGIN OF ty_response,
        status TYPE string,
        steps  TYPE STANDARD TABLE OF ty_step WITH EMPTY KEY,
        usage  TYPE ty_usage,
      END OF ty_response.

    DATA config TYPE zcl_est_ai_http=>ty_config.
ENDCLASS.



CLASS zcl_est_ai_gemini IMPLEMENTATION.

  METHOD constructor.
    me->config = config.
  ENDMETHOD.


  METHOD zif_est_ai_provider~complete.
    DATA response TYPE ty_response.

    " Instructions and data go into one input; store=false keeps the estate data
    " out of server-side interaction history.
    DATA(input) = zcl_est_ai_http=>escape_json( |{ system_prompt }\n\n{ user_prompt }| ).
    DATA(body) = |\{"model":"{ config-model_id }","store":false,"input":"{ input }"|.
    IF json_schema IS NOT INITIAL.
      body = |{ body },"response_format":\{"type":"text","mime_type":"application/json","schema":{ json_schema }\}|.
    ENDIF.
    body = |{ body }\}|.

    DATA(headers) = VALUE zcl_est_ai_http=>ty_headers(
      ( name = 'x-goog-api-key' value = zcl_est_ai_http=>get_api_key( config ) ) ).
    IF config-api_revision IS NOT INITIAL.
      APPEND VALUE #( name = 'Api-Revision' value = config-api_revision ) TO headers.
    ENDIF.

    result-raw = zcl_est_ai_http=>post( config  = config
                                         path    = CONV #( config-api_path )
                                         headers = headers
                                         body    = body ).

    /ui2/cl_json=>deserialize( EXPORTING json = result-raw CHANGING data = response ).

    LOOP AT response-steps INTO DATA(step) WHERE type = 'model_output'.
      LOOP AT step-content INTO DATA(content) WHERE type = 'text'.
        result-text = result-text && content-text.
      ENDLOOP.
    ENDLOOP.
    result-input_tokens  = response-usage-total_input_tokens.
    result-output_tokens = response-usage-total_output_tokens.

    IF result-text IS INITIAL.
      RAISE EXCEPTION NEW zcx_est_ai(
        message = |{ config-provider_id }: no model output (status { response-status })| ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
