@EndUserText.label: 'Answer on a Plan'
define abstract entity ZA_EST_ANSWER
{
  Answer          : abap.string(0);
  ModelId         : abap.char(60);
  AuditChecked    : abap.int4;
  AuditUnverified : abap.char(255);
}
