INSERT INTO public.route_tree (id, carrier) VALUES
    (0, 'default'),
    (1, 'start')
ON CONFLICT DO NOTHING;

INSERT INTO public.dispatcher (id, setid, destination, socket, state, probe_mode, weight, priority, attrs, description) VALUES
    (1, 101, 'sip:freeswitch:5080', NULL, 0, 0, 1, 0, '', 'FreeSWITCH VoxTrigger')
ON CONFLICT DO NOTHING;
