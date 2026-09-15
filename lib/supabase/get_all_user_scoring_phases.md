
BEGIN
  RETURN QUERY
  WITH all_users AS (
    SELECT DISTINCT
      ua.id_user::TEXT AS user_uuid,
      ua.email AS user_email,
      ua.created_at AS reg_time
    FROM public.user_all ua
    JOIN public.user_interests ui ON ui.user_id = ua.id_user
    UNION
    SELECT 
      a.user_id AS user_uuid,
      a.user_id AS user_email,
      MIN(a.timestamp) AS reg_time
    FROM public.activity_logs a
    WHERE a.user_id IS NOT NULL AND a.user_id <> '' AND a.user_id <> 'Anonymous'
    GROUP BY a.user_id
  ),
  distinct_users AS (
    SELECT 
      au.user_email,
      MAX(au.user_uuid) AS user_uuid,
      MIN(au.reg_time) AS first_seen
    FROM all_users au
    WHERE au.user_email IS NOT NULL AND au.user_email <> ''
    GROUP BY au.user_email
  ),
  user_stats AS (
    SELECT 
      du.user_email,
      du.user_uuid,
      COUNT(a.id) FILTER (
        WHERE a.timestamp >= NOW() - INTERVAL '30 days'
          AND a.category_id IS NOT NULL
          AND a.action_type NOT IN ('login_success', 'click_login_google', 'delete_account', 'logout')
          AND a.title NOT IN ('Halaman Login', 'Halaman Profil', 'Masuk dengan Google', 'Masuk dengan Google (Native)', 'Login Google Sukses', 'Login Google Native Sukses', 'Hapus Akun', 'Logout')
      ) AS interactions_30d,
      COALESCE(MAX(a.timestamp), du.first_seen) AS last_activity,
      COALESCE(MAX(a.platform), 'Android') AS platform
    FROM distinct_users du
    LEFT JOIN public.activity_logs a ON a.user_id = du.user_email OR a.user_id = du.user_uuid
    GROUP BY du.user_email, du.user_uuid, du.first_seen
  ),
  phase_calc AS (
    SELECT 
      us.*,
      CASE 
        WHEN us.interactions_30d = 0 THEN 'cold-start'
        WHEN us.interactions_30d < 10 THEN 'warm-up'
        ELSE 'established'
      END AS phase,
      CASE WHEN us.interactions_30d = 0 THEN 1.0
           WHEN us.interactions_30d < 10 THEN 0.7
           ELSE 0.2 END AS w_explicit,
      CASE WHEN us.interactions_30d = 0 THEN 0.0
           WHEN us.interactions_30d < 10 THEN 0.2
           ELSE 0.5 END AS w_freq,
      CASE WHEN us.interactions_30d = 0 THEN 0.0
           WHEN us.interactions_30d < 10 THEN 0.1
           ELSE 0.3 END AS w_recency
    FROM user_stats us
  ),
  user_onboarding AS (
    SELECT 
      ua.email,
      ARRAY_AGG(cat.category) AS sectors
    FROM public.user_all ua
    JOIN public.user_interests ui ON ui.user_id = ua.id_user
    JOIN public.categories cat ON cat.id_category = ui.category_id
    GROUP BY ua.email
  ),
  top_sectors AS (
    SELECT DISTINCT ON (du_sub.u_id)
      du_sub.u_id,
      rss.sector_name AS top_sector,
      rss.score AS top_sector_score
    FROM (
      SELECT du.user_email AS u_id FROM distinct_users du
    ) du_sub
    CROSS JOIN LATERAL get_sector_scores_for_user(du_sub.u_id) rss
    ORDER BY du_sub.u_id, rss.score DESC
  )
  SELECT 
    pc.user_uuid AS device_id,
    pc.user_email AS user_id,
    pc.platform,
    pc.phase,
    pc.interactions_30d AS total_interactions,
    pc.w_explicit,
    pc.w_freq,
    pc.w_recency,
    uo.sectors AS onboarding_sectors,
    ts.top_sector,
    COALESCE(ts.top_sector_score, 1.0)::NUMERIC AS top_sector_score,
    pc.last_activity
  FROM phase_calc pc
  LEFT JOIN user_onboarding uo ON uo.email = pc.user_email
  LEFT JOIN top_sectors ts ON ts.u_id = pc.user_email
  ORDER BY pc.last_activity DESC;
END;
