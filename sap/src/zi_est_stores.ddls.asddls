@EndUserText.label: 'Stores: What to Order'
@ObjectModel.query.implementedBy: 'ABAP:ZCL_EST_STORES_QUERY'
@Metadata.allowExtensions: true
define custom entity ZI_EST_STORES
{
  key Estate            : abap.char(10);
  key Material          : abap.char(40);
      MaterialName      : abap.char(60);
      MaterialGroup     : abap.char(9);
      QtyUnit           : abap.char(3);
      Supplier          : abap.char(10);
      SupplierName      : abap.char(60);
      StockOnHand       : abap.dec(15,3);
      OnOrder           : abap.dec(15,3);
      DailyUse          : abap.dec(15,3);
      QuotedDays        : abap.int4;
      UsualDays         : abap.int4;
      LateDays          : abap.int4;
      VeryLatePct       : abap.int4;
      OrdersMeasured    : abap.int4;
      ReorderPoint      : abap.dec(15,3);
      SapReorderPoint   : abap.dec(15,3);
      SafetyStock       : abap.dec(15,3);
      BufferForDelivery : abap.dec(15,3);
      BufferForUse      : abap.dec(15,3);
      OrderByDate       : abap.dats;
      OrderQty          : abap.dec(15,3);
      StockStatus       : abap.char(12);
      StatusCriticality : abap.int1;
      Headline          : abap.char(160);
      LeadSentence      : abap.char(255);
      BufferSentence    : abap.char(255);
      PolicySource      : abap.char(20);
      IsSample          : abap_boolean;
}
