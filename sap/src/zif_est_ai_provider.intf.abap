INTERFACE zif_est_ai_provider
  PUBLIC.

  TYPES:
    BEGIN OF ty_result,
      text          TYPE string,
      input_tokens  TYPE i,
      output_tokens TYPE i,
      raw           TYPE string,
    END OF ty_result.

  "! Sends one prompt and returns the model's text answer.
  "! @parameter json_schema | JSON schema the answer must follow (used where the API supports it)
  METHODS complete
    IMPORTING
      system_prompt TYPE string
      user_prompt   TYPE string
      json_schema   TYPE string OPTIONAL
    RETURNING
      VALUE(result) TYPE ty_result
    RAISING
      zcx_est_ai.

ENDINTERFACE.
