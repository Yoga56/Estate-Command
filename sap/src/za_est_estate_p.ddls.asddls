@EndUserText.label: 'Estate Parameter'
define abstract entity ZA_EST_ESTATE_P
{
  @EndUserText.label: 'Estate'
  @Consumption.valueHelpDefinition: [ { entity: { name: 'ZC_EST_ESTATE', element: 'Estate' } } ]
  Estate : abap.char(10);
}
