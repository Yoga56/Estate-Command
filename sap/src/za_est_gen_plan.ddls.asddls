@EndUserText.label: 'Generate Plan Parameters'
define abstract entity ZA_EST_GEN_PLAN
{
  @EndUserText.label: 'Estate'
  @Consumption.valueHelpDefinition: [ { entity: { name: 'ZI_EST_ESTATE_VH', element: 'Estate' } } ]
  Estate     : abap.char(10);
  @EndUserText.label: 'Operation (harvest, prune, weed, spray)'
  Operation  : abap.char(10);
  @EndUserText.label: 'Plan Date (blank = day after the data)'
  PlanDate   : abap.dats;
  @EndUserText.label: 'AI Provider (blank = default)'
  @Consumption.valueHelpDefinition: [ { entity: { name: 'ZI_EST_AI_PROV_VH', element: 'ProviderId' } } ]
  ProviderId : abap.char(20);
}
