------------------------------------------------------------
-- PROJETO: DIREITO FACIL - CITIZENTECH (GLOBAL SOLUTION 2026/2)
-- DISCIPLINA: MASTERING RELATIONAL AND NON-RELATIONAL DATABASE
-- ARQUIVO: 04_BLOCOS_PLSQL.sql
-- DESCRICAO: 2 BLOCOS ANONIMOS PL/SQL COM CURSOR, REPETICAO E DECISAO
-- EXECUCAO: 4 - executar apos 03_CARGA.sql
------------------------------------------------------------

SET SERVEROUTPUT ON;

------------------------------------------------------------
-- BLOCO 1: perfil de cada pessoa (CURSOR + FOR LOOP + IF/ELSIF)
-- Classifica faixa etaria e faixa de renda per capita em fracao
-- do salario minimo (a mesma base usada pela funcao de elegibilidade).
------------------------------------------------------------
DECLARE
    CURSOR c_pessoas IS
        SELECT ID_PESSOA, NOME, DT_NASCIMENTO, VLR_RENDA_FAMILIAR, QTD_MEMBROS_FAMILIA
        FROM T_DF_PESSOA
        ORDER BY ID_PESSOA;

    v_sm        NUMBER;
    v_idade     NUMBER;
    v_fracao    NUMBER;
    v_faixa     VARCHAR2(30);
    v_renda     VARCHAR2(30);
BEGIN
    SELECT VLR_SALARIO_MINIMO INTO v_sm
    FROM T_DF_SALARIO_MINIMO
    WHERE ANO_REFERENCIA = (SELECT MAX(ANO_REFERENCIA) FROM T_DF_SALARIO_MINIMO);

    DBMS_OUTPUT.PUT_LINE('=== PERFIL DAS PESSOAS (data de referencia 05/11/2026) ===');
    FOR r IN c_pessoas LOOP
        v_idade  := TRUNC(MONTHS_BETWEEN(DATE '2026-11-05', r.DT_NASCIMENTO) / 12);
        v_fracao := ROUND((r.VLR_RENDA_FAMILIAR / r.QTD_MEMBROS_FAMILIA) / v_sm, 4);

        IF v_idade >= 65 THEN
            v_faixa := 'IDOSO 65+';
        ELSIF v_idade >= 60 THEN
            v_faixa := 'IDOSO 60-64';
        ELSIF v_idade >= 18 THEN
            v_faixa := 'ADULTO';
        ELSE
            v_faixa := 'CRIANCA/ADOLESCENTE';
        END IF;

        IF v_fracao <= 0.25 THEN
            v_renda := 'ATE 1/4 SM';
        ELSIF v_fracao <= 0.5 THEN
            v_renda := 'ATE 1/2 SM';
        ELSIF v_fracao <= 1 THEN
            v_renda := 'ATE 1 SM';
        ELSE
            v_renda := 'ACIMA DE 1 SM';
        END IF;

        DBMS_OUTPUT.PUT_LINE(RPAD(r.NOME, 18) || ' | idade ' || LPAD(v_idade, 2)
            || ' | ' || RPAD(v_faixa, 20)
            || ' | per capita ' || TO_CHAR(v_fracao, 'FM990D0000', 'NLS_NUMERIC_CHARACTERS=''.,''') || ' SM'
            || ' | ' || v_renda);
    END LOOP;
END;
/

------------------------------------------------------------
-- BLOCO 2: varredura dos laudos (WHILE LOOP + CASE + contadores)
-- Conta quantos laudos abrem direitos de PcD. Por lei (12.764/2012,
-- art. 1o, par. 2o), laudo de TEA conta como deficiencia.
------------------------------------------------------------
DECLARE
    v_i        NUMBER := 1;
    v_total    NUMBER;
    v_tipo     T_DF_LAUDO.TIPO_CONDICAO%TYPE;
    v_cid      T_DF_LAUDO.COD_CID%TYPE;
    v_pcd      NUMBER := 0;
    v_tea      NUMBER := 0;
    v_outra    NUMBER := 0;
    v_resumo   VARCHAR2(60);
BEGIN
    SELECT COUNT(*) INTO v_total FROM T_DF_LAUDO;
    DBMS_OUTPUT.PUT_LINE('=== LAUDOS (' || v_total || ') ===');

    WHILE v_i <= v_total LOOP
        SELECT TIPO_CONDICAO, COD_CID INTO v_tipo, v_cid
        FROM (SELECT TIPO_CONDICAO, COD_CID,
                     ROW_NUMBER() OVER (ORDER BY ID_LAUDO) AS RN
              FROM T_DF_LAUDO)
        WHERE RN = v_i;

        v_resumo := CASE v_tipo
                        WHEN 'TEA'  THEN 'abre direitos de PcD e de autismo'
                        WHEN 'OUTRA' THEN 'nao caracteriza deficiencia'
                        ELSE 'abre direitos de PcD'
                    END;

        IF v_tipo = 'TEA' THEN
            v_tea := v_tea + 1;
            v_pcd := v_pcd + 1;
        ELSIF v_tipo = 'OUTRA' THEN
            v_outra := v_outra + 1;
        ELSE
            v_pcd := v_pcd + 1;
        END IF;

        DBMS_OUTPUT.PUT_LINE('Laudo ' || v_i || ' | CID ' || RPAD(v_cid, 6) || ' | ' || v_resumo);
        v_i := v_i + 1;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Total PcD: ' || v_pcd || ' (sendo TEA: ' || v_tea || ') | Sem deficiencia: ' || v_outra);
END;
/
