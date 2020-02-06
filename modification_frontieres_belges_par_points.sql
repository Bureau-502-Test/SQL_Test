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
SET a.GEOM = (SELECT b.geom FROM ta_test_points b WHERE a.fid_closest_point = b.objectid AND a.fid_source = 3)
WHERE a.FID_CLOSEST_POINT IS NOT NULL;


-- Création d'un polygone que l'on découpe après
INSERT INTO ta_test_limites_communes(nom, geom)
SELECT
    TO_CHAR(fid_polygone),
    SDO_AGGR_CONVEXHULL(SDOAGGRTYPE(a.geom, 0.005))
FROM
    ta_test_points a
WHERE
    fid_polygone = 44;

INSERT INTO ta_test_limites_communes(nom, geom)
WITH
    v_buffer_MEL AS (
        SELECT
        SDO_AGGR_UNION(
            SDOAGGRTYPE(a.geom, 0.001)
        ) AS geom
        FROM
            ta_test_limites_communes a
        WHERE
            a.geom IS NOT NULL
            AND a.fid_source = 3
    ),

    v_difference_1 AS (
    SELECT
        a.nom,
        SDO_GEOM.SDO_DIFFERENCE(a.geom, b.geom, 0.005) AS GEOM
    FROM
        ta_test_limites_communes a,
        v_buffer_MEL
    ),

    v_selection_comparaison AS(
        SELECT
        SDO_AGGR_UNION(
            SDOAGGRTYPE(a.geom, 0.001)
        ) AS geom
        FROM
            ta_test_limites_communes a,
            v_difference_1 b
        WHERE
            TO_CHAR(a.objectid) <> b.nom
            AND SDO_GEOM.RELATE(a.geom, 'OVERLAPBDYINTERSECT', b.geom, 0.005) = 'TRUE'
        ),

    SELECT
        a.nom,
        SDO_GEOM.SDO_DIFFERENCE(a.geom, b.geom, 0.005) AS GEOM
    FROM
        v_difference_1 a,
        v_selection_comparaison b
    ;


----------!!!!!!!!!!!!!!!!!!!!!!!!----------------------
----------!!!!!!!!!!!!!!!!!!!!!!!!----------------------
----------!!!!!!!!!!!!!!!!!!!!!!!!----------------------
----------!!!!!!!!!!!!!!!!!!!!!!!!----------------------
----------!!!!!!!!!!!!!!!!!!!!!!!!----------------------
----------!!!!!!!!!!!!!!!!!!!!!!!!----------------------
----------!!!!!!!!!!!!!!!!!!!!!!!!----------------------


-- 3. Sélection des points les plus proches des points des sommets des communes françaises
/
--3.1. Sélection du point le plus proche en insérant une nouvelle donnée
SET SERVEROUTPUT ON
DECLARE
    CURSOR C_1 IS
    WITH
    -- Fusion des 90 communes actuelles de la MEL - L. 5   
    v_regroupement AS (
    SELECT
        SDO_AGGR_UNION(
            SDOAGGRTYPE(a.geom, 0.001)
        ) AS geom
    FROM
        ta_test_limites_communes a
    WHERE
        a.geom IS NOT NULL
        AND a.fid_source = 3
    ),
    
    -- Buffer de chaque municipalité à ajouter - L. 18
    v_buffer_6com AS (
    SELECT
        a.nom,
        SDO_GEOM.SDO_BUFFER(a.geom, 50, 0.001) AS geom
    FROM
        ta_test_limites_communes a
    WHERE
        a.geom IS NOT NULL
        AND a.fid_source = 25
    ),

-- Suppression des arcs pouvant occasionner des décalages entre la France et la Belgique - L. 30
    v_correction_arcs_v1 AS (
    SELECT
        a.nom,
        SDO_GEOM.SDO_ARC_DENSIFY(a.geom, 0.001, 'arc_tolerance = 0.005') AS geom
    FROM
        v_buffer_6com a
    ),   

-- Buffer de 90 communes actuelles de la MEL - L. 39    
    v_buffer_90com AS(
        SELECT
            SDO_GEOM.SDO_BUFFER(a.geom, 50, 0.001) AS geom
        FROM
            v_regroupement a
    ),
    
-- Suppression des arcs pouvant occasionner des décalages entre la France et la Belgique - L. 47
    v_correction_arcs_v2 AS (
    SELECT
        SDO_GEOM.SDO_ARC_DENSIFY(a.geom, 0.001, 'arc_tolerance = 0.005') AS geom
    FROM
        v_buffer_90com a
    ), 
    
-- Intersection entre les deux buffers afin d'avoir uniquement les parties à ajouter aux nouvelles communes de la MEL - L. 55    
    v_intersection AS(
        SELECT
            a.nom,
            SDO_GEOM.SDO_INTERSECTION(a.geom, b.geom, 0.001) AS geom
        FROM
            v_correction_arcs_v1 a,
            v_correction_arcs_v2 b
    )
    
    SELECT
        a.objectid,
        a.geom
    FROM
        ta_test_points a,
        v_intersection b
    WHERE
        a.fid_source = 25
        AND a.fid_polygone = 48
        AND SDO_RELATE(a.geom, b.geom, 'mask = anyinteract') = 'TRUE';

    v_point MDSYS.SDO_GEOMETRY;
    v_id_point NUMBER;
    v_test MDSYS.SDO_GEOMETRY;
    dist NUMBER;
    geoma MDSYS.SDO_GEOMETRY;
    geomb MDSYS.SDO_GEOMETRY;
    v_closest_point NUMBER;

BEGIN

    OPEN C_1;
    LOOP
        FETCH C_1 INTO v_id_point, v_point;
        EXIT WHEN C_1%NOTFOUND; --Pour chaque point de Comines-Warneton on sélectionne le plus proche point dont le fid_source est 3 et qui se situe dans un rayon de 30m autour du point de Comines-Warneton.
        
        SELECT SDO_AGGR_UNION(
                    SDOAGGRTYPE(a.geom, 0.001)
                ) INTO v_test
        FROM
            ta_test_points a,
            ta_test_points b
        WHERE
            b.objectid = v_id_point
            AND a.fid_source = 3
            AND SDO_WITHIN_DISTANCE(b.geom, a.geom, 'distance = 30') = 'TRUE';
    
        SDO_GEOM.SDO_CLOSEST_POINTS(v_point, v_test, 0.005, NULL, dist, geoma, geomb);
        
        IF geomb IS NOT NULL THEN
            SELECT a.objectid INTO v_closest_point FROM ta_test_points a WHERE SDO_RELATE(a.geom, geomb, 'mask = equal') = 'TRUE';
            UPDATE ta_test_points SET fid_closest_point = v_closest_point WHERE objectid = v_id_point;
        /*INSERT INTO TA_TEST_POINTS (fid_closest_point, geom)
        VALUES(2, geomb);*/
       END IF;
            
    END LOOP;
    CLOSE C_1;
    COMMIT;
END;

/

-- 1. Création d'une table de lignes temporaire
DROP TABLE ta_test_lignes CASCADE CONSTRAINTS;
DELETE FROM USER_SDO_GEOM_METADATA WHERE TABLE_NAME = 'TA_TEST_LIGNES';
COMMIT;
-- 1.1. Création de la table ta_test_lignes
CREATE TABLE ta_test_lignes(
    objectid NUMBER(38,0) GENERATED ALWAYS AS IDENTITY,
    fid_polygone NUMBER(38,0),
    fid_source NUMBER(38,0),
    geom SDO_GEOMETRY
);

-- 2. Création des commentaires sur la table et les champs
COMMENT ON TABLE ta_test_lignes IS 'Table temporaire servant à stocker les lignes résultantes de la modification des frontières belges.';
COMMENT ON COLUMN g_referentiel.ta_test_lignes.objectid IS 'Identifiant de chaque objet de la table.';
COMMENT ON COLUMN g_referentiel.ta_test_lignes.fid_polygone IS 'Identifiant du polygone d''appartenance.';
COMMENT ON COLUMN g_referentiel.ta_test_lignes.fid_source IS 'Identifiant de la donne source à laquelle appartient le polygone duquel la ligne est créée.';
COMMENT ON COLUMN g_referentiel.ta_test_lignes.geom IS 'Géométrie de la ligne.';

ALTER TABLE ta_test_lignes 
ADD CONSTRAINT ta_test_lignes_PK 
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
    'ta_test_lignes',
    'geom',
    SDO_DIM_ARRAY(SDO_DIM_ELEMENT('X', 594000, 964000, 0.005),SDO_DIM_ELEMENT('Y', 6987000, 7165000, 0.005)), 
    2154
);
COMMIT;

-- 1.4. Création de l'index spatial sur le champ geom
CREATE INDEX ta_test_lignes_SIDX
ON ta_test_lignes(GEOM)
INDEXTYPE IS MDSYS.SPATIAL_INDEX
PARAMETERS('sdo_indx_dims=2, layer_gtype=LINE, tablespace=G_ADT_INDX, work_tablespace=DATA_TEMP');

SELECT *
FROM USER_CONSTRAINTS
WHERE
    CONSTRAINT_NAME = 'V_COMMUNES_ACTUELLES_BDTOPO_PK';

-- Insertion réussie d'une ligne faite à partir de deux points de la table ta_test_points
SET SERVEROUTPUT ON
DECLARE
    start_x NUMBER(38, 10);
    start_y  NUMBER(38, 10);
    end_x  NUMBER(38, 10);
    end_y  NUMBER(38, 10);

BEGIN

    SELECT
        t.x INTO start_x
    FROM
        ta_test_points a,
        TABLE(SDO_UTIL.GETVERTICES(a.geom))t
    WHERE
        a.objectid = 6160;

    SELECT
        t.y INTO start_y
    FROM
        ta_test_points a,
        TABLE(SDO_UTIL.GETVERTICES(a.geom))t
    WHERE
        a.objectid = 6160;
        
    SELECT
        t.x INTO end_x
    FROM
        ta_test_points a,
        TABLE(SDO_UTIL.GETVERTICES(a.geom))t
    WHERE
        a.objectid = 6161;
        
    SELECT
        t.y INTO end_y
    FROM
        ta_test_points a,
        TABLE(SDO_UTIL.GETVERTICES(a.geom))t
    WHERE
        a.objectid = 6161;
        
    INSERT INTO ta_test_lignes(geom) VALUES(MDSYS.SDO_GEOMETRY(2002, 2154, NULL, MDSYS.SDO_ELEM_INFO_ARRAY(1, 2, 1), MDSYS.SDO_ORDINATE_ARRAY(start_x, start_y, end_x, end_y)));
END;








INSERT INTO ta_test_limites_communes(nom, geom)
VALUES(
    'test',
    MDSYS.SDO_GEOMETRY(2003, 2154, NULL, MDSYS.SDO_ELEM_INFO_ARRAY(1, 1003, 1), MDSYS.SDO_ORDINATE_ARRAY(
    SELECT ))
);

SET SERVEROUTPUT ON
DECLARE
    CURSOR C_1 IS
    SELECT
        a.fid_polygone,
        a.fid_order_point,
        t.x,
        t.y
    FROM
        ta_test_points a,
        TABLE(SDO_UTIL.GETVERTICES(a.geom)) t
    ORDER BY
        a.fid_polygone,
        a.fid_order_points;

    v_polygone NUMBER;
    v_order_point NUMBER;
    v_x NUMBER(38, 10);
    v_y NUMBER(38, 10);
    v_comparateur NUMBER;
    v_geometry CLOB;
BEGIN
    OPEN C_1;
        v_comparateur := 0;
        LOOP
            FETCH C_1 INTO v_polygone, v_order_point, v_x, v_y;
            EXIT WHEN C_1%NOTFOUND;
            IF v_polygone <> v_comparateur THEN
                IF v_geometry IS NOT NULL THEN
                    INSERT INTO ta_test_limites_communes(nom, geom) VALUES(TO_CHAR(v_polygone), v_geometry);
                    v_geometry := MDSYS.SDO_GEOMETRY(2003, 2154, NULL, MDSYS.SDO_ELEM_INFO_ARRAY(1, 1003, 1), MDSYS.SDO_ORDINATE_ARRAY(v_x, v_y;
                END IF;
            ELSE
                v_geometry := MDSYS.SDO_GEOMETRY(2003, 2154, NULL, MDSYS.SDO_ELEM_INFO_ARRAY(1, 1003, 1), MDSYS.SDO_ORDINATE_ARRAY(
            END IF;
    CLOSE C_1;
END;

UPDATE ta_test_points
SET geom = (SELECT a.geom FROM ta_test_points a, ta_test_points b WHERE a.objectid = b.fid_closest_point)
WHERE fid_polygone = 44;


UPDATE ta_test_points t1
SET t1.geom = (SELECT t2.geom
                FROM
                    ta_test_points t1
                    INNER JOIN ta_test_points t2
                    ON t1.fid_closest_point = t2.objectid
                WHERE
                    t1.fid_polygone = 44
                );
