@EndUserText.label: 'Fire Hotspot'
@ObjectModel.query.implementedBy: 'ABAP:ZCL_EST_FIRE_QUERY'
define custom entity ZI_EST_FIRE
{
  key Estate       : abap.char(10);
  key HotspotId    : abap.char(80);
      // the row with IsStatus set carries the answer for the estate: read or not, radius, days
      IsStatus     : abap_boolean;
      StatusText   : abap.char(255);
      RadiusKm     : abap.dec(5,1);
      WatchDays    : abap.int4;
      Latitude     : abap.dec(10,6);
      Longitude    : abap.dec(10,6);
      AcqDate      : abap.dats;
      AcqTime      : abap.char(4);
      Product      : abap.char(20);
      Satellite    : abap.char(10);
      Instrument   : abap.char(10);
      Confidence   : abap.char(10);
      Criticality  : abap.int1;
      Frp          : abap.dec(9,2);
      Brightness   : abap.dec(7,2);
      DayNight     : abap.char(1);
      DistanceKm   : abap.dec(7,2);
      NearestBlock : abap.char(20);
      IsInside     : abap_boolean;
}
