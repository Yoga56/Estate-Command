@EndUserText.label: 'Replan Parameters'
define abstract entity ZA_EST_REPLAN
{
  @EndUserText.label: 'Crew Out for the Day'
  CrewOut       : abap.char(10);
  @EndUserText.label: 'Crew Whose Headcount Changes'
  CrewCode      : abap.char(10);
  @EndUserText.label: 'Headcount for That Crew'
  CrewPresent   : abap.int4;
  @EndUserText.label: 'Rain on the Day, mm (blank = forecast)'
  RainMm        : abap.char(8);
  @EndUserText.label: 'Block Held Back'
  BlockHeld     : abap.char(16);
  @EndUserText.label: 'Contiguity Bonus % (blank = register)'
  ContiguityPct : abap.char(8);
  @EndUserText.label: 'Clear Earlier Changes First'
  ClearChanges  : abap_boolean;
  @EndUserText.label: 'AI Provider (blank = same)'
  ProviderId    : abap.char(20);
}
