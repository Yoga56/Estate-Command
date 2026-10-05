CLASS lhc_assumption DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR assumption RESULT result.

    METHODS checkrange FOR VALIDATE ON SAVE
      IMPORTING keys FOR assumption~CheckRange.

    METHODS marksource FOR DETERMINE ON MODIFY
      IMPORTING keys FOR assumption~MarkSource.

    METHODS resettodefault FOR MODIFY
      IMPORTING keys FOR ACTION assumption~ResetToDefault RESULT result.
ENDCLASS.

CLASS lhc_assumption IMPLEMENTATION.

  METHOD get_global_authorizations.
  ENDMETHOD.


  METHOD checkrange.
    READ ENTITIES OF zr_est_assump IN LOCAL MODE
      ENTITY assumption
        FIELDS ( AssumptionLabel AssumptionValue MinValue MaxValue ValueUnit ) WITH CORRESPONDING #( keys )
      RESULT DATA(assumptions).

    LOOP AT assumptions INTO DATA(assumption).
      CHECK assumption-AssumptionValue < assumption-MinValue OR assumption-AssumptionValue > assumption-MaxValue.
      APPEND VALUE #( %tky = assumption-%tky ) TO failed-assumption.
      APPEND VALUE #( %tky = assumption-%tky
                      %element-AssumptionValue = if_abap_behv=>mk-on
                      %msg = new_message_with_text(
                               severity = if_abap_behv_message=>severity-error
                               text     = |{ assumption-AssumptionLabel }: between { assumption-MinValue } | &&
                                          |and { assumption-MaxValue } { assumption-ValueUnit }| ) )
        TO reported-assumption.
    ENDLOOP.
  ENDMETHOD.


  METHOD marksource.
    READ ENTITIES OF zr_est_assump IN LOCAL MODE
      ENTITY assumption
        FIELDS ( AssumptionValue DefaultValue ValueSource ) WITH CORRESPONDING #( keys )
      RESULT DATA(assumptions).

    DATA updates TYPE TABLE FOR UPDATE zr_est_assump.

    DATA(defaults) = zcl_est_assumptions=>defaults( ).
    LOOP AT assumptions INTO DATA(assumption).
      " back at the default it keeps the shipped source
      DATA(source) = zcl_est_assumptions=>source-assumed.
      READ TABLE defaults INTO DATA(shipped) WITH KEY assumption_key = assumption-AssumptionKey.
      IF sy-subrc = 0.
        source = shipped-value_source.
      ENDIF.
      IF assumption-AssumptionValue <> assumption-DefaultValue.
        source = zcl_est_assumptions=>source-client.
      ENDIF.
      APPEND VALUE #( %tky = assumption-%tky ValueSource = source ) TO updates.
    ENDLOOP.

    MODIFY ENTITIES OF zr_est_assump IN LOCAL MODE
      ENTITY assumption
        UPDATE FIELDS ( ValueSource ) WITH updates.
    zcl_est_assumptions=>clear_cache( ).
  ENDMETHOD.


  METHOD resettodefault.
    READ ENTITIES OF zr_est_assump IN LOCAL MODE
      ENTITY assumption
        FIELDS ( DefaultValue ) WITH CORRESPONDING #( keys )
      RESULT DATA(assumptions).

    MODIFY ENTITIES OF zr_est_assump IN LOCAL MODE
      ENTITY assumption
        UPDATE FIELDS ( AssumptionValue )
          WITH VALUE #( FOR assumption IN assumptions
                        ( %tky = assumption-%tky AssumptionValue = assumption-DefaultValue ) ).

    READ ENTITIES OF zr_est_assump IN LOCAL MODE
      ENTITY assumption
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(refreshed).
    result = VALUE #( FOR row IN refreshed ( %tky = row-%tky %param = row ) ).
  ENDMETHOD.

ENDCLASS.
