SELECT 
    i.id AS interview_id,
    i.starttime,
    i.stoptime,
    i.lastmod,
    
    MAX(CASE WHEN q.fieldname = 'interviewerid' THEN a.value_text END) AS interviewerid,
    MAX(CASE WHEN q.fieldname = 'subjid' THEN a.value_text END) AS subjid,
    MAX(CASE WHEN q.fieldname = 'comfort_smartphone' THEN a.value_text END) AS comfort_smartphone,
    MAX(CASE WHEN q.fieldname = 'smartphone_features' THEN a.value_json END) AS smartphone_features,
    MAX(CASE WHEN q.fieldname = 'comments' THEN a.value_text END) AS comments,
    MAX(CASE WHEN q.fieldname = 'uniqueid' THEN a.value_text END) AS uniqueid,
    MAX(CASE WHEN q.fieldname = 'swver' THEN a.value_text END) AS swver

FROM interviews i
LEFT JOIN answers a ON i.id = a.interview_id
LEFT JOIN questions q ON a.question_id = q.id
LEFT JOIN options o ON q.id = o.question_id AND a.value_text = o.value

WHERE i.survey_id = 'assets/surveys/survey.xml'
GROUP BY i.id, i.starttime, i.stoptime, i.lastmod
ORDER BY i.starttime;