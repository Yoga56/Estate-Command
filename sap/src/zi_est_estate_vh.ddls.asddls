@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Estate'
@ObjectModel.dataCategory: #VALUE_HELP
@ObjectModel.resultSet.sizeCategory: #XS
@Search.searchable: true
define view entity ZI_EST_ESTATE_VH
  as select from zest_estate
{
      @EndUserText.label: 'Estate'
      @ObjectModel.text.element: [ 'EstateName' ]
      @Search.defaultSearchElement: true
  key estate      as Estate,
      @EndUserText.label: 'Name'
      @Search.defaultSearchElement: true
      estate_name as EstateName,
      @EndUserText.label: 'Plant'
      plant       as Plant,
      @EndUserText.label: 'Sample Data'
      is_sample   as IsSample
}
