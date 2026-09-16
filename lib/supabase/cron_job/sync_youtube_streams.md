CREATE OR REPLACE FUNCTION public.sync_youtube_streams(force_run boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  api_key TEXT := 'AIzaSyCHs4xGRIvAZOQ6WiNfLFyq4WgRCF4RjXI';
  channel_id TEXT := 'UCkKOTKDtStYq4YTRvjAAy6w';  -- BPS Kota Malang
  playlist_id TEXT := 'PLoLKO9YLtaoIdFRfRsuMhSaPlX2jQGrre'; -- Playlist Rilis Berita Resmi Statistik
  live_response JSONB;
  playlist_response JSONB;
  video JSONB;
  current_day INT := EXTRACT(DAY FROM NOW() AT TIME ZONE 'Asia/Jakarta');
  current_hour INT := EXTRACT(HOUR FROM NOW() AT TIME ZONE 'Asia/Jakarta');
BEGIN
  -- Guard Internal: Jika bukan eksekusi paksa (force_run), hanya jalan tanggal 1-6 pada jam 12:00 s/d 17:59 WIB
  IF NOT force_run THEN
    IF current_day < 1 OR current_day > 6 OR current_hour < 12 OR current_hour > 17 THEN
      RETURN;
    END IF;
  END IF;

  -- 1. Cek Live Stream yang sedang Aktif di Channel BPS Kota Malang
  SELECT content::jsonb INTO live_response
  FROM http_get(
    'https://www.googleapis.com/youtube/v3/search?part=snippet&channelId=' 
    || channel_id 
    || '&type=video&eventType=live&key=' || api_key
  );

  UPDATE youtube_streams SET is_live = FALSE, updated_at = NOW();

  IF live_response->'items' IS NOT NULL AND jsonb_array_length(live_response->'items') > 0 THEN
    FOR video IN SELECT * FROM jsonb_array_elements(live_response->'items')
    LOOP
      INSERT INTO youtube_streams (video_id, title, thumbnail_url, published_at, is_live)
      VALUES (
        video->'id'->>'videoId',
        video->'snippet'->>'title',
        COALESCE(video->'snippet'->'thumbnails'->'high'->>'url', video->'snippet'->'thumbnails'->'default'->>'url'),
        (video->'snippet'->>'publishedAt')::timestamptz,
        TRUE
      )
      ON CONFLICT (video_id) DO UPDATE SET
        title = EXCLUDED.title,
        thumbnail_url = EXCLUDED.thumbnail_url,
        is_live = TRUE,
        updated_at = NOW();
    END LOOP;
  END IF;

  -- 2. Ambil Rekaman Video KHUSUS dari Playlist "Rilis Berita Resmi Statistik" (hingga 50 video terbaru)
  SELECT content::jsonb INTO playlist_response 
  FROM http_get(
    'https://www.googleapis.com/youtube/v3/playlistItems?part=snippet&playlistId=' 
    || playlist_id 
    || '&maxResults=50&key=' || api_key
  );

  IF playlist_response->'items' IS NOT NULL AND jsonb_array_length(playlist_response->'items') > 0 THEN
    FOR video IN SELECT * FROM jsonb_array_elements(playlist_response->'items')
    LOOP
      IF video->'snippet'->'resourceId'->>'videoId' IS NOT NULL 
         AND video->'snippet'->>'title' NOT IN ('Private video', 'Deleted video') THEN
        INSERT INTO youtube_streams (video_id, title, thumbnail_url, published_at, is_live)
        VALUES (
          video->'snippet'->'resourceId'->>'videoId',
          video->'snippet'->>'title',
          COALESCE(
            video->'snippet'->'thumbnails'->'high'->>'url', 
            video->'snippet'->'thumbnails'->'medium'->>'url',
            video->'snippet'->'thumbnails'->'default'->>'url'
          ),
          (video->'snippet'->>'publishedAt')::timestamptz,
          FALSE
        )
        ON CONFLICT (video_id) DO UPDATE SET
          title = EXCLUDED.title,
          thumbnail_url = EXCLUDED.thumbnail_url,
          published_at = EXCLUDED.published_at,
          updated_at = NOW();
      END IF;
    END LOOP;
  END IF;
END;
$function$
