CLASS zcx_est_ai DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    DATA message TYPE string READ-ONLY.

    METHODS constructor
      IMPORTING
        message  TYPE string OPTIONAL
        previous LIKE previous OPTIONAL.

    METHODS if_message~get_text REDEFINITION.
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcx_est_ai IMPLEMENTATION.

  METHOD constructor.
    super->constructor( previous = previous ).
    me->message = message.
  ENDMETHOD.

  METHOD if_message~get_text.
    result = message.
  ENDMETHOD.

ENDCLASS.
