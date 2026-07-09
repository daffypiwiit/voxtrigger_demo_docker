INSERT INTO public.route_tree (id, carrier) VALUES
    (0, 'default'),
    (1, 'start')
ON CONFLICT DO NOTHING;
