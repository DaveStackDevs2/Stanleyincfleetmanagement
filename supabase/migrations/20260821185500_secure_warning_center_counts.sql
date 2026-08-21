-- Keep Warning Center counts as the existing internal dashboard helper.
-- Data-free: this changes only function security metadata and EXECUTE grants.
ALTER FUNCTION public.get_warning_center_counts_state() OWNER TO postgres;
ALTER FUNCTION public.get_warning_center_counts_state() SECURITY DEFINER;
ALTER FUNCTION public.get_warning_center_counts_state() SET search_path TO '';

REVOKE ALL ON FUNCTION public.get_warning_center_counts_state()
FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.get_warning_center_counts_state()
TO service_role;
