CREATE TABLE public.hetzner_migration_runner_probe (
  id integer PRIMARY KEY,
  value text NOT NULL
);

INSERT INTO public.hetzner_migration_runner_probe (id, value)
VALUES (1, 'applied');
