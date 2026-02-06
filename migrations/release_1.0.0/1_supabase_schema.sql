-- Create enum type for plan
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE TYPE plan AS ENUM ('free', 'pro', 'free_trial_over');

-- Create organizations table
CREATE TABLE organization (
    id TEXT PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    name TEXT,
    image_url TEXT,
    allowed_responses_count INTEGER,
    plan plan
);

-- Create users table with reference to organization
CREATE TABLE "user" (
    id TEXT PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    email TEXT,
    organization_id TEXT NOT NULL REFERENCES organization(id)
);

-- Create interviewers table with reference to organization
CREATE TABLE interviewer (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    agent_id TEXT,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    image TEXT NOT NULL,
    audio TEXT,
    empathy INTEGER NOT NULL,
    exploration INTEGER NOT NULL,
    rapport INTEGER NOT NULL,
    speed INTEGER NOT NULL,
    organization_id TEXT NOT NULL REFERENCES organization(id)
);

-- Create interviews table with references to user, interviewer, and organization
CREATE TABLE interview (
    id TEXT PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    name TEXT,
    description TEXT,
    objective TEXT,
    user_id TEXT REFERENCES "user"(id),
    interviewer_id INTEGER REFERENCES interviewer(id),
    is_active BOOLEAN DEFAULT true,
    is_anonymous BOOLEAN DEFAULT false,
    is_archived BOOLEAN DEFAULT false,
    logo_url TEXT,
    theme_color TEXT,
    url TEXT,
    readable_slug TEXT,
    questions JSONB,
    quotes JSONB[],
    insights TEXT[],
    respondents TEXT[],
    question_count INTEGER,
    response_count INTEGER,
    time_duration TEXT,
    organization_id TEXT NOT NULL REFERENCES organization(id)
);

-- Create responses table with references to interview and organization
CREATE TABLE response (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    interview_id TEXT REFERENCES interview(id),
    name TEXT,
    email TEXT,
    call_id TEXT,
    candidate_status TEXT,
    duration INTEGER,
    details JSONB,
    analytics JSONB,
    is_analysed BOOLEAN DEFAULT false,
    is_ended BOOLEAN DEFAULT false,
    is_viewed BOOLEAN DEFAULT false,
    tab_switch_count INTEGER,
    organization_id TEXT NOT NULL REFERENCES organization(id)
);

-- Create feedback table with references to interview and organization
CREATE TABLE feedback (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    interview_id TEXT REFERENCES interview(id),
    email TEXT,
    feedback TEXT,
    satisfaction INTEGER,
    organization_id TEXT NOT NULL REFERENCES organization(id)
);

-- Create writing_style_analysis table with reference to organization
CREATE TABLE writing_style_analysis (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    organization_id TEXT NOT NULL REFERENCES organization(id),
    tone_of_voice JSONB NOT NULL,
    key_word_choices JSONB NOT NULL,
    writing_style JSONB NOT NULL,
    narrative_techniques JSONB NOT NULL
);

-- Create indexes for improved query performance
CREATE INDEX user_organization_id_idx ON "user" (organization_id);
CREATE INDEX interviewer_organization_id_idx ON "interviewer" (organization_id);
CREATE INDEX interview_organization_id_idx ON "interview" (organization_id);
CREATE INDEX response_organization_id_idx ON "response" (organization_id);
CREATE INDEX feedback_organization_id_idx ON "feedback" (organization_id);
CREATE INDEX writing_style_analysis_organization_id_idx ON writing_style_analysis (organization_id); 