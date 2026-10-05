@EndUserText.label: 'Plan Outcome'
define abstract entity ZA_EST_OUTCOME
{
  BlockLabel    : abap.char(16);
  CrewCode      : abap.char(10);
  Activity      : abap.char(16);
  PlannedQty    : abap.dec(13,2);
  ActualQty     : abap.dec(13,2);
  QtyUnit       : abap.char(10);
  AdherencePct  : abap.dec(7,1);
  OutcomeStatus : abap.char(20);
  OrderIds      : abap.char(80);
  Criticality   : abap.int1;
}
