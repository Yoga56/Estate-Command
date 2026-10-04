@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.allowExtensions: true
@EndUserText.label: 'AI Provider'
define root view entity ZR_EST_AI_PROV
  as select from zest_ai_prov
{
  key provider_id as ProviderId,
  provider_type as ProviderType,
  description as Description,
  model_id as ModelId,
  comm_scenario as CommScenario,
  outbound_service as OutboundService,
  api_path as ApiPath,
  api_revision as ApiRevision,
  api_key as ApiKey,
  aws_region as AwsRegion,
  max_tokens as MaxTokens,
  temperature as Temperature,
  is_active as IsActive,
  is_default as IsDefault,
  priority as Priority,
  @Semantics.user.createdBy: true
  created_by as CreatedBy,
  @Semantics.systemDateTime.createdAt: true
  created_at as CreatedAt,
  @Semantics.user.lastChangedBy: true
  last_changed_by as LastChangedBy,
  @Semantics.systemDateTime.lastChangedAt: true
  last_changed_at as LastChangedAt,
  @Semantics.systemDateTime.localInstanceLastChangedAt: true
  local_last_changed_at as LocalLastChangedAt
}
