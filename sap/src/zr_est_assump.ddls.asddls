@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.allowExtensions: true
@EndUserText.label: 'Assumption'
define root view entity ZR_EST_ASSUMP
  as select from zest_assump
{
  key assumption_key as AssumptionKey,
  assumption_label as AssumptionLabel,
  assumption_value as AssumptionValue,
  default_value as DefaultValue,
  value_unit as ValueUnit,
  value_source as ValueSource,
  basis as Basis,
  used_by as UsedBy,
  min_value as MinValue,
  max_value as MaxValue,
  assumption_group as AssumptionGroup,
  sort_order as SortOrder,
  @Semantics.user.createdBy: true
  created_by as CreatedBy,
  @Semantics.systemDateTime.createdAt: true
  created_at as CreatedAt,
  @Semantics.user.lastChangedBy: true
  last_changed_by as LastChangedBy,
  @Semantics.systemDateTime.lastChangedAt: true
  last_changed_at as LastChangedAt,
  @Semantics.systemDateTime.localInstanceLastChangedAt: true
  local_last_changed_at as LocalLastChangedAt
}
