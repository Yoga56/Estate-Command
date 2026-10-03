CLASS zcl_est_audit DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! The guardrail is checked, not trusted (port of reasoning.audit_figures): every number
    "! and block label in a generated text is looked for in the evidence it was written from.
    "! What is not found is reported as unverified. A total the model worked out itself lands
    "! there too, which is the point: nothing in this system is allowed to compute.
    TYPES:
      BEGIN OF ty_result,
        checked    TYPE i,
        unverified TYPE string_table,
        clean      TYPE abap_bool,
      END OF ty_result.

    CLASS-METHODS audit
      IMPORTING answer        TYPE string
                evidence      TYPE string
                tolerance     TYPE decfloat34 DEFAULT '0.005'
      RETURNING VALUE(result) TYPE ty_result.

    "! The unverified tokens as one line, for a 255-character field
    CLASS-METHODS summary
      IMPORTING audit         TYPE ty_result
      RETURNING VALUE(result) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES ty_numbers TYPE SORTED TABLE OF decfloat34 WITH UNIQUE KEY table_line.

    CONSTANTS number_pattern TYPE string VALUE `-?\d[\d,]*(?:\.\d+)?`.
    "! a block label - 34-38 - is one token, not the numbers 34 and -38
    CONSTANTS label_pattern TYPE string VALUE `\b\d{1,3}-\d{1,3}\b`.
    "! "1. " / "12) " at the head of a line: an enumeration, not a measurement
    CONSTANTS list_marker TYPE string VALUE `^\s*\d{1,2}[.)]\s+`.

    CLASS-METHODS numbers_in
      IMPORTING text          TYPE string
      RETURNING VALUE(result) TYPE ty_numbers.

    CLASS-METHODS labels_in
      IMPORTING text          TYPE string
      RETURNING VALUE(result) TYPE string_table.

    CLASS-METHODS to_number
      IMPORTING token         TYPE string
      EXPORTING valid         TYPE abap_bool
      RETURNING VALUE(result) TYPE decfloat34.

    CLASS-METHODS matches
      IMPORTING value         TYPE decfloat34
                known         TYPE ty_numbers
                tolerance     TYPE decfloat34
      RETURNING VALUE(result) TYPE abap_bool.
ENDCLASS.



CLASS zcl_est_audit IMPLEMENTATION.

  METHOD audit.
    DATA seen TYPE string_table.
    DATA valid TYPE abap_bool.

    DATA(known) = numbers_in( evidence ).
    DATA(labels) = labels_in( evidence ).

    SPLIT answer AT |\n| INTO TABLE DATA(answer_lines).
    LOOP AT answer_lines INTO DATA(line).
      line = replace( val = line pcre = list_marker with = `` ).

      DATA(line_labels) = labels_in( line ).
      LOOP AT line_labels INTO DATA(label).
        CHECK NOT line_exists( seen[ table_line = label ] ).
        APPEND label TO seen.
        IF NOT line_exists( labels[ table_line = label ] ).
          APPEND label TO result-unverified.
        ENDIF.
      ENDLOOP.
      line = replace( val = line pcre = label_pattern with = ` ` occ = 0 ).

      FIND ALL OCCURRENCES OF PCRE number_pattern IN line RESULTS DATA(found).
      LOOP AT found INTO DATA(match).
        " "short by 50, and" ends on a comma that belongs to the sentence
        DATA(token) = substring( val = line off = match-offset len = match-length ).
        WHILE token IS NOT INITIAL AND ( substring( val = token off = strlen( token ) - 1 len = 1 ) = `,`
                                      OR substring( val = token off = strlen( token ) - 1 len = 1 ) = `.` ).
          token = substring( val = token len = strlen( token ) - 1 ).
        ENDWHILE.
        CHECK token IS NOT INITIAL AND NOT line_exists( seen[ table_line = token ] ).
        APPEND token TO seen.
        DATA(value) = to_number( EXPORTING token = token IMPORTING valid = valid ).
        IF valid = abap_false OR matches( value = value known = known tolerance = tolerance ) = abap_false.
          APPEND token TO result-unverified.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    result-checked = lines( seen ).
    result-clean   = xsdbool( result-unverified IS INITIAL ).
  ENDMETHOD.


  METHOD summary.
    result = concat_lines_of( table = audit-unverified sep = `, ` ).
    IF strlen( result ) > 255.
      result = |{ substring( val = result len = 250 ) } ...|.
    ENDIF.
  ENDMETHOD.


  METHOD numbers_in.
    DATA valid TYPE abap_bool.

    FIND ALL OCCURRENCES OF PCRE number_pattern IN text RESULTS DATA(found).
    LOOP AT found INTO DATA(match).
      DATA(value) = to_number( EXPORTING token = substring( val = text off = match-offset len = match-length )
                               IMPORTING valid = valid ).
      IF valid = abap_true.
        INSERT value INTO TABLE result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD labels_in.
    FIND ALL OCCURRENCES OF PCRE label_pattern IN text RESULTS DATA(found).
    LOOP AT found INTO DATA(match).
      DATA(label) = substring( val = text off = match-offset len = match-length ).
      IF NOT line_exists( result[ table_line = label ] ).
        APPEND label TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD to_number.
    valid = abap_false.
    DATA(digits) = replace( val = token sub = `,` with = `` occ = 0 ).
    IF digits IS INITIAL.
      RETURN.
    ENDIF.
    TRY.
        result = abs( CONV decfloat34( digits ) ).
        valid = abap_true.
      CATCH cx_sy_conversion_error.
        CLEAR result.
    ENDTRY.
  ENDMETHOD.


  METHOD matches.
    " numbers a sentence needs to be readable, that no tool would ever return
    IF line_exists( known[ table_line = value ] )
       OR value = 0 OR value = 1 OR value = 2 OR value = 3 OR value = 4 OR value = 5 OR value = 6
       OR value = 7 OR value = 8 OR value = 9 OR value = 10 OR value = 100 OR value = 1000.
      result = abap_true.
      RETURN.
    ENDIF.

    LOOP AT known INTO DATA(candidate) WHERE table_line <> 0.
      IF abs( value - candidate ) <= tolerance * candidate.
        result = abap_true.
        RETURN.
      ENDIF.
      " the model rounds when it writes prose: 0.6294 becomes 0.63, 2004.5 becomes 2005
      DO 4 TIMES.
        IF round( val = candidate dec = sy-index - 1 ) = value.
          result = abap_true.
          RETURN.
        ENDIF.
      ENDDO.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
