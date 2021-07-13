DROP FUNCTION IF EXISTS assessment_instances_update_points(bigint,double precision,bigint,bigint,varchar,timestamptz,boolean);

CREATE OR REPLACE FUNCTION
    assessment_instances_update_points(
        IN assessment_instance_id bigint,
        IN new_points double precision,
        IN authn_user_id bigint,
        IN assessment_id bigint,
        IN user_uid varchar,
        IN date timestamptz,
        IN score_only boolean
    ) RETURNS void
AS $$
DECLARE
    max_points double precision;
    new_score_perc double precision;
    instance_id bigint := assessment_instance_id;
    user_id bigint;
    group_work boolean;
    mode enum_mode;
    time_limit_min integer := 0;
BEGIN
    SELECT ai.max_points INTO max_points FROM assessment_instances AS ai WHERE ai.id = assessment_instance_id;

    IF NOT FOUND THEN
		IF score_only THEN
			SELECT 
				a.group_work,
				a.mode
			INTO
				group_work,
				mode
			FROM assessments AS a WHERE a.id = assessment_id;

			IF group_work THEN
				SELECT
					gu.user_id
				INTO
					user_id
				FROM
					group_users as gu
					JOIN groups AS g ON (g.id = gu.group_id)
					JOIN group_configs AS gc ON (gc.id = g.group_config_id)
				WHERE 
					g.name = user_uid
					AND gc.assessment_id = assessment_instances_update_points.assessment_id
					AND gc.deleted_at IS NULL
					AND g.deleted_at IS NULL;
			ELSE
				SELECT u.user_id INTO user_id FROM users AS u WHERE u.uid = user_uid;
			END IF;
			
			SELECT
				tmp.assessment_instance_id
			INTO
				instance_id
			FROM assessment_instances_insert(assessment_id, user_id, group_work, authn_user_id, mode, time_limit_min, date) AS tmp;

			max_points := 1;
		ELSE
			RAISE EXCEPTION 'no such assessment_instance_id: %', assessment_instance_id;
		END IF;
	END IF;
    
    new_score_perc := new_points / (CASE WHEN max_points > 0 THEN max_points ELSE 1 END) * 100;

    WITH updated_assessment_instances AS (
        UPDATE assessment_instances AS ai
        SET
            points = new_points,
            points_in_grading = 0,
            score_perc = new_score_perc,
            score_perc_in_grading = 0,
            modified_at = now()
        WHERE ai.id = instance_id
        RETURNING ai.*
    )
    INSERT INTO assessment_score_logs
        (assessment_instance_id,  auth_user_id,    max_points,
           points,    points_in_grading,    score_perc,    score_perc_in_grading)
    SELECT
                          ai.id, authn_user_id, ai.max_points,
        ai.points, ai.points_in_grading, ai.score_perc, ai.score_perc_in_grading
    FROM
        updated_assessment_instances AS ai;
END;
$$ LANGUAGE plpgsql VOLATILE;
