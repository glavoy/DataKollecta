#!/usr/bin/env python3
"""
Generate dynamic wide-format SQL query based on questions in the database
This script reads the questions table and creates a CASE statement for each field
"""

import sqlite3
import sys

def generate_wide_format_sql(db_path, survey_id='assets/surveys/survey.xml'):
    """Generate wide format SQL based on questions in the database"""
    
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Get all questions except automatic ones we handle separately
    cursor.execute("""
        SELECT 
            id,
            fieldname,
            qtype,
            fieldtype,
            questiontext
        FROM questions 
        WHERE survey_id = ?
        ORDER BY position
    """, (survey_id,))
    
    questions = cursor.fetchall()
    
    # Separate questions into categories
    data_fields = []
    system_fields = ['starttime', 'stoptime', 'lastmod']
    automatic_fields = ['uniqueid', 'swver']
    
    case_statements = []
    
    for q_id, fieldname, qtype, fieldtype, qtext in questions:
        if fieldname in system_fields:
            continue  # These come from interviews table
        
        # Generate CASE statement for value
        case_statements.append(f"    MAX(CASE WHEN q.fieldname = '{fieldname}' THEN a.value_text END) AS {fieldname}")
        
        # For radio buttons, also get the label
        if qtype == 'radio':
            case_statements.append(f"    MAX(CASE WHEN q.fieldname = '{fieldname}' THEN o.label END) AS {fieldname}_label")
        
        # For checkboxes, get both JSON and labels
        elif qtype == 'checkbox':
            case_statements.append(f"    MAX(CASE WHEN q.fieldname = '{fieldname}' THEN a.value_json END) AS {fieldname}_values")
    
    # Build the CTE for checkbox labels
    checkbox_ctes = []
    cursor.execute("""
        SELECT fieldname 
        FROM questions 
        WHERE survey_id = ? AND qtype = 'checkbox'
        ORDER BY position
    """, (survey_id,))
    
    checkbox_fields = [row[0] for row in cursor.fetchall()]
    
    if checkbox_fields:
        for fieldname in checkbox_fields:
            checkbox_ctes.append(f"""
    {fieldname}_labels AS (
        SELECT 
            a.interview_id,
            GROUP_CONCAT(o.label, '; ') AS labels
        FROM answers a
        JOIN questions q ON a.question_id = q.id
        LEFT JOIN options o ON q.id = o.question_id 
            AND a.value_json LIKE '%"' || o.value || '"%'
        WHERE q.fieldname = '{fieldname}'
            AND a.value_json IS NOT NULL
        GROUP BY a.interview_id
    )""")
    
    # Generate the full SQL
    sql_parts = []
    
    # Add CTEs if we have checkboxes
    if checkbox_ctes:
        sql_parts.append("WITH" + ",".join(checkbox_ctes))
        sql_parts.append("")
    
    # Main SELECT
    sql_parts.append("SELECT")
    sql_parts.append("    i.id AS interview_id,")
    sql_parts.append("    i.starttime,")
    sql_parts.append("    i.stoptime,")
    sql_parts.append("    i.lastmod,")
    sql_parts.append("")
    
    # Add all the CASE statements
    sql_parts.append(",\n".join(case_statements))
    
    # Add checkbox label columns
    if checkbox_fields:
        sql_parts.append(",")
        label_cols = [f"    MAX({fieldname}_labels.labels) AS {fieldname}_labels" 
                      for fieldname in checkbox_fields]
        sql_parts.append(",\n".join(label_cols))
    
    # FROM clause
    sql_parts.append("")
    sql_parts.append("FROM interviews i")
    sql_parts.append("LEFT JOIN answers a ON i.id = a.interview_id")
    sql_parts.append("LEFT JOIN questions q ON a.question_id = q.id")
    sql_parts.append("LEFT JOIN options o ON q.id = o.question_id AND a.value_text = o.value")
    
    # Add checkbox label JOINs
    for fieldname in checkbox_fields:
        sql_parts.append(f"LEFT JOIN {fieldname}_labels ON i.id = {fieldname}_labels.interview_id")
    
    sql_parts.append("")
    sql_parts.append(f"WHERE i.survey_id = '{survey_id}'")
    sql_parts.append("")
    sql_parts.append("GROUP BY i.id, i.starttime, i.stoptime, i.lastmod")
    sql_parts.append("")
    sql_parts.append("ORDER BY i.starttime;")
    
    conn.close()
    
    return "\n".join(sql_parts)


if __name__ == "__main__":
    db_path = sys.argv[1] if len(sys.argv) > 1 else '/mnt/user-data/uploads/datakollecta.sqlite'
    
    sql = generate_wide_format_sql(db_path)
    
    print("-- " + "="*76)
    print("-- DataKollecta Survey Data - Dynamically Generated Wide Format Query")
    print("-- Generated from questions table - no hardcoded field names")
    print("-- " + "="*76)
    print()
    print(sql)
    
    # Save to file
    output_file = 'gistx_dynamic_wide_format.sql'
    with open(output_file, 'w') as f:
        f.write(sql)
    
    print(f"\n\nSQL saved to: {output_file}", file=sys.stderr)
