------------------------------------------------------------
-- PROJETO: DIREITO FACIL - CITIZENTECH (GLOBAL SOLUTION 2026/2)
-- DISCIPLINA: MASTERING RELATIONAL AND NON-RELATIONAL DATABASE
-- ARQUIVO: 07_RELATORIOS_ORACLE.sql
-- DESCRICAO: 3 RELATORIOS RELACIONAIS EQUIVALENTES AS 3 CONSULTAS DO MONGODB
-- EXECUCAO: 7 - executar apos 06_PACKAGES.sql
------------------------------------------------------------

SET SERVEROUTPUT ON;

------------------------------------------------------------
-- RELATORIO 1 (equivale ao find #1 do MongoDB)
-- Direitos ELEGIVEIS de Lucas Almeida (pessoa 1), na ordem do catalogo
------------------------------------------------------------
SELECT c.ID_CASO, d.COD_DIREITO, c.STATUS
FROM T_DF_CASO c
JOIN T_DF_DIREITO d ON d.ID_DIREITO = c.ID_DIREITO
WHERE c.ID_PESSOA = 1
  AND c.RESULTADO_AVALIACAO = 'ELEGIVEL'
ORDER BY d.ID_DIREITO;

------------------------------------------------------------
-- RELATORIO 2 (equivale ao find #2 do MongoDB)
-- Casos ainda em andamento com prazo ate 05/12/2026 (painel do assistente social)
------------------------------------------------------------
SELECT c.ID_CASO, p.NOME, d.COD_DIREITO, c.STATUS, TO_CHAR(c.DT_PRAZO, 'YYYY-MM-DD') AS PRAZO
FROM T_DF_CASO c
JOIN T_DF_PESSOA p ON p.ID_PESSOA = c.ID_PESSOA
JOIN T_DF_DIREITO d ON d.ID_DIREITO = c.ID_DIREITO
WHERE c.STATUS IN ('ABERTO', 'EM_ANALISE', 'DOCUMENTOS_PENDENTES')
  AND c.DT_PRAZO <= DATE '2026-12-05'
ORDER BY c.DT_PRAZO, c.ID_CASO;

------------------------------------------------------------
-- RELATORIO 3 (equivale a AGREGACAO do MongoDB)
-- Panorama por pessoa: total de casos, elegiveis, possiveis e concedidos
------------------------------------------------------------
SELECT p.NOME,
       COUNT(*) AS TOTAL_CASOS,
       SUM(CASE WHEN c.RESULTADO_AVALIACAO = 'ELEGIVEL' THEN 1 ELSE 0 END) AS ELEGIVEIS,
       SUM(CASE WHEN c.RESULTADO_AVALIACAO = 'POSSIVEL' THEN 1 ELSE 0 END) AS POSSIVEIS,
       SUM(CASE WHEN c.STATUS = 'CONCEDIDO' THEN 1 ELSE 0 END) AS CONCEDIDOS
FROM T_DF_CASO c
JOIN T_DF_PESSOA p ON p.ID_PESSOA = c.ID_PESSOA
GROUP BY p.NOME
ORDER BY TOTAL_CASOS DESC, p.NOME;

------------------------------------------------------------
-- COMPARACAO RAPIDA: total de casos e de laudos (deve bater com o MongoDB)
------------------------------------------------------------
SELECT (SELECT COUNT(*) FROM T_DF_CASO)  AS TOTAL_CASOS,
       (SELECT COUNT(*) FROM T_DF_LAUDO) AS TOTAL_LAUDOS
FROM DUAL;
