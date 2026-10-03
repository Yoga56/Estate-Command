@Metadata.allowExtensions: true
@Metadata.ignorePropagatedAnnotations: true
@EndUserText.label: 'Tomorrow''s Assignment'
@AccessControl.authorizationCheck: #MANDATORY
define root view entity ZC_EST_PLAN
  provider contract transactional_query
  as projection on ZR_EST_PLAN
  association [1..1] to ZR_EST_PLAN as _BaseEntity on $projection.PlanUuid = _BaseEntity.PlanUuid
{
  key PlanUuid,
  @Consumption.valueHelpDefinition: [ { entity: { name: 'ZI_EST_ESTATE_VH', element: 'Estate' } } ]
  Estate,
  Operation,
  PlanDate,
  Status,
  StatusCriticality,
  Crews,
  Present,
  CapacityMd,
  BlocksDue,
  ManDaysDue,
  BlocksAssigned,
  ManDaysAssigned,
  DeferralDue,
  ValueRecovered,
  UpperBound,
  GapPercent,
  ContiguityCost,
  ContiguityPercent,
  Swaps,
  RainMm,
  RainProbability,
  WeatherSource,
  StopsWork,
  StopReason,
  Overrides,
  Headline,
  Summary,
  WhyText,
  AuditChecked,
  AuditUnverified,
  AuditCriticality,
  @Consumption.valueHelpDefinition: [ { entity: { name: 'ZI_EST_AI_PROV_VH', element: 'ProviderId' } } ]
  ProviderId,
  ModelId,
  InputTokens,
  OutputTokens,
  ErrorText,
  Prompt,
  RawResponse,
  DecidedBy,
  DecidedAt,
  DecisionNote,
  DueDate,
  ExpectedEffect,
  ObservedEffect,
  ArtifactText,
  CreatedBy,
  CreatedAt,
  LastChangedBy,
  LastChangedAt,
  LocalLastChangedAt,
  _Lines : redirected to composition child ZC_EST_PLAN_L,
  _BaseEntity
}
