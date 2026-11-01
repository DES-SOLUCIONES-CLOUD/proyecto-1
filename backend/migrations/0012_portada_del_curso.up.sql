-- Portada que el profesor elige para su curso.
--
-- 0 es "automatica": el frontend escoge un color a partir del titulo.
-- 1 a 8 son las portadas de colores que se pueden elegir al crear el curso.
ALTER TABLE course_versions
  ADD COLUMN portada SMALLINT NOT NULL DEFAULT 0
  CHECK (portada BETWEEN 0 AND 8);
