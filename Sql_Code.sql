USE ROLE SYSADMIN;
CREATE DATABASE MELS_SMOOTHIE_CHALLENGE_DB;
USE DATABASE MELS_SMOOTHIE_CHALLENGE_DB;
DROP SCHEMA IF EXISTS PUBLIC;
CREATE SCHEMA TRAILS;
-- Stage for GEOJSON files
CREATE STAGE TRAILS.TRAILS_GEOJSON;

-- Stage for PARQUET files
CREATE STAGE TRAILS.TRAILS_PARQUET;


select * from @trails_parquet
(file_format => ff_parquet) ;

SELECT 
    $1:sequence_1 AS sequence_1,
    $1:trail_name AS trail_name,
    $1:elevation AS elevation,
    $1:latitude AS latitude,
    $1:longitude AS longitude,
    $1:sequence_2 AS sequence_2
FROM @trails_parquet
(FILE_FORMAT => ff_parquet)
ORDER BY sequence_1;

CREATE VIEW CHERRY_CREEK_TRAIL as
select 
 $1:sequence_1 as point_id,
 $1:trail_name::varchar as trail_name,
 $1:latitude::number(11,8) as lng, --remember we did a gut check on this data
 $1:longitude::number(11,8) as lat
from @trails_parquet
(file_format => ff_parquet)
order by point_id;

--Using concatenate to prepare the data for plotting on a map
select top 100 
 lng||' '||lat as coord_pair
,'POINT('||coord_pair||')' as trail_point
from cherry_creek_trail;

--To add a column, we have to replace the entire view
--changes to the original are shown in red
create or replace view cherry_creek_trail as
select 
 $1:sequence_1 as point_id,
 $1:trail_name::varchar as trail_name,
 $1:latitude::number(11,8) as lng,
 $1:longitude::number(11,8) as lat,
 lng||' '||lat as coord_pair
from @trails_parquet
(file_format => ff_parquet)
order by point_id;

select 
'LINESTRING('||
listagg(coord_pair, ',') 
within group (order by point_id)
||')' as my_linestring
from cherry_creek_trail
where point_id <= 10
group by trail_name;

select 
'LINESTRING('||
listagg(coord_pair, ',') 
within group (order by point_id)
||')' as my_linestring
,st_length(to_geography(my_linestring)) as length_of_trail --this line is new! but it won't work!
from cherry_creek_trail
group by trail_name;


--DENVER AREA TRAIL
--Normalise the data without loading it & Visually Display the geoJSON Data
create view DENVER_AREA_TRAILS as
select
$1:features[0]:properties:Name::string as feature_name
,$1:features[0]:geometry:coordinates::string as feature_coordinates
,$1:features[0]:geometry::string as geometry
,$1:features[0]:properties::string as feature_properties
,$1:crs:properties:name::string as specs
,$1 as whole_object
from @trails_geojson (file_format => ff_json);

Select * from denver_area_trails;

select feature_name, st_length(to_geography (whole_object))as wo_length, st_length(to_geography (GEOMETRY))
as geom_length
from denver_area_trails;

select get_ddl('view', 'DENVER_AREA_TRAILS');

-- Defination
CREATE OR REPLACE VIEW MELS_SMOOTHIE_CHALLENGE_DB.TRAILS.DENVER_AREA_TRAILS (
    FEATURE_NAME,
    FEATURE_COORDINATES,
    GEOMETRY,
    TRAIL_LENGTH,
    FEATURE_PROPERTIES,
    SPECS,
    WHOLE_OBJECT
) AS
SELECT
    $1:features[0]:properties:Name::string AS feature_name,
    $1:features[0]:geometry:coordinates::string AS feature_coordinates,
    $1:features[0]:geometry::string AS geometry,
    ST_LENGTH(TO_GEOGRAPHY($1:features[0]:geometry)) AS trail_length,
    $1:features[0]:properties::string AS feature_properties,
    $1:crs:properties:name::string AS specs,
    $1 AS whole_object
FROM @trails_geojson (FILE_FORMAT => ff_json);

select
*
from DENVER_AREA_TRAILS;


--Create a view that will have similar columns to DENVER_AREA_TRAILS 
--Even though this data started out as Parquet, and we're joining it with geoJSON data
--So let's make it look like geoJSON instead.
create or replace view DENVER_AREA_TRAILS_2 as
select 
trail_name as feature_name
,'{"coordinates":['||listagg('['||lng||','||lat||']',',') within group (order by point_id)||'],"type":"LineString"}' as geometry
,st_length(to_geography(geometry))  as trail_length
from cherry_creek_trail
group by trail_name;

--Create a view that will have similar columns to DENVER_AREA_TRAILS 
select feature_name, geometry, trail_length
from DENVER_AREA_TRAILS
union all
select feature_name, geometry, trail_length
from DENVER_AREA_TRAILS_2;

select feature_name, geometry, trail_length from DENVER_AREA_TRAILS
union all select feature_name, geometry, trail_length
from DENVER_AREA_TRAILS_2;

select feature_name
, to_geography (geometry) as my_Linestring
, trail_length
from DENVER_AREA_TRAILS
union all
select feature_name
, to_geography (geometry) as my_linestring
, trail_length
from DENVER_AREA_TRAILS_2;

--Add more GeoSpatial Calculations to get more GeoSpecial Information! 
create view trails_and_boundaries as
select feature_name
, to_geography(geometry) as my_linestring
, st_xmin(my_linestring) as min_eastwest
, st_xmax(my_linestring) as max_eastwest
, st_ymin(my_linestring) as min_northsouth
, st_ymax(my_linestring) as max_northsouth
, trail_length
from DENVER_AREA_TRAILS
union all
select feature_name
, to_geography(geometry) as my_linestring
, st_xmin(my_linestring) as min_eastwest
, st_xmax(my_linestring) as max_eastwest
, st_ymin(my_linestring) as min_northsouth
, st_ymax(my_linestring) as max_northsouth
, trail_length
from DENVER_AREA_TRAILS_2;

select min (min_eastwest)
as western_edge
,min (min_northsouth)
as southern_edge
,max(max_eastwest) as eastern_edge
, max (max_northsouth)
as northern_edge
from trails_and_boundaries;

select 'POLYGON(('|| 
    min(min_eastwest)||' '||max(max_northsouth)||','|| 
    max(max_eastwest)||' '||max(max_northsouth)||','|| 
    max(max_eastwest)||' '||min(min_northsouth)||','|| 
    min(min_eastwest)||' '||min(min_northsouth)||'))' AS my_polygon
from trails_and_boundaries;
