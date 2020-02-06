/*
	Objectif : adapter les frontières des municipalités belges à celles des communes françaises.
*/

-- 1. Création d'une table de points temporaire
DROP TABLE ta_test_points CASCADE CONSTRAINTS;
DELETE FROM USER_SDO_GEOM_METADATA WHERE TABLE_NAME = 'TA_TEST_POINTS';
COMMIT;
-- 1.1. Création de la table ta_test_points
CREATE TABLE ta_test_points(
    objectid NUMBER(38,0) GENERATED ALWAYS AS IDENTITY,
    fid_polygone NUMBER(38,0),
    fid_order_point NUMBER(38,0),
    fid_source NUMBER(38,0),
    fid_closest_point NUMBER(38,0),
    geom SDO_GEOMETRY
);

-- 2. Création des commentaires sur la table et les champs
COMMENT ON TABLE ta_test_points IS 'Table temporaire servant à stocker les plus proches points entre france et belgique.';
COMMENT ON COLUMN g_referentiel.ta_test_points.objectid IS 'Identifiant de chaque objet de la table.';
COMMENT ON COLUMN g_referentiel.ta_test_points.fid_polygone IS 'Identifiant du polygone d''appartenance.';
COMMENT ON COLUMN g_referentiel.ta_test_points.fid_order_point IS 'Ordre des points de chaque polygone de départ.';
COMMENT ON COLUMN g_referentiel.ta_test_points.fid_source IS 'Identifiant de la donne source à laquelle appartient le polygone duquel est extrait le point.';
COMMENT ON COLUMN g_referentiel.ta_test_points.fid_closest_point IS 'identifiant du point le plus proche.';
COMMENT ON COLUMN g_referentiel.ta_test_points.geom IS 'Géométrie du point.';

ALTER TABLE ta_test_points 
ADD CONSTRAINT ta_test_points_PK 
PRIMARY KEY("OBJECTID") 
USING INDEX TABLESPACE "G_ADT_INDX";

-- 1.3. Création des métadonnées spatiales
INSERT INTO USER_SDO_GEOM_METADATA(
    TABLE_NAME, 
    COLUMN_NAME, 
    DIMINFO, 
    SRID
)
VALUES(
    'ta_test_points',
    'geom',
    SDO_DIM_ARRAY(SDO_DIM_ELEMENT('X', 594000, 964000, 0.005),SDO_DIM_ELEMENT('Y', 6987000, 7165000, 0.005)), 
    2154
);
COMMIT;

-- 1.4. Création de l'index spatial sur le champ geom
CREATE INDEX ta_test_points_SIDX
ON ta_test_points(GEOM)
INDEXTYPE IS MDSYS.SPATIAL_INDEX
PARAMETERS('sdo_indx_dims=2, layer_gtype=POINT, tablespace=G_ADT_INDX, work_tablespace=DATA_TEMP');

-- 2. Remplissage de la table de points temporaire 
/
-- 2.1 Remplissage avec les points des sommets de toutes les communes frontalières de la MEL
SET SERVEROUTPUT ON
DECLARE
    CURSOR C_1 IS
    WITH
    v_buffer AS( -- Le buffer permet d'avoir un seul polygone pour la MEL et donc de supprimer les points en doublon des communes limitrophes.
    SELECT
        a.fid_source,
        SDO_AGGR_UNION(
            SDOAGGRTYPE(a.geom, 0.001)
        ) AS geom
    FROM
        ta_test_limites_communes a
    WHERE
        a.geom IS NOT NULL
        AND a.fid_source = 3
    GROUP BY a.fid_source
    )

SELECT
        a.fid_source,
        t.x,
        t.y,
        t.id
    FROM
        v_buffer a,
        TABLE(SDO_UTIL.GETVERTICES(a.geom))t;
    v_x NUMBER(38, 10);
    v_y NUMBER(38, 10);
    v_source NUMBER(38,0);
    v_id NUMBER(38,0);
BEGIN
    OPEN C_1;
    LOOP
        FETCH C_1 INTO v_source, v_x, v_y, v_id;
        EXIT WHEN C_1%NOTFOUND;
        
        INSERT INTO ta_test_points(fid_order_point, fid_source, geom) VALUES(v_id, v_source, MDSYS.SDO_GEOMETRY(2001, 2154, MDSYS.SDO_POINT_TYPE(v_x, v_y, NULL), NULL, NULL));
    END LOOP;
    CLOSE C_1;
    COMMIT;
END;

/

-- 2.2. Remplissage avec les points des sommets de toutes les municipalités belges frontalières
SET SERVEROUTPUT ON
DECLARE
    CURSOR C_1 IS
    SELECT
        a.objectid,
        a.fid_source,
        t.x,
        t.y,
        t.id
    FROM
        ta_test_limites_communes a,
        TABLE(SDO_UTIL.GETVERTICES(a.geom))t
    WHERE
        a.fid_source = 25;
    v_x NUMBER(38, 10);
    v_y NUMBER(38, 10);
    v_identifiant NUMBER(38,0);
    v_source NUMBER(38,0);
    v_id NUMBER(38,0);
BEGIN
    OPEN C_1;
    LOOP
        FETCH C_1 INTO v_identifiant, v_source, v_x, v_y, v_id;
        EXIT WHEN C_1%NOTFOUND;
        
        INSERT INTO ta_test_points(fid_polygone, fid_order_point, fid_source, geom) VALUES(v_identifiant, v_id, v_source, MDSYS.SDO_GEOMETRY(2001, 2154, MDSYS.SDO_POINT_TYPE(v_x, v_y, NULL), NULL, NULL));
    END LOOP;
    CLOSE C_1;
    COMMIT;
END;

-- Remplacement de la géométrie des points
UPDATE ta_test_points a
SET a.GEOM = (SELECT b.geom FROM ta_test_points b WHERE a.fid_closest_point = b.objectid)
WHERE a.FID_CLOSEST_POINT IS NOT NULL;