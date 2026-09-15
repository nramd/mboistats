-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE public.activity_logs (
id uuid NOT NULL DEFAULT gen_random_uuid(),
action_type text NOT NULL,
title text NOT NULL,
platform text NOT NULL,
user_id text,
timestamp timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
contents_id_content uuid,
youtube_streams_id_streams integer,
category_id integer,
module_name text DEFAULT 'fitur'::text,
CONSTRAINT activity_logs_pkey PRIMARY KEY (id),
CONSTRAINT activity_logs_contents_id_content_fkey FOREIGN KEY (contents_id_content) REFERENCES public.contents(id),
CONSTRAINT activity_logs_youtube_streams_id_streams_fkey FOREIGN KEY (youtube_streams_id_streams) REFERENCES public.youtube_streams(id),
CONSTRAINT activity_logs_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id_category)
);
CREATE TABLE public.contents (
id uuid NOT NULL DEFAULT gen_random_uuid(),
title text NOT NULL UNIQUE,
action_type text NOT NULL DEFAULT 'view_pdf'::text,
cover_url text,
content_url text,
created_at timestamp with time zone DEFAULT now(),
content_type text CHECK (content_type = ANY (ARRAY['brs'::text, 'publikasi'::text, 'infografis'::text])),
CONSTRAINT contents_pkey PRIMARY KEY (id)
);
CREATE TABLE public.youtube_streams (
id integer NOT NULL DEFAULT nextval('youtube_streams_id_seq'::regclass),
video_id text NOT NULL UNIQUE,
title text NOT NULL,
thumbnail_url text,
published_at timestamp with time zone,
is_live boolean DEFAULT false,
updated_at timestamp with time zone DEFAULT now(),
CONSTRAINT youtube_streams_pkey PRIMARY KEY (id)
);
CREATE TABLE public.categories (
id_category integer NOT NULL DEFAULT nextval('categories_id_category_seq'::regclass),
category text NOT NULL UNIQUE,
CONSTRAINT categories_pkey PRIMARY KEY (id_category)
);
CREATE TABLE public.major (
id_major integer NOT NULL DEFAULT nextval('major_id_major_seq'::regclass),
major text NOT NULL UNIQUE,
CONSTRAINT major_pkey PRIMARY KEY (id_major)
);
CREATE TABLE public.major_recommendations (
id integer NOT NULL DEFAULT nextval('major_recommendations_id_seq'::regclass),
major_id integer NOT NULL,
category_id integer NOT NULL,
CONSTRAINT major_recommendations_pkey PRIMARY KEY (id),
CONSTRAINT major_recommendations_major_id_fkey FOREIGN KEY (major_id) REFERENCES public.major(id_major),
CONSTRAINT major_recommendations_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id_category)
);
CREATE TABLE public.user_all (
id_user uuid NOT NULL DEFAULT gen_random_uuid(),
email text UNIQUE,
name text,
phone text,
type_user text DEFAULT 'umum'::text,
institution_id text,
university_id text,
education_id text,
work_id text,
major_id_major integer,
created_at timestamp with time zone DEFAULT now(),
age integer,
gender text,
CONSTRAINT user_all_pkey PRIMARY KEY (id_user),
CONSTRAINT user_all_major_id_major_fkey FOREIGN KEY (major_id_major) REFERENCES public.major(id_major)
);
CREATE TABLE public.user_interests (
id integer NOT NULL DEFAULT nextval('user_interests_id_seq'::regclass),
user_id uuid NOT NULL,
category_id integer NOT NULL,
CONSTRAINT user_interests_pkey PRIMARY KEY (id),
CONSTRAINT user_interests_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_all(id_user),
CONSTRAINT user_interests_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id_category)
);
CREATE TABLE public.contents_has_categories (
id integer NOT NULL DEFAULT nextval('contents_has_categories_id_seq'::regclass),
contents_id_content uuid NOT NULL,
categories_id_category integer NOT NULL,
CONSTRAINT contents_has_categories_pkey PRIMARY KEY (id),
CONSTRAINT contents_has_categories_contents_id_content_fkey FOREIGN KEY (contents_id_content) REFERENCES public.contents(id),
CONSTRAINT contents_has_categories_categories_id_category_fkey FOREIGN KEY (categories_id_category) REFERENCES public.categories(id_category)
);
