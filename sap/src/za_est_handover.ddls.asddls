@EndUserText.label: 'Shift Handover'
define abstract entity ZA_EST_HANDOVER
{
  HandoverHeadline : abap.char(255);
  Decided          : abap.string(0);
  OpenPositions    : abap.string(0);
  Watchlist        : abap.string(0);
  HandoverNote     : abap.string(0);
  ModelId          : abap.char(60);
  AuditUnverified  : abap.char(255);
}
