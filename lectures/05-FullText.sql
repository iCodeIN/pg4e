
-- https://www.pg4e.com/lectures/05-FullText.sql

-- Strings, arrays, and rows

SELECT string_to_array('Hello world', ' ');
SELECT unnest(string_to_array('Hello world', ' '));

-- Inverted string index with SQL

CREATE TABLE docs (id SERIAL, doc TEXT, PRIMARY KEY(id));
INSERT INTO docs (doc) VALUES
('This is SQL and Python and other fun teaching stuff'),
('More people should learn SQL from UMSI'),
('UMSI also teaches Python and also SQL');
SELECT * FROM docs;

--- https://stackoverflow.com/questions/29419993/split-column-into-multiple-rows-in-postgres

-- Break the document column into one row per word + primary key
SELECT id, s.keyword AS keyword
FROM docs AS D, unnest(string_to_array(D.doc, ' ')) s(keyword)
ORDER BY id;

-- Discard duplicate rows
SELECT DISTINCT id, s.keyword AS keyword
FROM docs AS D, unnest(string_to_array(D.doc, ' ')) s(keyword)
ORDER BY id;

CREATE TABLE docs_gin (
  keyword TEXT,
  doc_id INTEGER REFERENCES docs(id) ON DELETE CASCADE
);

-- Insert the keyword / primary key rows into a table
INSERT INTO docs_gin (doc_id, keyword)
SELECT DISTINCT id, s.keyword AS keyword
FROM docs AS D, unnest(string_to_array(D.doc, ' ')) s(keyword)
ORDER BY id;

SELECT * FROM docs_gin ORDER BY doc_id;

-- Find all the distinct documents that match a keyword
SELECT DISTINCT doc FROM docs AS D
JOIN docs_gin AS G ON D.id = G.doc_id
WHERE G.keyword = 'UMSI';

-- We can remove duplicates and have more than one keyword
SELECT DISTINCT doc FROM docs AS D
JOIN docs_gin AS G ON D.id = G.doc_id
WHERE G.keyword IN ('fun', 'people');

-- We can handle a phrase
SELECT DISTINCT doc FROM docs AS D
JOIN docs_gin AS G ON D.id = G.doc_id
WHERE G.keyword = ANY(string_to_array('I want to learn', ' '));

-- This can go sideways - (foreshadowing stop words)
SELECT DISTINCT doc FROM docs AS D
JOIN docs_gin AS G ON D.id = G.doc_id
WHERE G.keyword = ANY(string_to_array('Search for Lemons and Neons', ' '));

-- docs_gin is purely a text (not language) based Inverted Index
-- PostgreSQL already knows how to do this using the GIN index

DROP TABLE docs cascade;
DROP INDEX gin1;
CREATE TABLE docs (id SERIAL, doc TEXT, PRIMARY KEY(id));

-- The GIN (General Inverted Index) thinks about columns that contain arrays
-- A GIN needs to know what kind of data will be in the arrays
-- array_ops (_text_ops for PostgreSQL 9) means that it is expecting
-- text[] (arrays of strings) and WHERE clauses will use array
-- operators (i.e. like <@ )

-- PostgreSQL 9
CREATE INDEX gin1 ON docs USING gin(string_to_array(doc, ' ')  _text_ops);

-- PostgreSQL >= 11
CREATE INDEX gin1 ON docs USING gin(string_to_array(doc, ' ')  array_ops);

INSERT INTO docs (doc) VALUES
('This is SQL and Python and other fun teaching stuff'),
('More people should learn SQL from UMSI'),
('UMSI also teaches Python and also SQL');

-- The <@ if "is contained within" or "intersection" from set theory
SELECT id, doc FROM docs WHERE '{learn}' <@ string_to_array(doc, ' ');
EXPLAIN SELECT id, doc FROM docs WHERE '{learn}' <@ string_to_array(doc, ' ');


-- Inverted string index wht stop words using SQL

-- If we know the documents contain natural language, we can optimize indexes

-- (1) Ignore the case of words in the index and in the query
-- (2) Don't index low-meaning "stop words" that we will ignore
-- if they are in a search query

CREATE TABLE stop_words (word TEXT unique);
INSERT INTO stop_words (word) VALUES ('is'), ('this'), ('and');

-- All we do is throw out the words in the stop word list
SELECT DISTINCT id, s.keyword AS keyword
FROM docs AS D, unnest(string_to_array(lower(D.doc), ' ')) s(keyword)
WHERE s.keyword NOT IN (SELECT word FROM stop_words)
ORDER BY id;

DELETE FROM docs_gin;

-- Put the stop-word free list into the GIN
INSERT INTO docs_gin (doc_id, keyword)
SELECT DISTINCT id, s.keyword AS keyword
FROM docs AS D, unnest(string_to_array(lower(D.doc), ' ')) s(keyword)
WHERE s.keyword NOT IN (SELECT word FROM stop_words)
ORDER BY id;

SELECT * FROM docs_gin;

-- A one word query
SELECT DISTINCT doc FROM docs AS D
JOIN docs_gin AS G ON D.id = G.doc_id
WHERE G.keyword = lower('UMSI');

-- A multi-word query
SELECT DISTINCT doc FROM docs AS D
JOIN docs_gin AS G ON D.id = G.doc_id
WHERE G.keyword =
  ANY(string_to_array(lower('Meet fun people'), ' '));

-- A stop word query - as if it were never there
SELECT DISTINCT doc FROM docs AS D
JOIN docs_gin AS G ON D.id = G.doc_id
WHERE G.keyword = lower('and');

-- Add stemming

-- We can make the index even smaller
-- (3) Only store the "stems" of words

-- Our simple approach is to make a "dictionary" of word -> stem

CREATE TABLE docs_stem (word TEXT, stem TEXT);
INSERT INTO docs_stem (word, stem) VALUES
('teaching', 'teach'), ('teaches', 'teach');

-- Move the initial word extraction into a sub-query
SELECT id, keyword FROM (
SELECT DISTINCT id, lower(s.keyword) AS keyword
FROM docs AS D, unnest(string_to_array(D.doc, ' ')) s(keyword)
) AS X;

-- Add the stems as third column (may or may not exist)
SELECT id, keyword, stem FROM (
SELECT DISTINCT id, lower(s.keyword) AS keyword
FROM docs AS D, unnest(string_to_array(D.doc, ' ')) s(keyword)
) AS K
LEFT JOIN docs_stem AS S ON K.keyword = S.word;

-- If the stem is there, use it
SELECT id,
CASE WHEN stem IS NOT NULL THEN stem ELSE keyword END,
keyword, stem
FROM (
SELECT DISTINCT id, lower(s.keyword) AS keyword
FROM docs AS D, unnest(string_to_array(D.doc, ' ')) s(keyword)
) AS K
LEFT JOIN docs_stem AS S ON K.keyword = S.word;

-- Null Coalescing - return the first non-null in a list
-- x = stem or 'teaching'  # Python
SELECT COALESCE(NULL, NULL, 'umsi');
SELECT COALESCE('umsi', NULL, 'SQL');

-- If the stem is there, use it instead of the keyword
SELECT id, COALESCE(stem, keyword)
FROM (
SELECT DISTINCT id, lower(s.keyword) AS keyword
FROM docs AS D, unnest(string_to_array(D.doc, ' ')) s(keyword)
) AS K
LEFT JOIN docs_stem AS S ON K.keyword = S.word;

-- Insert only the stems
DELETE FROM docs_gin;

INSERT INTO docs_gin (doc_id, keyword)
SELECT id, COALESCE(stem, keyword)
FROM (
  SELECT DISTINCT id, lower(s.keyword) AS keyword
  FROM docs AS D, unnest(string_to_array(D.doc, ' ')) s(keyword)
) AS K
LEFT JOIN docs_stem AS S ON K.keyword = S.word;

SELECT * FROM docs_gin;

-- Lets do stop words and stems...
DELETE FROM docs_gin;

INSERT INTO docs_gin (doc_id, keyword)
SELECT id, COALESCE(stem, keyword)
FROM (
  SELECT DISTINCT id, lower(s.keyword) AS keyword
  FROM docs AS D, unnest(string_to_array(D.doc, ' ')) s(keyword)
  WHERE s.keyword NOT IN (SELECT word FROM stop_words)
) AS K
LEFT JOIN docs_stem AS S ON K.keyword = S.word;

SELECT * FROM docs_gin;

-- Like Python null/false coalescing
-- x = stem or 'teaching'
SELECT COALESCE((SELECT stem FROM docs_stem WHERE word=lower('SQL')), lower('SQL'));

-- Handling the stems in queries.  Use the keyword if there is no stem
SELECT DISTINCT doc FROM docs AS D
JOIN docs_gin AS G ON D.id = G.doc_id
WHERE G.keyword = COALESCE((SELECT stem FROM docs_stem WHERE word=lower('SQL')), lower('SQL'));

-- Prefer the stem over the actual keyword
SELECT COALESCE((SELECT stem FROM docs_stem WHERE word=lower('teaching')), lower('teaching'));
SELECT DISTINCT doc FROM docs AS D
JOIN docs_gin AS G ON D.id = G.doc_id
WHERE G.keyword = COALESCE((SELECT stem FROM docs_stem WHERE word=lower('teaching')), lower('teaching'));

-- The technical term for converting search terms to their stems is called "conflation"
-- from https://en.wikipedia.org/wiki/Stemming

-- Using PostgreSQL built-in features (much easier and more efficient)

-- ts_vector is an special "array" of stemmed words, passed throug a stop-word
-- filter + positions within the document
SELECT to_tsvector('english', 'This is SQL and Python and other fun teaching stuff');
SELECT to_tsvector('english', 'More people should learn SQL from UMSI');
SELECT to_tsvector('english', 'UMSI also teaches Python and also SQL');

-- ts_query is an "array" of lower case, stemmed words with
-- stop words removed plus logical operators & = and, ! = not, | = or
SELECT to_tsquery('english', 'teaching');
SELECT to_tsquery('english', 'teaches');
SELECT to_tsquery('english', 'and');
SELECT to_tsquery('english', 'SQL');
SELECT to_tsquery('english', 'Teach | teaches | teaching | and | the | if');

-- Plaintext just pulls out the keywords
SELECT plainto_tsquery('english', 'SQL Python');
SELECT plainto_tsquery('english', 'Teach teaches teaching and the if');

-- A phrase is words that come in order
SELECT phraseto_tsquery('english', 'SQL Python');

-- Websearch is in PostgreSQL >= 11 and a bit like
-- https://www.google.com/advanced_search
SELECT websearch_to_tsquery('english', 'SQL -not Python');

SELECT to_tsquery('english', 'teaching') @@
  to_tsvector('english', 'UMSI also teaches Python and also SQL');

-- Lets do a natural language inverted index letting PostgreSQL do the work

DROP TABLE docs cascade;
DROP INDEX gin1;

CREATE TABLE docs (id SERIAL, doc TEXT, PRIMARY KEY(id));
CREATE INDEX gin1 ON docs USING gin(to_tsvector('english', doc));

INSERT INTO docs (doc) VALUES
('This is SQL and Python and other fun teaching stuff'),
('More people should learn SQL from UMSI'),
('UMSI also teaches Python and also SQL');

SELECT id, doc FROM docs WHERE
    to_tsquery('english', 'learn') @@ to_tsvector('english', doc);
EXPLAIN SELECT id, doc FROM docs WHERE
    to_tsquery('english', 'learn') @@ to_tsvector('english', doc);

-- Using natural language on an email corpus

-- wget https://www.pg4e.com/code/gmane.py
-- python3 gmane.py
-- Pulls data and puts it into messages table

-- CREATE TABLE IF NOT EXISTS messages

-- CREATE TABLE IF NOT EXISTS messages
--    (id SERIAL, email TEXT, sent_at TIMESTAMPTZ,
--     subject TEXT, headers TEXT, body TEXT)

-- Making a language oriented inverted index in mail messages

SELECT to_tsvector('english', body) FROM messages LIMIT 1;

SELECT to_tsquery('english', 'monday');

SELECT to_tsquery('english', 'neon') @@ to_tsvector('english', body)
FROM messages LIMIT 1;

SELECT to_tsquery('english', 'monday') @@ to_tsvector('english', body)
FROM messages LIMIT 1;

-- https://www.postgresql.org/docs/11/textsearch-indexes.html
CREATE INDEX messages_gin ON messages USING gin(to_tsvector('english', body));

SELECT subject, sender FROM messages
WHERE to_tsquery('english', 'monday') @@ to_tsvector('english', body);
EXPLAIN ANALYZE SELECT subject, sender FROM messages
WHERE to_tsquery('english', 'monday') @@ to_tsvector('english', body);

DROP INDEX messages_gin;
CREATE INDEX messages_gist ON messages USING gist(to_tsvector('english', body));
DROP INDEX messages_gist;

SELECT subject, sender FROM messages
WHERE to_tsquery('english', 'monday') @@ to_tsvector('english', body);
EXPLAIN ANALYZE SELECT subject, sender
FROM messages WHERE to_tsquery('english', 'monday') @@ to_tsvector('english', body);

-- https://www.postgresql.org/docs/11/functions-textsearch.html
SELECT id, subject, sender FROM messages
WHERE to_tsquery('english', 'personal & learning') @@ to_tsvector('english', body);

SELECT id, subject, sender FROM messages
WHERE to_tsquery('english', 'learning & personal') @@ to_tsvector('english', body);

SELECT id, subject, sender FROM messages
WHERE to_tsquery('english', 'personal <-> learning') @@ to_tsvector('english', body);

SELECT id, subject, sender FROM messages
WHERE to_tsquery('english', 'learning <-> personal') @@ to_tsvector('english', body);

SELECT id, subject, sender FROM messages
WHERE to_tsquery('english', '! personal & learning') @@ to_tsvector('english', body);

-- plainto_tsquery() Is tolerant of "syntax errors" in the expression
SELECT id, subject, sender FROM messages
WHERE to_tsquery('english', '(personal learning') @@ to_tsvector('english', body);

SELECT id, subject, sender FROM messages
WHERE plainto_tsquery('english', '(personal learning') @@ to_tsvector('english', body);

-- phraseto_tsquery() implies followed by
SELECT id, subject, sender FROM messages
WHERE to_tsquery('english', 'I <-> think') @@ to_tsvector('english', body);

SELECT id, subject, sender FROM messages
WHERE phraseto_tsquery('english', 'I think') @@ to_tsvector('english', body);

-- https://www.postgresql.org/docs/12/textsearch-controls.html#TEXTSEARCH-RANKING
SELECT id, subject, sender,
  ts_rank(to_tsvector('english', body), to_tsquery('english', 'personal & learning')) as ts_rank
FROM messages
WHERE to_tsquery('english', 'personal & learning') @@ to_tsvector('english', body)
ORDER BY ts_rank DESC;

-- A different ranking algorithm
SELECT id, subject, sender,
  ts_rank_cd(to_tsvector('english', body), to_tsquery('english', 'personal & learning')) as ts_rank
FROM messages
WHERE to_tsquery('english', 'personal & learning') @@ to_tsvector('english', body)
ORDER BY ts_rank DESC;

SELECT id, subject, sender FROM messages
WHERE to_tsquery('english', '! personal & learning') @@ to_tsvector('english', body);

-- websearch_to_tsquery is in PostgreSQL > 11
SELECT id, subject, sender FROM messages
WHERE websearch_to_tsquery('english', '-personal learning') @@ to_tsvector('english', body);

-- https://www.postgresql.org/docs/11/textsearch-indexes.html

--- GIN versus GIsT

-- Select version();   -- PostgreSQL 9.6.7
-- https://habr.com/en/company/postgrespro/blog/448746/

-- Check the operation types for the various indexes

SELECT am.amname AS index_method, opc.opcname AS opclass_name
    FROM pg_am am, pg_opclass opc
    WHERE opc.opcmethod = am.oid
    ORDER BY index_method, opclass_name;

