@Metadata.allowExtensions: true
@Metadata.ignorePropagatedAnnotations: true
@EndUserText.label: 'Data Import'
@AccessControl.authorizationCheck: #NOT_REQUIRED
define root view entity ZC_EST_IMPORT
  provider contract transactional_query
  as projection on ZR_EST_IMPORT
{
  key ImportUuid,
  DataKind,
  Estate,
  FileName,
  @Semantics.mimeType: true
  MimeType,
  @Semantics.largeObject: { mimeType: 'MimeType', fileName: 'FileName', contentDispositionPreference: #ATTACHMENT }
  Attachment,
  Status,
  StatusCriticality,
  RowsLoaded,
  Message,
  CreatedBy,
  CreatedAt,
  LastChangedBy,
  LastChangedAt,
  LocalLastChangedAt
}
