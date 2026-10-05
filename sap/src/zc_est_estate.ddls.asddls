@Metadata.allowExtensions: true
@Metadata.ignorePropagatedAnnotations: true
@EndUserText.label: 'Estate'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Search.searchable: true
define root view entity ZC_EST_ESTATE
  provider contract transactional_query
  as projection on ZR_EST_ESTATE
{
  @Search.defaultSearchElement: true
  @ObjectModel.text.element: [ 'EstateName' ]
  key Estate,
  EstateName,
  Plant,
  StorageLocation,
  Latitude,
  Longitude,
  Currency,
  @Consumption.valueHelpDefinition: [ { entity: { name: 'ZI_EST_AI_PROV_VH', element: 'ProviderId' } } ]
  DefaultProvider,
  IsSample,
  DataEnd,
  CreatedBy,
  CreatedAt,
  LastChangedBy,
  LastChangedAt,
  LocalLastChangedAt
}
