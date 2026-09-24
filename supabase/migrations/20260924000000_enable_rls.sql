-- Security hardening for Vegas AI Studios AutoDMX deployment.
-- The upstream init migration disables RLS near the end. This follow-up
-- migration restores RLS on every public table while keeping the app's
-- server-side service-role client functional (service_role bypasses RLS).

ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.automations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.send_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tracked_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.link_clicks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.processed_comments ENABLE ROW LEVEL SECURITY;
