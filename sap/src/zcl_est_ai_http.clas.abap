CLASS zcl_est_ai_http DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES ty_config TYPE zest_ai_prov.
    TYPES:
      BEGIN OF ty_header,
        name  TYPE string,
        value TYPE string,
      END OF ty_header,
      ty_headers TYPE STANDARD TABLE OF ty_header WITH EMPTY KEY.

    "! Key from the provider row; if that is empty, property API_KEY of the
    "! communication arrangement of the provider's scenario.
    CLASS-METHODS get_api_key
      IMPORTING
        config        TYPE ty_config
      RETURNING
        VALUE(result) TYPE string
      RAISING
        zcx_est_ai.

    CLASS-METHODS post
      IMPORTING
        config        TYPE ty_config
        path          TYPE string
        headers       TYPE ty_headers
        body          TYPE string
      RETURNING
        VALUE(result) TYPE string
      RAISING
        zcx_est_ai.

    "! GET on a feed that needs no key (Open-Meteo). The arrangement of COMM_SCENARIO
    "! names the host; PATH carries the query string.
    CLASS-METHODS get
      IMPORTING
        comm_scenario    TYPE csequence
        outbound_service TYPE csequence
        path             TYPE string
      RETURNING
        VALUE(result)    TYPE string
      RAISING
        zcx_est_ai.

    "! Value of an additional property of the arrangement of COMM_SCENARIO; empty when the
    "! arrangement has no such property. Raises when the scenario has no arrangement.
    CLASS-METHODS property
      IMPORTING
        comm_scenario TYPE csequence
        name          TYPE csequence
      RETURNING
        VALUE(result) TYPE string
      RAISING
        zcx_est_ai.

    CLASS-METHODS escape_json
      IMPORTING
        text          TYPE string
      RETURNING
        VALUE(result) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CONSTANTS api_key_property TYPE string VALUE 'API_KEY'.

    CLASS-METHODS get_arrangement
      IMPORTING
        comm_scenario TYPE csequence
      RETURNING
        VALUE(result) TYPE REF TO if_com_arrangement
      RAISING
        zcx_est_ai.

    CLASS-METHODS execute
      IMPORTING
        comm_scenario    TYPE csequence
        outbound_service TYPE csequence
        method           TYPE if_web_http_client=>method
        path             TYPE string
        headers          TYPE ty_headers OPTIONAL
        body             TYPE string OPTIONAL
        label            TYPE csequence
      RETURNING
        VALUE(result)    TYPE string
      RAISING
        zcx_est_ai.
ENDCLASS.



CLASS zcl_est_ai_http IMPLEMENTATION.

  METHOD get_arrangement.
    DATA scenarios TYPE if_com_scenario_factory=>ty_query-cscn_id_range.

    scenarios = VALUE #( ( sign = 'I' option = 'EQ' low = comm_scenario ) ).
    cl_com_arrangement_factory=>create_instance( )->query_ca(
      EXPORTING is_query           = VALUE #( cscn_id_range = scenarios )
      IMPORTING et_com_arrangement = DATA(arrangements) ).

    result = VALUE #( arrangements[ 1 ] OPTIONAL ).
    IF result IS NOT BOUND.
      RAISE EXCEPTION NEW zcx_est_ai(
        message = |No communication arrangement for scenario { comm_scenario }| ).
    ENDIF.
  ENDMETHOD.


  METHOD get_api_key.
    IF config-api_key IS NOT INITIAL.
      result = config-api_key.
      RETURN.
    ENDIF.

    " Both providers need the key in a custom header, which the outbound user of a
    " communication system cannot supply, so the alternative is an arrangement property.
    LOOP AT get_arrangement( config-comm_scenario )->get_properties( ) INTO DATA(property).
      IF property-name = api_key_property.
        result = VALUE #( property-values[ 1 ] OPTIONAL ).
      ENDIF.
    ENDLOOP.

    IF result IS INITIAL.
      RAISE EXCEPTION NEW zcx_est_ai(
        message = |{ config-provider_id }: no API key in the provider row or in arrangement property { api_key_property }| ).
    ENDIF.
  ENDMETHOD.


  METHOD property.
    LOOP AT get_arrangement( comm_scenario )->get_properties( ) INTO DATA(entry).
      IF entry-name = name.
        result = VALUE #( entry-values[ 1 ] OPTIONAL ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD post.
    result = execute( comm_scenario    = config-comm_scenario
                      outbound_service = config-outbound_service
                      method           = if_web_http_client=>post
                      path             = path
                      headers          = VALUE #( BASE headers ( name = 'Content-Type' value = 'application/json' ) )
                      body             = body
                      label            = config-provider_id ).
  ENDMETHOD.


  METHOD get.
    result = execute( comm_scenario    = comm_scenario
                      outbound_service = outbound_service
                      method           = if_web_http_client=>get
                      path             = path
                      label            = comm_scenario ).
  ENDMETHOD.


  METHOD execute.
    TRY.
        DATA(destination) = cl_http_destination_provider=>create_by_comm_arrangement(
          comm_scenario  = CONV #( comm_scenario )
          service_id     = CONV #( outbound_service )
          comm_system_id = get_arrangement( comm_scenario )->get_comm_system_id( ) ).
        DATA(client) = cl_web_http_client_manager=>create_by_http_destination( destination ).

        DATA(request) = client->get_http_request( ).
        request->set_uri_path( i_uri_path = path ).
        LOOP AT headers INTO DATA(header).
          request->set_header_field( i_name = header-name i_value = header-value ).
        ENDLOOP.
        IF body IS NOT INITIAL.
          request->set_text( body ).
        ENDIF.

        DATA(response) = client->execute( method ).
        DATA(status) = response->get_status( ).
        result = response->get_text( ).
        client->close( ).

      CATCH cx_http_dest_provider_error cx_web_http_client_error INTO DATA(error).
        RAISE EXCEPTION NEW zcx_est_ai( message = error->get_text( ) previous = error ).
    ENDTRY.

    IF status-code < 200 OR status-code > 299.
      " an HTML error page says what it is in its title; anything else in its first characters
      DATA(detail) = condense( result ).
      FIND FIRST OCCURRENCE OF PCRE `<title>\s*([^<]*?)\s*</title>` IN detail SUBMATCHES DATA(title) IGNORING CASE.
      IF sy-subrc = 0.
        detail = |(HTML page "{ title }")|.
      ELSE.
        detail = substring( val = detail len = nmin( val1 = strlen( detail ) val2 = 200 ) ).
      ENDIF.
      RAISE EXCEPTION NEW zcx_est_ai( message = |{ label }: HTTP { status-code } { status-reason } { detail }| ).
    ENDIF.
  ENDMETHOD.


  METHOD escape_json.
    result = escape( val = text format = cl_abap_format=>e_json_string ).
  ENDMETHOD.

ENDCLASS.
