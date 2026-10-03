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
                               text     = |{ assumption-AssumptionLabel }: between | &&
                                          |{ zcl_est_data=>num( CONV #( assumption-MinValue ) ) } and | &&
                                          |{ zcl_est_data=>num( CONV #( assumption-MaxValue ) ) } { assumption-ValueUnit }| ) )
        TO reported-assumption.
    ENDLOOP.
  ENDMETHOD.


  METHOD marksource.
    READ ENTITIES OF zr_est_assump IN LOCAL MODE
      ENTITY assumption
        FIELDS ( AssumptionValue DefaultValue ValueSource ) WITH CORRESPONDING #( keys )
      RESULT DATA(assumptions).

    DATA(defaults) = zcl_est_assumptions=>defaults( ).
    MODIFY ENTITIES OF zr_est_assump IN LOCAL MODE
      ENTITY assumption
        UPDATE FIELDS ( ValueSource )
          WITH VALUE #( FOR assumption IN assumptions
                        ( %tky        = assumption-%tky
                          ValueSource = COND #(
                            WHEN assumption-AssumptionValue <> assumption-DefaultValue
                            THEN zcl_est_assumptions=>source-client
                            ELSE VALUE #( defaults[ assumption_key = assumption-AssumptionKey ]-value_source
                                          DEFAULT zcl_est_assumptions=>source-assumed ) ) ) ).
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
