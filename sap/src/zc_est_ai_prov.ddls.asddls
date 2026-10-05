@Metadata.allowExtensions: true
@Metadata.ignorePropagatedAnnotations: true
@EndUserText.label: 'AI Provider'
@AccessControl.authorizationCheck: #NOT_REQUIRED
define root view entity ZC_EST_AI_PROV
  provider contract transactional_query
  as projection on ZR_EST_AI_PROV
{
  key ProviderId,
  ProviderType,
  Description,
  ModelId,
  CommScenario,
  OutboundService,
  ApiPath,
  ApiRevision,
  ApiKey,
  AwsRegion,
  MaxTokens,
  Temperature,
  IsActive,
  IsDefault,
  Priority,
  CreatedBy,
  CreatedAt,
  LastChangedBy,
  LastChangedAt,
  LocalLastChangedAt
}
