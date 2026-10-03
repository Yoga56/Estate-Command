CLASS zcl_est_stores_query DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Query provider of the custom entity ZI_EST_STORES: computes the stores answer per
    "! estate on read. Filter on Estate to read one estate; without it every estate is read.
    INTERFACES if_rap_query_provider.
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcl_est_stores_query IMPLEMENTATION.

  METHOD if_rap_query_provider~select.
    DATA rows TYPE STANDARD TABLE OF zi_est_stores WITH EMPTY KEY.
    DATA estates TYPE RANGE OF zest_estate-estate.
    DATA materials TYPE RANGE OF zest_mm_mock-material.

    TRY.
        DATA(ranges) = io_request->get_filter( )->get_as_ranges( ).
      CATCH cx_rap_query_filter_no_range.
        CLEAR ranges.
    ENDTRY.
    LOOP AT ranges INTO DATA(range).
      CASE range-name.
        WHEN 'ESTATE'.
          estates = CORRESPONDING #( range-range ).
        WHEN 'MATERIAL'.
          materials = CORRESPONDING #( range-range ).
      ENDCASE.
    ENDLOOP.

    SELECT estate FROM zest_estate WHERE estate IN @estates ORDER BY estate INTO TABLE @DATA(selected).
    LOOP AT selected INTO DATA(estate).
      LOOP AT zcl_est_stores=>overview( estate-estate ) INTO DATA(row) WHERE material IN materials.
        APPEND CORRESPONDING #( row ) TO rows.
      ENDLOOP.
    ENDLOOP.

    IF io_request->is_total_numb_of_rec_requested( ).
      io_response->set_total_number_of_records( lines( rows ) ).
    ENDIF.

    IF io_request->is_data_requested( ).
      DATA(offset) = io_request->get_paging( )->get_offset( ).
      DATA(page_size) = io_request->get_paging( )->get_page_size( ).
      IF offset > 0.
        DELETE rows TO offset.
      ENDIF.
      IF page_size > 0 AND page_size <> if_rap_query_paging=>page_size_unlimited AND lines( rows ) > page_size.
        DELETE rows FROM page_size + 1.
      ENDIF.
      io_response->set_data( rows ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
