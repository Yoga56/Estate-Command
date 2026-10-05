CLASS zcl_est_ai_factory DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS:
      BEGIN OF provider_type,
        gemini  TYPE zest_ai_prov-provider_type VALUE 'GEMINI',
        bedrock  TYPE zest_ai_prov-provider_type VALUE 'BEDROCK',
        byteplus TYPE zest_ai_prov-provider_type VALUE 'BYTEPLUS',
      END OF provider_type.

    TYPES ty_configs TYPE STANDARD TABLE OF zcl_est_ai_http=>ty_config WITH EMPTY KEY.

    "! @parameter provider_id | blank = the active provider flagged as default
    CLASS-METHODS get_config
      IMPORTING
        provider_id   TYPE zest_ai_prov-provider_id OPTIONAL
      RETURNING
        VALUE(result) TYPE zcl_est_ai_http=>ty_config
      RAISING
        zcx_est_ai.

    "! The requested (or default) provider first, then every other active provider by
    "! fallback order, so a caller can move on when a model is overloaded.
    CLASS-METHODS get_candidates
      IMPORTING
        provider_id   TYPE zest_ai_prov-provider_id OPTIONAL
      RETURNING
        VALUE(result) TYPE ty_configs
      RAISING
        zcx_est_ai.

    CLASS-METHODS create
      IMPORTING
        config        TYPE zcl_est_ai_http=>ty_config
      RETURNING
        VALUE(result) TYPE REF TO zif_est_ai_provider
      RAISING
        zcx_est_ai.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcl_est_ai_factory IMPLEMENTATION.

  METHOD get_config.
    IF provider_id IS NOT INITIAL.
      SELECT SINGLE * FROM zest_ai_prov
        WHERE provider_id = @provider_id AND is_active = @abap_true
        INTO @result.
    ELSE.
      SELECT * FROM zest_ai_prov
        WHERE is_active = @abap_true AND is_default = @abap_true
        ORDER BY priority, provider_id
        INTO @result UP TO 1 ROWS.
      ENDSELECT.
    ENDIF.

    IF result IS INITIAL.
      RAISE EXCEPTION NEW zcx_est_ai(
        message = COND #( WHEN provider_id IS INITIAL
                          THEN |No active default AI provider configured|
                          ELSE |AI provider { provider_id } is not configured or not active| ) ).
    ENDIF.
  ENDMETHOD.


  METHOD get_candidates.
    DATA(first) = get_config( provider_id ).

    SELECT * FROM zest_ai_prov
      WHERE is_active = @abap_true AND provider_id <> @first-provider_id
      ORDER BY is_default DESCENDING, priority, provider_id
      INTO TABLE @result.
    INSERT first INTO result INDEX 1.
  ENDMETHOD.


  METHOD create.
    CASE config-provider_type.
      WHEN provider_type-gemini.
        result = NEW zcl_est_ai_gemini( config ).
      WHEN provider_type-bedrock.
        result = NEW zcl_est_ai_bedrock( config ).
      WHEN provider_type-byteplus.
        result = NEW zcl_est_ai_byteplus( config ).
      WHEN OTHERS.
        RAISE EXCEPTION NEW zcx_est_ai(
          message = |Provider type { config-provider_type } is not supported| ).
    ENDCASE.
  ENDMETHOD.

ENDCLASS.
