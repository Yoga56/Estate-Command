@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.allowExtensions: true
@EndUserText.label: 'Estate Block'
define view entity ZI_EST_BLOCK
  as select from zest_block
{
  key estate as Estate,
  key block_key as BlockKey,
  division as Division,
  block_code as BlockCode,
  block_label as BlockLabel,
  planted_ha as PlantedHa,
  palms as Palms,
  planted_year as PlantedYear,
  abw_kg as AbwKg,
  rotation_days as RotationDays,
  gang_code as GangCode,
  road_condition as RoadCondition,
  bunches_per_day as BunchesPerDay,
  centroid_lon as CentroidLon,
  centroid_lat as CentroidLat,
  geometry as Geometry
}
