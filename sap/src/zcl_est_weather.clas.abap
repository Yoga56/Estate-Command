CLASS zcl_est_weather DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Tomorrow's rain from the free Open-Meteo forecast over the estate. Optional: without the
    "! communication arrangement, or for a day the forecast does not cover, the plan says the
    "! rain is unknown and decides without it - it never invents a figure.
    TYPES:
      BEGIN OF ty_weather,
        known       TYPE abap_bool,
        rain_mm     TYPE decfloat34,
        "! chance of any rain, percent; 0 when not given
        probability TYPE i,
        source      TYPE string,
      END OF ty_weather.

    CONSTANTS comm_scenario TYPE string VALUE `ZEST_WEATHER`.
    CONSTANTS outbound_service TYPE string VALUE `ZEST_WEATHER_REST`.

    CLASS-METHODS forecast
      IMPORTING latitude      TYPE decfloat34
                longitude     TYPE decfloat34
                on            TYPE d
      RETURNING VALUE(result) TYPE ty_weather.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_daily,
        time                          TYPE string_table,
        precipitation_sum             TYPE STANDARD TABLE OF decfloat34 WITH EMPTY KEY,
        precipitation_probability_max TYPE STANDARD TABLE OF i WITH EMPTY KEY,
      END OF ty_daily,
      BEGIN OF ty_response,
        daily TYPE ty_daily,
      END OF ty_response.
ENDCLASS.



CLASS zcl_est_weather IMPLEMENTATION.

  METHOD forecast.
    DATA response TYPE ty_response.

    result-source = `unknown: no forecast for the day`.
    IF zcl_est_assumptions=>value( 'use_rain_forecast' ) < 1.
      result-source = `unknown: the rain forecast is switched off in the assumption register`.
      RETURN.
    ENDIF.
    IF latitude IS INITIAL AND longitude IS INITIAL.
      result-source = `unknown: the estate has no coordinates`.
      RETURN.
    ENDIF.

    DATA(day) = |{ on DATE = ISO }|.
    DATA(path) = |/v1/forecast?latitude={ latitude }&longitude={ longitude }| &&
                 |&daily=precipitation_sum,precipitation_probability_max&timezone=auto| &&
                 |&start_date={ day }&end_date={ day }|.
    TRY.
        DATA(json) = zcl_est_ai_http=>get( comm_scenario    = comm_scenario
                                           outbound_service = outbound_service
                                           path             = path ).
      CATCH zcx_est_ai INTO DATA(error).
        result-source = |unknown: { error->get_text( ) }|.
        RETURN.
    ENDTRY.

    /ui2/cl_json=>deserialize( EXPORTING json = json CHANGING data = response ).
    DATA(index) = line_index( response-daily-time[ table_line = day ] ).
    IF index = 0 OR index > lines( response-daily-precipitation_sum ).
      RETURN.
    ENDIF.

    result-known       = abap_true.
    result-rain_mm     = response-daily-precipitation_sum[ index ].
    result-probability = VALUE #( response-daily-precipitation_probability_max[ index ] OPTIONAL ).
    result-source      = |predicted: Open-Meteo forecast for { day }|.
  ENDMETHOD.

ENDCLASS.
