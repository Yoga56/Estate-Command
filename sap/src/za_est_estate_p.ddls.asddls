@EndUserText.label: 'Estate Parameter'
define abstract entity ZA_EST_ESTATE_P
{
  @EndUserText.label: 'Estate'
  @Consumption.valueHelpDefinition: [ { entity: { name: 'ZI_EST_ESTATE_VH', element: 'Estate' } } ]
  Estate : abap.char(10);
}
