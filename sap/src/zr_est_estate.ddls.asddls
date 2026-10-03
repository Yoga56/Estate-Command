@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.allowExtensions: true
@EndUserText.label: 'Estate'
define root view entity ZR_EST_ESTATE
  as select from zest_estate
{
  key estate as Estate,
  estate_name as EstateName,
  plant as Plant,
  storage_location as StorageLocation,
  latitude as Latitude,
  longitude as Longitude,
  currency as Currency,
  default_provider as DefaultProvider,
  is_sample as IsSample,
  data_end as DataEnd,
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
