@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'AI Provider'
@ObjectModel.dataCategory: #VALUE_HELP
@ObjectModel.resultSet.sizeCategory: #XS
@Search.searchable: true
define view entity ZI_EST_AI_PROV_VH
  as select from zest_ai_prov
{
      @EndUserText.label: 'AI Provider'
      @ObjectModel.text.element: [ 'Description' ]
      @Search.defaultSearchElement: true
  key provider_id   as ProviderId,
      @EndUserText.label: 'Description'
      @Search.defaultSearchElement: true
      description   as Description,
      @EndUserText.label: 'Model'
      model_id      as ModelId,
      @EndUserText.label: 'Provider Type'
      provider_type as ProviderType
}
where
  is_active = 'X'
