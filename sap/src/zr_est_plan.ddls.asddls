@AccessControl.authorizationCheck: #MANDATORY
@Metadata.allowExtensions: true
@EndUserText.label: 'Tomorrow''s Assignment'
define root view entity ZR_EST_PLAN
  as select from zest_plan
  composition [0..*] of ZR_EST_PLAN_L as _Lines
{
  key plan_uuid as PlanUuid,
  estate as Estate,
  operation as Operation,
  plan_date as PlanDate,
  status as Status,
  status_criticality as StatusCriticality,
  crews as Crews,
  present as Present,
  capacity_md as CapacityMd,
  blocks_due as BlocksDue,
  man_days_due as ManDaysDue,
  blocks_assigned as BlocksAssigned,
  man_days_assigned as ManDaysAssigned,
  deferral_due as DeferralDue,
  value_recovered as ValueRecovered,
  upper_bound as UpperBound,
  gap_percent as GapPercent,
  contiguity_cost as ContiguityCost,
  contiguity_percent as ContiguityPercent,
  swaps as Swaps,
  rain_mm as RainMm,
  rain_probability as RainProbability,
  weather_source as WeatherSource,
  stops_work as StopsWork,
  stop_reason as StopReason,
  overrides as Overrides,
  headline as Headline,
  summary as Summary,
  why_text as WhyText,
  audit_checked as AuditChecked,
  audit_unverified as AuditUnverified,
  audit_criticality as AuditCriticality,
  provider_id as ProviderId,
  model_id as ModelId,
  input_tokens as InputTokens,
  output_tokens as OutputTokens,
  error_text as ErrorText,
  prompt as Prompt,
  raw_response as RawResponse,
  decided_by as DecidedBy,
  decided_at as DecidedAt,
  decision_note as DecisionNote,
  due_date as DueDate,
  expected_effect as ExpectedEffect,
  observed_effect as ObservedEffect,
  artifact_text as ArtifactText,
  @Semantics.user.createdBy: true
  created_by as CreatedBy,
  @Semantics.systemDateTime.createdAt: true
  created_at as CreatedAt,
  @Semantics.user.lastChangedBy: true
  last_changed_by as LastChangedBy,
  @Semantics.systemDateTime.lastChangedAt: true
  last_changed_at as LastChangedAt,
  @Semantics.systemDateTime.localInstanceLastChangedAt: true
  local_last_changed_at as LocalLastChangedAt,
  _Lines
}
