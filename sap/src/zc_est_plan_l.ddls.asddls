@Metadata.allowExtensions: true
@Metadata.ignorePropagatedAnnotations: true
@EndUserText.label: 'Assignment Line'
@AccessControl.authorizationCheck: #NOT_REQUIRED
define view entity ZC_EST_PLAN_L
  as projection on ZR_EST_PLAN_L
{
  key LineUuid,
  PlanUuid,
  LineNo,
  IsAssigned,
  CrewCode,
  CrewRange,
  CrewPresent,
  SequenceNo,
  BlockKey,
  BlockLabel,
  Division,
  Activity,
  Quantity,
  QtyUnit,
  ManDays,
  WorkShare,
  Urgency,
  DaysSince,
  TargetDays,
  BlockValue,
  Deferral,
  Contiguity,
  TravelKm,
  TravelCost,
  Score,
  IsContiguous,
  RoadCondition,
  Criticality,
  LineNote,
  LocalLastChangedAt,
  _Plan : redirected to parent ZC_EST_PLAN
}
