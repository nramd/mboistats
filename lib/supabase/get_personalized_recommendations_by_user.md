
BEGIN
  RETURN QUERY
  WITH ranked_sectors AS (
    SELECT 
      rs_inner.sector_name, 
      rs_inner.score,
      ROW_NUMBER() OVER (ORDER BY rs_inner.score DESC, rs_inner.sector_name ASC) AS sector_rank
    FROM get_sector_scores_for_user(input_user_id) rs_inner
  ),
  recent_logs AS (
    SELECT DISTINCT LOWER(TRIM(a.title)) AS item_name
    FROM public.activity_logs a
    WHERE a.user_id = input_user_id
      AND a.action_type IN ('view_pdf', 'download_file', 'view_page', 'view_brs_pdf', 'view_publikasi_pdf')
      AND a.timestamp >= NOW() - INTERVAL '30 days'
  ),
  candidate_contents AS (
    SELECT 
      c.id::TEXT AS content_id,
      c.title AS content_title,
      LOWER(cat.category) AS sec_cat,
      COALESCE(c.content_type, c.action_type) AS content_type,
      c.cover_url,
      c.content_url,
      c.created_at,
      rs.score AS sector_score,
      rs.sector_rank,
      CASE 
        WHEN rl.item_name IS NOT NULL THEN 0 
        ELSE 1 
      END AS is_unseen,
      ROW_NUMBER() OVER (
        PARTITION BY LOWER(cat.category)
        ORDER BY 
          (CASE WHEN rl.item_name IS NOT NULL THEN 0 ELSE 1 END) DESC,
          c.created_at DESC
      ) AS rank_in_sector
    FROM public.contents c
    JOIN public.contents_has_categories chc ON chc.contents_id_content = c.id
    JOIN public.categories cat ON cat.id_category = chc.categories_id_category
    JOIN ranked_sectors rs ON rs.sector_name = LOWER(cat.category)
    LEFT JOIN recent_logs rl ON rl.item_name = LOWER(TRIM(c.title))
    WHERE c.title NOT ILIKE '%TEST%' 
      AND c.title NOT ILIKE '%dummy%'
      AND c.title NOT IN ('Halaman Login', 'Halaman Profil', 'Masuk dengan Google', 'Masuk dengan Google (Native)', 'Login Google Sukses', 'Login Google Native Sukses', 'Hapus Akun', 'Logout', 'Temukan BRS lainnya', 'Temukan Infografis lainnya', 'Temukan Publikasi lainnya')
  ),
  top_1_per_sector AS (
    SELECT 
      cc.content_id,
      cc.content_title,
      cc.sec_cat AS sector_category,
      cc.content_type,
      cc.cover_url,
      cc.content_url,
      (cc.sector_score * 0.70 + (EXTRACT(EPOCH FROM cc.created_at) / 1000000000.0) * 0.30)::NUMERIC AS final_score,
      cc.sector_rank
    FROM candidate_contents cc
    WHERE cc.rank_in_sector = 1
  )
  SELECT 
    t.content_id,
    t.content_title,
    t.sector_category,
    t.content_type,
    t.cover_url,
    t.content_url,
    t.final_score
  FROM top_1_per_sector t
  ORDER BY 
    t.sector_rank ASC
  LIMIT rec_limit;
END;
