@EndUserText.label: 'Decision Parameters'
define abstract entity ZA_EST_DECISION
{
  @EndUserText.label: 'Note'
  DecisionNote   : abap.char(255);
  @EndUserText.label: 'Look Again On (deferrals)'
  DueDate        : abap.dats;
  @EndUserText.label: 'Expected Effect'
  ExpectedEffect : abap.char(255);
}
