/*
Table temporaire servant à récupérer tous les noeuds des communes françaises sous forme de point, afin de bouger les frontières belges.
*/

-- 1. Création de la table ta_test_points
CREATE TABLE ta_test_points(
    objectid NUMBER(38,0),
    nom VARCHAR2(200),
    geom SDO_GEOMETRY
);

-- 2. Création des commentaires sur la table et les champs
COMMENT ON TABLE ta_test_points IS 'Table temporaire rassemblant tous les noeuds des communes françaises sous forme de point.';
COMMENT ON COLUMN g_referentiel.ta_test_points.objectid IS 'Identifiant de chaque objet de la table.';
COMMENT ON COLUMN g_referentiel.ta_test_points.nom IS 'Nom de chaque commune.';
COMMENT ON COLUMN g_referentiel.ta_test_points.geom IS 'Géométrie de chaque point.';
-- 3. Création de la clé primaire
ALTER TABLE ta_test_points 
ADD CONSTRAINT ta_test_points_PK 
PRIMARY KEY("OBJECTID") 
USING INDEX TABLESPACE "G_ADT_INDX";

-- 4. Création de la séquence d'auto-incrémentation
CREATE SEQUENCE SEQ_ta_test_points
START WITH 1 INCREMENT BY 1;

-- 5. Création du déclencheur de la séquence permettant d'avoir une PK auto-incrémentée
CREATE OR REPLACE TRIGGER BEF_ta_test_points
BEFORE INSERT ON ta_test_points
FOR EACH ROW
BEGIN
    :new.objectid := SEQ_ta_test_points.nextval;
END;

-- 6. Création des métadonnées spatiales
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

-- 7. Création de l'index spatial sur le champ geom
CREATE INDEX ta_test_points_SIDX
ON ta_test_points(GEOM)
INDEXTYPE IS MDSYS.SPATIAL_INDEX
PARAMETERS('sdo_indx_dims=2, layer_gtype=POINT, tablespace=G_ADT_INDX, work_tablespace=DATA_TEMP');