@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.allowExtensions: true
@EndUserText.label: 'Assignment Line'
define view entity ZR_EST_PLAN_L
  as select from zest_plan_l
  association to parent ZR_EST_PLAN as _Plan on $projection.PlanUuid = _Plan.PlanUuid
{
  key line_uuid as LineUuid,
  plan_uuid as PlanUuid,
  line_no as LineNumber,
  is_assigned as IsAssigned,
  crew_code as CrewCode,
  crew_range as CrewRange,
  crew_present as CrewPresent,
  sequence_no as SequenceNo,
  block_key as BlockKey,
  block_label as BlockLabel,
  division as Division,
  activity as Activity,
  quantity as Quantity,
  qty_unit as QtyUnit,
  man_days as ManDays,
  work_share as WorkShare,
  urgency as Urgency,
  days_since as DaysSince,
  target_days as TargetDays,
  block_value as BlockValue,
  deferral as Deferral,
  contiguity as Contiguity,
  travel_km as TravelKm,
  travel_cost as TravelCost,
  score as Score,
  is_contiguous as IsContiguous,
  road_condition as RoadCondition,
  criticality as Criticality,
  line_note as LineNote,
  @Semantics.systemDateTime.localInstanceLastChangedAt: true
  local_last_changed_at as LocalLastChangedAt,
  _Plan
}
