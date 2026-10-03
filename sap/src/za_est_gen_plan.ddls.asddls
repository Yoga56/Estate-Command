@EndUserText.label: 'Generate Plan Parameters'
define abstract entity ZA_EST_GEN_PLAN
{
  @EndUserText.label: 'Estate'
  Estate     : abap.char(10);
  @EndUserText.label: 'Operation (harvest, prune, weed, spray)'
  Operation  : abap.char(10);
  @EndUserText.label: 'Plan Date (blank = day after the data)'
  PlanDate   : abap.dats;
  @EndUserText.label: 'AI Provider (blank = default)'
  ProviderId : abap.char(20);
}
