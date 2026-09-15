
DECLARE
  total_interactions INT := 0;
  w_explicit NUMERIC := 0.2;
  w_freq NUMERIC := 0.5;
  w_recency NUMERIC := 0.3;
  user_sectors TEXT[];
BEGIN
  SELECT ARRAY_AGG(cat.category) INTO user_sectors
  FROM public.user_all ua
  JOIN public.user_interests ui ON ui.user_id = ua.id_user
  JOIN public.categories cat ON cat.id_category = ui.category_id
  WHERE ua.email = input_user_id OR ua.id_user::TEXT = input_user_id;

  SELECT COUNT(*) INTO total_interactions
  FROM public.activity_logs a
  WHERE a.user_id = input_user_id
    AND a.timestamp >= NOW() - INTERVAL '30 days'
    AND a.category_id IS NOT NULL;

  IF total_interactions = 0 THEN
    w_explicit := 1.0; w_freq := 0.0; w_recency := 0.0;
  ELSIF total_interactions < 10 THEN
    w_explicit := 0.7; w_freq := 0.2; w_recency := 0.1;
  ELSE
    w_explicit := 0.2; w_freq := 0.5; w_recency := 0.3;
  END IF;

  RETURN QUERY
  WITH user_clicks AS (
    SELECT 
      cat.category AS sector,
      SUM(
        CASE 
          WHEN a.action_type IN ('view_pdf', 'download_file', 'view_brs_pdf', 'view_publikasi_pdf') THEN 3.0
          WHEN a.action_type = 'view_page' THEN 1.0
          ELSE 0.5
        END
      )::NUMERIC AS click_count,
      MAX(a.timestamp) AS last_click_time
    FROM public.activity_logs a
    JOIN public.categories cat ON cat.id_category = a.category_id
    WHERE a.user_id = input_user_id
      AND a.timestamp >= NOW() - INTERVAL '30 days'
    GROUP BY cat.category
  ),
  max_click AS (
    SELECT COALESCE(MAX(click_count), 1.0) AS max_val FROM user_clicks
  )
  SELECT 
    c.category AS sector_name,
    (
      w_explicit * (CASE WHEN user_sectors IS NOT NULL AND c.category = ANY(user_sectors) THEN 1.0 ELSE 0.0 END)
      + w_freq * COALESCE(uc.click_count / mc.max_val, 0.0)
      + w_recency * COALESCE(EXP(-0.1 * EXTRACT(EPOCH FROM (NOW() - uc.last_click_time)) / 3600.0), 0.0)
    )::NUMERIC AS score
  FROM public.categories c
  LEFT JOIN user_clicks uc ON uc.sector = c.category
  CROSS JOIN max_click mc
  ORDER BY score DESC;
END;
