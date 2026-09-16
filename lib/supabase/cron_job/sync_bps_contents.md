CREATE OR REPLACE FUNCTION public.sync_bps_contents()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  RAISE NOTICE 'Daily BPS Contents Sync Executed at %', NOW();
  -- Log / logika ingesti BPS
END;
$function$
