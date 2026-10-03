CLASS zcl_est_plan_job DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Application job: tomorrow's plans for every estate and operation, ready for the
    "! Assistant Manager in the morning. A plan whose AI step failed is still created
    "! (status F): its figures stand on their own.
    INTERFACES if_apj_dt_exec_object.
    INTERFACES if_apj_rt_exec_object.
  PROTECTED SECTION.
  PRIVATE SECTION.
    CONSTANTS estate_parameter TYPE c LENGTH 8 VALUE 'P_ESTATE'.
    CONSTANTS operation_parameter TYPE c LENGTH 8 VALUE 'P_OPER'.
ENDCLASS.



CLASS zcl_est_plan_job IMPLEMENTATION.

  METHOD if_apj_dt_exec_object~get_parameters.
    et_parameter_def = VALUE #(
      ( selname        = estate_parameter
        kind           = if_apj_dt_exec_object=>parameter
        datatype       = 'C'
        length         = 10
        param_text     = 'Estate (blank = every estate)'
        changeable_ind = abap_true )
      ( selname        = operation_parameter
        kind           = if_apj_dt_exec_object=>parameter
        datatype       = 'C'
        length         = 10
        param_text     = 'Operation (blank = harvest, prune, weed, spray)'
        changeable_ind = abap_true ) ).
  ENDMETHOD.


  METHOD if_apj_rt_exec_object~execute.
    DATA estates TYPE STANDARD TABLE OF zest_estate-estate WITH EMPTY KEY.

    estates = VALUE #( FOR parameter IN it_parameters
                       WHERE ( selname = estate_parameter AND low IS NOT INITIAL )
                       ( CONV #( to_upper( parameter-low ) ) ) ).
    IF estates IS INITIAL.
      SELECT estate FROM zest_estate ORDER BY estate INTO TABLE @estates.
    ENDIF.

    DATA(operations) = VALUE string_table( FOR parameter IN it_parameters
                                           WHERE ( selname = operation_parameter AND low IS NOT INITIAL )
                                           ( to_lower( CONV string( parameter-low ) ) ) ).
    IF operations IS INITIAL.
      operations = zcl_est_data=>operations( ).
    ENDIF.

    LOOP AT estates INTO DATA(estate).
      LOOP AT operations INTO DATA(operation).
        MODIFY ENTITIES OF zr_est_plan
          ENTITY plan
            EXECUTE GeneratePlan FROM VALUE #( ( %cid                = 'PLAN'
                                                 %param-Estate       = estate
                                                 %param-Operation    = operation ) )
          FAILED DATA(failed).
        COMMIT ENTITIES.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
