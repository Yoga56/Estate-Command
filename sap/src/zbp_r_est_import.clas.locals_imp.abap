CLASS lhc_import DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    CONSTANTS:
      BEGIN OF status,
        uploaded TYPE zest_import-status VALUE 'U',
        loaded   TYPE zest_import-status VALUE 'L',
        error    TYPE zest_import-status VALUE 'E',
      END OF status.

    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR import RESULT result.

    METHODS load FOR MODIFY
      IMPORTING keys FOR ACTION import~Load RESULT result.
ENDCLASS.

CLASS lhc_import IMPLEMENTATION.

  METHOD get_global_authorizations.
  ENDMETHOD.


  METHOD load.
    READ ENTITIES OF zr_est_import IN LOCAL MODE
      ENTITY import
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(imports).

    LOOP AT imports INTO DATA(import).
      " the parsed rows are written in the save phase, which a draft never reaches
      IF import-%is_draft = if_abap_behv=>mk-on.
        APPEND VALUE #( %tky = import-%tky ) TO failed-import.
        APPEND VALUE #( %tky = import-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                      text     = `Save the import first, then load it` ) )
          TO reported-import.
        CONTINUE.
      ENDIF.
      TRY.
          IF import-Attachment IS INITIAL.
            RAISE EXCEPTION NEW zcx_est_ai( message = `Upload a file first` ).
          ENDIF.
          " parsed now, written in the save phase together with the status
          DATA(batch) = zcl_est_import=>parse( data_kind = import-DataKind
                                               estate    = import-Estate
                                               content   = import-Attachment ).
          zcl_est_import=>queue( batch ).

          MODIFY ENTITIES OF zr_est_import IN LOCAL MODE
            ENTITY import
              UPDATE FIELDS ( Status StatusCriticality RowsLoaded Message )
                WITH VALUE #( ( %tky              = import-%tky
                                Status            = status-loaded
                                StatusCriticality = 3
                                RowsLoaded        = batch-rows
                                Message           = |{ batch-rows } { to_lower( batch-kind ) } rows replace the earlier | &&
                                                    |rows of estate { batch-estate }| ) ).

        CATCH zcx_est_ai INTO DATA(error).
          MODIFY ENTITIES OF zr_est_import IN LOCAL MODE
            ENTITY import
              UPDATE FIELDS ( Status StatusCriticality RowsLoaded Message )
                WITH VALUE #( ( %tky              = import-%tky
                                Status            = status-error
                                StatusCriticality = 1
                                RowsLoaded        = 0
                                Message           = error->get_text( ) ) ).
          APPEND VALUE #( %tky = import-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                        text     = error->get_text( ) ) ) TO reported-import.
      ENDTRY.
    ENDLOOP.

    READ ENTITIES OF zr_est_import IN LOCAL MODE
      ENTITY import
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(refreshed).
    result = VALUE #( FOR row IN refreshed ( %tky = row-%tky %param = row ) ).
  ENDMETHOD.

ENDCLASS.


CLASS lsc_zr_est_import DEFINITION INHERITING FROM cl_abap_behavior_saver.
  PROTECTED SECTION.
    METHODS save_modified REDEFINITION.
    METHODS cleanup_finalize REDEFINITION.
ENDCLASS.

CLASS lsc_zr_est_import IMPLEMENTATION.

  METHOD save_modified.
    zcl_est_import=>flush( ).
    zcl_est_assumptions=>clear_cache( ).
  ENDMETHOD.


  METHOD cleanup_finalize.
    zcl_est_import=>clear_queue( ).
  ENDMETHOD.

ENDCLASS.
