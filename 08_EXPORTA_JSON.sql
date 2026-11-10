------------------------------------------------------------
-- PROJETO: DIREITO FACIL - CITIZENTECH (GLOBAL SOLUTION 2026/2)
-- DISCIPLINA: MASTERING RELATIONAL AND NON-RELATIONAL DATABASE
-- ARQUIVO: 08_EXPORTA_JSON.sql
-- DESCRICAO: EXPORTA OS CASOS DO ORACLE COMO JSON MANUAL (PONTE PARA O MONGODB)
-- EXECUCAO: 8 - opcional; executar apos 06_PACKAGES.sql
------------------------------------------------------------

-- O JSON e montado manualmente por PKG_CASOS.FN_CASO_TO_JSON (sem JSON_OBJECT/TO_JSON).
-- Cada linha gerada e um documento da collection "casos" do MongoDB.
-- Para gravar em arquivo no SQL*Plus / SQL Developer (Script Output):
--   SPOOL casos.json
--   (rode o EXEC abaixo)
--   SPOOL OFF
-- Depois: mongoimport --db citizentech --collection casos --file casos.json --jsonArray
-- (a parte MongoDB do projeto carrega esses mesmos 31 documentos pelos scripts da pasta mongo/)

SET SERVEROUTPUT ON SIZE UNLIMITED;
SET LINESIZE 4000;
SET TRIMSPOOL ON;
SET FEEDBACK OFF;

EXEC PKG_CASOS.PRC_EXPORTA_CASOS_JSON;
