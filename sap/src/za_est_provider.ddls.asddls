@EndUserText.label: 'AI Provider Parameter'
define abstract entity ZA_EST_PROVIDER
{
  @EndUserText.label: 'AI Provider (blank = default)'
  @Consumption.valueHelpDefinition: [ { entity: { name: 'ZI_EST_AI_PROV_VH', element: 'ProviderId' } } ]
  ProviderId : abap.char(20);
}
