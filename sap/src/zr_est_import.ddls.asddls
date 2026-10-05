@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.allowExtensions: true
@EndUserText.label: 'Data Import'
define root view entity ZR_EST_IMPORT
  as select from zest_import
{
  key import_uuid as ImportUuid,
  data_kind as DataKind,
  estate as Estate,
  file_name as FileName,
  @Semantics.mimeType: true
  mime_type as MimeType,
  @Semantics.largeObject: { mimeType: 'MimeType', fileName: 'FileName', contentDispositionPreference: #ATTACHMENT }
  attachment as Attachment,
  status as Status,
  status_criticality as StatusCriticality,
  rows_loaded as RowsLoaded,
  message as Message,
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
