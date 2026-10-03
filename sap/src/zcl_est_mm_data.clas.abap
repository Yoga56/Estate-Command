CLASS zcl_est_mm_data DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! The estate store as SAP MM holds it (port of gis/models/mm.py): material master and MRP
    "! settings, unrestricted stock, purchase orders with their goods receipts, and goods issues.
    "! An estate with a plant reads the released CDS views of S/4HANA Cloud; an estate without
    "! one reads the sample rows in ZEST_MM_MOCK, whose dates are days from today so the
    "! history never ages.
    TYPES ty_qty TYPE decfloat34.
    TYPES:
      BEGIN OF ty_material,
        material       TYPE zest_mm_mock-material,
        material_name  TYPE zest_mm_mock-material_name,
        material_group TYPE zest_mm_mock-material_group,
        unit           TYPE zest_mm_mock-qty_unit,
        supplier       TYPE zest_mm_mock-supplier,
        supplier_name  TYPE zest_mm_mock-supplier_name,
        "! planned delivery time in the material master (MARC-PLIFZ)
        quoted_days    TYPE i,
        "! SAP's reorder point and safety stock (MARC-MINBE, MARC-EISBE)
        reorder_point  TYPE ty_qty,
        safety_stock   TYPE ty_qty,
        rounding       TYPE ty_qty,
        price          TYPE ty_qty,
      END OF ty_material,
      ty_materials TYPE STANDARD TABLE OF ty_material WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_order,
        material      TYPE zest_mm_mock-material,
        supplier      TYPE zest_mm_mock-supplier,
        supplier_name TYPE zest_mm_mock-supplier_name,
        document      TYPE zest_mm_mock-document,
        ordered_on    TYPE d,
        "! goods receipt that completed the order; for an open order, when it is expected
        received_on   TYPE d,
        is_open       TYPE abap_bool,
        quantity      TYPE ty_qty,
      END OF ty_order,
      ty_orders TYPE STANDARD TABLE OF ty_order WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_issue,
        material TYPE zest_mm_mock-material,
        issued_on TYPE d,
        quantity TYPE ty_qty,
      END OF ty_issue,
      ty_issues TYPE STANDARD TABLE OF ty_issue WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_stock,
        material TYPE zest_mm_mock-material,
        quantity TYPE ty_qty,
      END OF ty_stock,
      ty_stocks TYPE HASHED TABLE OF ty_stock WITH UNIQUE KEY material.

    "! Purchase orders and issues are read this far back
    CONSTANTS history_days TYPE i VALUE 730.
    "! materials planned at most, largest reorder point first
    CONSTANTS max_materials TYPE i VALUE 200.

    DATA is_sample TYPE abap_bool READ-ONLY.
    DATA materials TYPE ty_materials READ-ONLY.
    DATA stock TYPE ty_stocks READ-ONLY.
    DATA orders TYPE ty_orders READ-ONLY.
    DATA issues TYPE ty_issues READ-ONLY.

    METHODS constructor
      IMPORTING estate TYPE zest_estate.

  PROTECTED SECTION.
  PRIVATE SECTION.
    METHODS read_sample
      IMPORTING estate TYPE zest_estate-estate
                today  TYPE d.

    METHODS read_plant
      IMPORTING plant  TYPE zest_estate-plant
                today  TYPE d.
ENDCLASS.



CLASS zcl_est_mm_data IMPLEMENTATION.

  METHOD constructor.
    DATA(today) = cl_abap_context_info=>get_system_date( ).
    is_sample = xsdbool( estate-plant IS INITIAL ).
    IF is_sample = abap_true.
      read_sample( estate = estate-estate today = today ).
    ELSE.
      read_plant( plant = estate-plant today = today ).
    ENDIF.
    SORT orders BY material ordered_on.
    SORT issues BY material issued_on.
  ENDMETHOD.


  METHOD read_sample.
    SELECT * FROM zest_mm_mock WHERE estate = @estate ORDER BY row_id INTO TABLE @DATA(rows).

    LOOP AT rows INTO DATA(row).
      CASE row-kind.
        WHEN 'M'.
          APPEND VALUE #( material       = row-material
                          material_name  = row-material_name
                          material_group = row-material_group
                          unit           = row-qty_unit
                          supplier       = row-supplier
                          supplier_name  = row-supplier_name
                          quoted_days    = row-quoted_days
                          reorder_point  = row-reorder_point
                          safety_stock   = row-safety_stock
                          rounding       = row-rounding
                          price          = row-price ) TO materials.
        WHEN 'S'.
          INSERT VALUE #( material = row-material quantity = row-quantity ) INTO TABLE stock.
        WHEN 'P' OR 'O'.
          APPEND VALUE #( material      = row-material
                          supplier      = row-supplier
                          supplier_name = row-supplier_name
                          document      = row-document
                          ordered_on    = today + row-date_offset
                          received_on   = today + row-date2_offset
                          is_open       = xsdbool( row-kind = 'O' )
                          quantity      = row-quantity ) TO orders.
        WHEN 'I'.
          APPEND VALUE #( material  = row-material
                          issued_on = today + row-date_offset
                          quantity  = row-quantity ) TO issues.
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.


  METHOD read_plant.
    " Field names of the released views are listed in sap/README.md under "Check on first activation".
    DATA(language) = cl_abap_context_info=>get_user_language_abap_format( ).
    DATA(since) = CONV d( today - history_days ).

    SELECT planning~Product                       AS material,
           text~ProductDescription                AS material_name,
           product~ProductGroup                   AS material_group,
           product~BaseUnit                       AS unit,
           planning~PlannedDeliveryDurationInDays AS quoted_days,
           planning~ReorderThresholdQuantity      AS reorder_point,
           planning~SafetyStockQuantity           AS safety_stock,
           planning~LotSizeRoundingQuantity       AS rounding
      FROM I_ProductSupplyPlanning WITH PRIVILEGED ACCESS AS planning
      INNER JOIN I_Product WITH PRIVILEGED ACCESS AS product ON product~Product = planning~Product
      LEFT OUTER JOIN I_ProductDescription WITH PRIVILEGED ACCESS AS text
        ON text~Product = planning~Product AND text~Language = @language
      WHERE planning~Plant = @plant
        AND ( planning~ReorderThresholdQuantity > 0 OR planning~MRPType LIKE 'V%' )
      ORDER BY planning~ReorderThresholdQuantity DESCENDING
      INTO CORRESPONDING FIELDS OF TABLE @materials
      UP TO @max_materials ROWS.
    CHECK materials IS NOT INITIAL.

    " aggregates cannot be combined with FOR ALL ENTRIES: read the plant, keep the materials planned
    SELECT Material AS material, SUM( MatlWrhsStkQtyInMatlBaseUnit ) AS quantity
      FROM I_MaterialStock_2 WITH PRIVILEGED ACCESS
      WHERE Plant = @plant AND InventoryStockType = '01'
      GROUP BY Material
      INTO TABLE @DATA(plant_stock).
    LOOP AT plant_stock INTO DATA(stock_row).
      CHECK line_exists( materials[ material = stock_row-material ] ).
      INSERT VALUE #( material = stock_row-material quantity = stock_row-quantity ) INTO TABLE stock.
    ENDLOOP.

    " purchase orders of the last two years, and the receipts against them
    SELECT header~PurchaseOrder        AS document,
           header~PurchaseOrderDate    AS ordered_on,
           header~Supplier             AS supplier,
           supplier~SupplierName       AS supplier_name,
           item~PurchaseOrderItem      AS item,
           item~Material               AS material,
           item~OrderQuantity          AS quantity,
           item~IsCompletelyDelivered  AS delivered
      FROM I_PurchaseOrderItemAPI01 WITH PRIVILEGED ACCESS AS item
      INNER JOIN I_PurchaseOrderAPI01 WITH PRIVILEGED ACCESS AS header ON header~PurchaseOrder = item~PurchaseOrder
      LEFT OUTER JOIN I_Supplier WITH PRIVILEGED ACCESS AS supplier ON supplier~Supplier = header~Supplier
      FOR ALL ENTRIES IN @materials
      WHERE item~Material = @materials-material
        AND item~Plant = @plant
        AND header~PurchaseOrderDate >= @since
        AND item~PurchasingDocumentDeletionCode = ''
      INTO TABLE @DATA(order_items).

    SELECT PurchaseOrder AS document, PurchaseOrderItem AS item, MAX( PostingDate ) AS received_on
      FROM I_MaterialDocumentItem_2 WITH PRIVILEGED ACCESS
      WHERE Plant = @plant AND GoodsMovementType = '101' AND PostingDate >= @since AND PurchaseOrder <> ''
      GROUP BY PurchaseOrder, PurchaseOrderItem
      INTO TABLE @DATA(receipts).

    LOOP AT order_items INTO DATA(order_item).
      DATA(material) = VALUE #( materials[ material = order_item-material ] OPTIONAL ).
      DATA(receipt) = VALUE #( receipts[ document = order_item-document item = order_item-item ] OPTIONAL ).
      DATA(is_open) = xsdbool( order_item-delivered = abap_false ).
      APPEND VALUE #( material      = order_item-material
                      supplier      = order_item-supplier
                      supplier_name = order_item-supplier_name
                      document      = order_item-document
                      ordered_on    = order_item-ordered_on
                      " an open order is expected after the quoted time
                      received_on   = COND #( WHEN is_open = abap_true THEN order_item-ordered_on + material-quoted_days
                                              ELSE receipt-received_on )
                      is_open       = is_open
                      quantity      = order_item-quantity ) TO orders.
    ENDLOOP.
    DELETE orders WHERE is_open = abap_false AND received_on IS INITIAL.

    " each material's main supplier: the one it was ordered from most
    LOOP AT materials ASSIGNING FIELD-SYMBOL(<material>).
      DATA(best) = 0.
      LOOP AT orders INTO DATA(order) WHERE material = <material>-material.
        DATA(count) = REDUCE i( INIT n = 0 FOR o IN orders WHERE ( material = <material>-material AND supplier = order-supplier )
                                NEXT n = n + 1 ).
        IF count > best.
          best = count.
          <material>-supplier      = order-supplier.
          <material>-supplier_name = order-supplier_name.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    " goods issues to cost centres and orders, reversals netted out
    SELECT Material AS material, PostingDate AS issued_on, GoodsMovementType AS movement,
           SUM( QuantityInBaseUnit ) AS quantity
      FROM I_MaterialDocumentItem_2 WITH PRIVILEGED ACCESS
      WHERE Plant = @plant AND PostingDate >= @since
        AND GoodsMovementType IN ( '201', '202', '261', '262' )
      GROUP BY Material, PostingDate, GoodsMovementType
      INTO TABLE @DATA(movements).

    LOOP AT movements INTO DATA(movement).
      CHECK line_exists( materials[ material = movement-material ] ).
      APPEND VALUE #( material  = movement-material
                      issued_on = movement-issued_on
                      quantity  = COND #( WHEN movement-movement = '202' OR movement-movement = '262'
                                          THEN movement-quantity * -1 ELSE movement-quantity ) ) TO issues.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
