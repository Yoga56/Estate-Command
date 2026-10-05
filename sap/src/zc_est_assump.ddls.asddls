@Metadata.allowExtensions: true
@Metadata.ignorePropagatedAnnotations: true
@EndUserText.label: 'Assumption'
@AccessControl.authorizationCheck: #NOT_REQUIRED
define root view entity ZC_EST_ASSUMP
  provider contract transactional_query
  as projection on ZR_EST_ASSUMP
{
  key AssumptionKey,
  AssumptionLabel,
  AssumptionValue,
  DefaultValue,
  ValueUnit,
  ValueSource,
  Basis,
  UsedBy,
  MinValue,
  MaxValue,
  AssumptionGroup,
  SortOrder,
  CreatedBy,
  CreatedAt,
  LastChangedBy,
  LastChangedAt,
  LocalLastChangedAt
}
