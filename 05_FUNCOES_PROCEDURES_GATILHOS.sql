------------------------------------------------------------
-- PROJETO: DIREITO FACIL - CITIZENTECH (GLOBAL SOLUTION 2026/2)
-- DISCIPLINA: MASTERING RELATIONAL AND NON-RELATIONAL DATABASE
-- ARQUIVO: 05_FUNCOES_PROCEDURES_GATILHOS.sql
-- DESCRICAO: 2 FUNCOES + 3 PROCEDURES + 2 GATILHOS (1 COM AUDITORIA) + TESTES
-- EXECUCAO: 5 - executar apos 04_BLOCOS_PLSQL.sql
------------------------------------------------------------

SET SERVEROUTPUT ON;

------------------------------------------------------------
-- REGRA DE NEGOCIO CENTRAL: "A REGRA DECIDE, A IA EXPLICA"
-- A elegibilidade de cada direito e decidida aqui, em PL/SQL, a
-- partir da tabela T_DF_CRITERIO_DIREITO. Deterministica, testavel
-- e auditavel. A IA (Spring AI) so extrai dados do laudo e explica.
-- O parametro p_dt_ref (padrao SYSDATE) permite reproduzir os testes
-- com data fixa.
------------------------------------------------------------

------------------------------------------------------------
-- FUNCTION: FN_RENDA_PER_CAPITA_SM
------------------------------------------------------------
CREATE OR REPLACE FUNCTION FN_RENDA_PER_CAPITA_SM (
    p_id_pessoa IN NUMBER
) RETURN NUMBER
IS
    v_renda    T_DF_PESSOA.VLR_RENDA_FAMILIAR%TYPE;
    v_membros  T_DF_PESSOA.QTD_MEMBROS_FAMILIA%TYPE;
    v_sm       T_DF_SALARIO_MINIMO.VLR_SALARIO_MINIMO%TYPE;
BEGIN
    SELECT VLR_RENDA_FAMILIAR, QTD_MEMBROS_FAMILIA
    INTO v_renda, v_membros
    FROM T_DF_PESSOA
    WHERE ID_PESSOA = p_id_pessoa;

    SELECT VLR_SALARIO_MINIMO INTO v_sm
    FROM T_DF_SALARIO_MINIMO
    WHERE ANO_REFERENCIA = (SELECT MAX(ANO_REFERENCIA) FROM T_DF_SALARIO_MINIMO);

    RETURN ROUND((v_renda / v_membros) / v_sm, 4);
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20020, 'FN_RENDA_PER_CAPITA_SM: pessoa ou salario minimo nao encontrado');
    WHEN OTHERS THEN
        RAISE_APPLICATION_ERROR(-20021, 'FN_RENDA_PER_CAPITA_SM: erro inesperado - ' || SQLERRM);
END FN_RENDA_PER_CAPITA_SM;
/

------------------------------------------------------------
-- PROCEDURE: PRC_AVALIAR_DIREITO
------------------------------------------------------------
CREATE OR REPLACE PROCEDURE PRC_AVALIAR_DIREITO (
    p_id_pessoa  IN  NUMBER,
    p_id_direito IN  NUMBER,
    p_dt_ref     IN  DATE,
    p_status     OUT VARCHAR2,
    p_motivo     OUT VARCHAR2
)
IS
    v_dt_nasc  DATE;
    v_idade    NUMBER;
    v_pcd      NUMBER;
    v_tea      NUMBER;
    v_fracao   NUMBER;
    v_crit     T_DF_CRITERIO_DIREITO%ROWTYPE;
    v_txt_f    VARCHAR2(10);
    v_txt_l    VARCHAR2(10);
BEGIN
    SELECT DT_NASCIMENTO INTO v_dt_nasc
    FROM T_DF_PESSOA WHERE ID_PESSOA = p_id_pessoa;

    SELECT * INTO v_crit
    FROM T_DF_CRITERIO_DIREITO WHERE ID_DIREITO = p_id_direito;

    v_idade := TRUNC(MONTHS_BETWEEN(p_dt_ref, v_dt_nasc) / 12);

    -- Lei 12.764/2012, art. 1o, par. 2o: laudo de TEA conta como deficiencia
    SELECT COUNT(*) INTO v_pcd
    FROM T_DF_LAUDO
    WHERE ID_PESSOA = p_id_pessoa AND TIPO_CONDICAO <> 'OUTRA';

    SELECT COUNT(*) INTO v_tea
    FROM T_DF_LAUDO
    WHERE ID_PESSOA = p_id_pessoa AND TIPO_CONDICAO = 'TEA';

    v_fracao := FN_RENDA_PER_CAPITA_SM(p_id_pessoa);
    v_txt_f  := TO_CHAR(v_fracao, 'FM990D0000', 'NLS_NUMERIC_CHARACTERS=''.,''');
    v_txt_l  := TO_CHAR(v_crit.FRC_SM_MAX, 'FM990D0000', 'NLS_NUMERIC_CHARACTERS=''.,''');

    IF v_idade < v_crit.NUM_IDADE_MIN
       OR (v_crit.NUM_IDADE_MAX IS NOT NULL AND v_idade > v_crit.NUM_IDADE_MAX) THEN
        p_status := 'NAO_ELEGIVEL';
        p_motivo := 'Idade ' || v_idade || ' fora da faixa exigida';
    ELSIF v_crit.STA_EXIGE_TEA = 'S' AND v_tea = 0 THEN
        p_status := 'NAO_ELEGIVEL';
        p_motivo := 'Exige laudo de TEA (Lei 12.764/2012)';
    ELSIF v_crit.STA_EXIGE_PCD = 'S' AND v_pcd = 0 THEN
        p_status := 'NAO_ELEGIVEL';
        p_motivo := 'Exige laudo de deficiencia (PcD)';
    ELSIF v_crit.FRC_SM_MAX IS NULL THEN
        p_status := 'ELEGIVEL';
        p_motivo := 'Criterios atendidos (sem limite de renda)';
    ELSIF v_fracao <= v_crit.FRC_SM_MAX THEN
        p_status := 'ELEGIVEL';
        p_motivo := 'Renda per capita ' || v_txt_f || ' SM dentro do limite de ' || v_txt_l || ' SM';
    ELSIF v_fracao <= v_crit.FRC_SM_MAX * (1 + v_crit.PCT_TOLERANCIA / 100) THEN
        p_status := 'POSSIVEL';
        p_motivo := 'Renda per capita ' || v_txt_f || ' SM proxima do limite de ' || v_txt_l
                    || ' SM; confirmar renda no CadUnico';
    ELSE
        p_status := 'NAO_ELEGIVEL';
        p_motivo := 'Renda per capita ' || v_txt_f || ' SM acima do limite de ' || v_txt_l || ' SM';
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20022, 'PRC_AVALIAR_DIREITO: pessoa, direito ou criterio nao encontrado');
END PRC_AVALIAR_DIREITO;
/

------------------------------------------------------------
-- FUNCTION: FN_AVALIAR_ELEGIBILIDADE
------------------------------------------------------------
CREATE OR REPLACE FUNCTION FN_AVALIAR_ELEGIBILIDADE (
    p_id_pessoa   IN NUMBER,
    p_cod_direito IN VARCHAR2,
    p_dt_ref      IN DATE DEFAULT SYSDATE
) RETURN VARCHAR2
IS
    v_id_direito  T_DF_DIREITO.ID_DIREITO%TYPE;
    v_status      VARCHAR2(15);
    v_motivo      VARCHAR2(300);
BEGIN
    SELECT ID_DIREITO INTO v_id_direito
    FROM T_DF_DIREITO
    WHERE COD_DIREITO = UPPER(p_cod_direito);

    PRC_AVALIAR_DIREITO(p_id_pessoa, v_id_direito, p_dt_ref, v_status, v_motivo);
    RETURN v_status;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20023, 'FN_AVALIAR_ELEGIBILIDADE: direito ' || p_cod_direito || ' nao encontrado');
END FN_AVALIAR_ELEGIBILIDADE;
/

------------------------------------------------------------
-- PROCEDURE: PRC_ABRIR_CASOS
------------------------------------------------------------
CREATE OR REPLACE PROCEDURE PRC_ABRIR_CASOS (
    p_id_pessoa IN NUMBER,
    p_dt_ref    IN DATE DEFAULT SYSDATE
)
IS
    CURSOR c_direitos IS
        SELECT ID_DIREITO, COD_DIREITO, NUM_PRAZO_DIAS
        FROM T_DF_DIREITO
        ORDER BY ID_DIREITO;

    v_status    VARCHAR2(15);
    v_motivo    VARCHAR2(300);
    v_ja_existe NUMBER;
    v_abertos   NUMBER := 0;
    v_erro      VARCHAR2(4000);
    v_codigo    NUMBER;
BEGIN
    FOR r IN c_direitos LOOP
        PRC_AVALIAR_DIREITO(p_id_pessoa, r.ID_DIREITO, p_dt_ref, v_status, v_motivo);

        IF v_status IN ('ELEGIVEL', 'POSSIVEL') THEN
            SELECT COUNT(*) INTO v_ja_existe
            FROM T_DF_CASO
            WHERE ID_PESSOA = p_id_pessoa AND ID_DIREITO = r.ID_DIREITO;

            IF v_ja_existe = 0 THEN
                INSERT INTO T_DF_CASO (ID_PESSOA, ID_DIREITO, STATUS, RESULTADO_AVALIACAO,
                                        DES_MOTIVO, DT_ABERTURA, DT_PRAZO, DT_ATUALIZACAO)
                VALUES (p_id_pessoa, r.ID_DIREITO, 'ABERTO', v_status,
                        v_motivo, p_dt_ref, p_dt_ref + r.NUM_PRAZO_DIAS, p_dt_ref);
                v_abertos := v_abertos + 1;
            END IF;
        END IF;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Pessoa ' || p_id_pessoa || ': ' || v_abertos || ' caso(s) aberto(s)');
EXCEPTION
    WHEN OTHERS THEN
        v_codigo := SQLCODE;
        v_erro   := SQLERRM;
        INSERT INTO T_DF_LOG_ERRO (NOME_PROCEDURE, CODIGO_ERRO, MENSAGEM_ERRO, DATA_ERRO, USUARIO_BANCO)
        VALUES ('PRC_ABRIR_CASOS', v_codigo, v_erro, SYSDATE, USER);
        DBMS_OUTPUT.PUT_LINE('Erro [' || v_codigo || ']: ' || v_erro);
END PRC_ABRIR_CASOS;
/

------------------------------------------------------------
-- PROCEDURE: PRC_ATUALIZAR_STATUS_CASO
------------------------------------------------------------
CREATE OR REPLACE PROCEDURE PRC_ATUALIZAR_STATUS_CASO (
    p_id_caso     IN NUMBER,
    p_novo_status IN VARCHAR2,
    p_dt_ref      IN DATE DEFAULT SYSDATE
)
IS
    v_erro     VARCHAR2(4000);
    v_codigo   NUMBER;
BEGIN
    UPDATE T_DF_CASO
    SET STATUS = UPPER(p_novo_status),
        DT_ATUALIZACAO = p_dt_ref
    WHERE ID_CASO = p_id_caso;

    IF SQL%ROWCOUNT = 0 THEN
        RAISE_APPLICATION_ERROR(-20040, 'Caso ' || p_id_caso || ' nao encontrado');
    END IF;

    DBMS_OUTPUT.PUT_LINE('Caso ' || p_id_caso || ' -> ' || UPPER(p_novo_status));
EXCEPTION
    WHEN OTHERS THEN
        v_codigo := SQLCODE;
        v_erro   := SQLERRM;
        INSERT INTO T_DF_LOG_ERRO (NOME_PROCEDURE, CODIGO_ERRO, MENSAGEM_ERRO, DATA_ERRO, USUARIO_BANCO)
        VALUES ('PRC_ATUALIZAR_STATUS_CASO', v_codigo, v_erro, SYSDATE, USER);
        RAISE;
END PRC_ATUALIZAR_STATUS_CASO;
/

------------------------------------------------------------
-- GATILHO 1: TRG_DF_CASO_VALIDA (BEFORE INSERT OR UPDATE)
-- Valida o fluxo de status e o prazo do caso.
------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_DF_CASO_VALIDA
BEFORE INSERT OR UPDATE ON T_DF_CASO
FOR EACH ROW
BEGIN
    -- regra 1: prazo nunca anterior a abertura
    IF :NEW.DT_PRAZO < :NEW.DT_ABERTURA THEN
        RAISE_APPLICATION_ERROR(-20034, 'Prazo do caso nao pode ser anterior a data de abertura');
    END IF;

    -- regra 2: todo caso nasce ABERTO
    IF INSERTING AND :NEW.STATUS <> 'ABERTO' THEN
        RAISE_APPLICATION_ERROR(-20031, 'Caso novo deve ser criado com status ABERTO');
    END IF;

    -- regra 3: fluxo de status
    --   ABERTO / EM_ANALISE / DOCUMENTOS_PENDENTES -> avancam entre si ou para PROTOCOLADO
    --   PROTOCOLADO -> somente CONCEDIDO ou NEGADO
    --   CONCEDIDO / NEGADO -> estados finais (nao mudam mais)
    IF UPDATING AND :OLD.STATUS <> :NEW.STATUS THEN
        IF :OLD.STATUS IN ('CONCEDIDO', 'NEGADO') THEN
            RAISE_APPLICATION_ERROR(-20032, 'Caso ' || :OLD.STATUS || ' e final e nao pode mudar de status');
        ELSIF :OLD.STATUS = 'PROTOCOLADO' THEN
            IF :NEW.STATUS NOT IN ('CONCEDIDO', 'NEGADO') THEN
                RAISE_APPLICATION_ERROR(-20033, 'De PROTOCOLADO so e permitido CONCEDIDO ou NEGADO');
            END IF;
        ELSE
            IF :NEW.STATUS IN ('CONCEDIDO', 'NEGADO', 'ABERTO') THEN
                RAISE_APPLICATION_ERROR(-20033, 'Transicao invalida: ' || :OLD.STATUS || ' -> ' || :NEW.STATUS
                    || ' (e preciso passar por PROTOCOLADO)');
            END IF;
        END IF;
    END IF;
END;
/

------------------------------------------------------------
-- GATILHO 2: TRG_DF_AUDITORIA_CASO (AFTER INSERT OR UPDATE OR DELETE)
-- Trilha de auditoria: usuario, data, operacao, valores antigo/novo.
------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_DF_AUDITORIA_CASO
AFTER INSERT OR UPDATE OR DELETE ON T_DF_CASO
FOR EACH ROW
DECLARE
    v_tipo     VARCHAR2(10);
    v_anterior VARCHAR2(1000);
    v_novo     VARCHAR2(1000);
    v_st_ant   VARCHAR2(25);
    v_st_novo  VARCHAR2(25);
    v_id_ref   NUMBER;
BEGIN
    IF INSERTING THEN
        v_tipo     := 'INSERT';
        v_id_ref   := :NEW.ID_CASO;
        v_st_novo  := :NEW.STATUS;
        v_novo     := 'PESSOA=' || :NEW.ID_PESSOA || ';DIREITO=' || :NEW.ID_DIREITO
                      || ';STATUS=' || :NEW.STATUS || ';RESULTADO=' || :NEW.RESULTADO_AVALIACAO
                      || ';PRAZO=' || TO_CHAR(:NEW.DT_PRAZO, 'YYYY-MM-DD');
    ELSIF UPDATING THEN
        v_tipo     := 'UPDATE';
        v_id_ref   := :NEW.ID_CASO;
        v_st_ant   := :OLD.STATUS;
        v_st_novo  := :NEW.STATUS;
        v_anterior := 'STATUS=' || :OLD.STATUS || ';PRAZO=' || TO_CHAR(:OLD.DT_PRAZO, 'YYYY-MM-DD');
        v_novo     := 'STATUS=' || :NEW.STATUS || ';PRAZO=' || TO_CHAR(:NEW.DT_PRAZO, 'YYYY-MM-DD');
    ELSIF DELETING THEN
        v_tipo     := 'DELETE';
        v_id_ref   := :OLD.ID_CASO;
        v_st_ant   := :OLD.STATUS;
        v_anterior := 'PESSOA=' || :OLD.ID_PESSOA || ';DIREITO=' || :OLD.ID_DIREITO
                      || ';STATUS=' || :OLD.STATUS;
    END IF;

    INSERT INTO T_DF_AUDITORIA_CASO (NOME_USUARIO, TIPO_OPERACAO, ID_CASO_REF, STATUS_ANTERIOR,
                                      STATUS_NOVO, VALORES_ANTERIORES, VALORES_NOVOS)
    VALUES (USER, v_tipo, v_id_ref, v_st_ant, v_st_novo, v_anterior, v_novo);
END;
/

------------------------------------------------------------
-- CARGA DOS CASOS: avalia as 15 regras para cada pessoa e abre um caso
-- para cada direito ELEGIVEL ou POSSIVEL (data de referencia fixa)
------------------------------------------------------------
BEGIN
    PRC_ABRIR_CASOS(1, DATE '2026-11-05');
    PRC_ABRIR_CASOS(2, DATE '2026-11-05');
    PRC_ABRIR_CASOS(3, DATE '2026-11-05');
    PRC_ABRIR_CASOS(4, DATE '2026-11-05');
    PRC_ABRIR_CASOS(5, DATE '2026-11-05');
    COMMIT;
END;
/

------------------------------------------------------------
-- ANDAMENTO DOS CASOS: atualiza status via procedure (dispara os gatilhos)
------------------------------------------------------------
DECLARE
    PROCEDURE atualiza (p_pessoa IN NUMBER, p_cod IN VARCHAR2, p_status IN VARCHAR2, p_data IN DATE) IS
        v_id NUMBER;
    BEGIN
        SELECT c.ID_CASO INTO v_id
        FROM T_DF_CASO c
        JOIN T_DF_DIREITO d ON d.ID_DIREITO = c.ID_DIREITO
        WHERE c.ID_PESSOA = p_pessoa AND d.COD_DIREITO = p_cod;
        PRC_ATUALIZAR_STATUS_CASO(v_id, p_status, p_data);
    END;
BEGIN
    atualiza(1, 'BPC_PCD', 'EM_ANALISE', DATE '2026-11-06');
    atualiza(1, 'BPC_PCD', 'DOCUMENTOS_PENDENTES', DATE '2026-11-07');
    atualiza(1, 'CIPTEA', 'PROTOCOLADO', DATE '2026-11-06');
    atualiza(1, 'CIPTEA', 'CONCEDIDO', DATE '2026-11-08');
    atualiza(2, 'ISENCAO_IPI_VEICULO_PCD', 'EM_ANALISE', DATE '2026-11-06');
    atualiza(3, 'BPC_IDOSO', 'PROTOCOLADO', DATE '2026-11-06');
    atualiza(3, 'TARIFA_SOCIAL_ENERGIA', 'PROTOCOLADO', DATE '2026-11-06');
    atualiza(3, 'TARIFA_SOCIAL_ENERGIA', 'CONCEDIDO', DATE '2026-11-07');
    atualiza(5, 'BPC_IDOSO', 'DOCUMENTOS_PENDENTES', DATE '2026-11-06');
    atualiza(5, 'CADUNICO', 'PROTOCOLADO', DATE '2026-11-06');
    atualiza(5, 'CADUNICO', 'NEGADO', DATE '2026-11-08');
    COMMIT;
END;
/

------------------------------------------------------------
-- TESTES (gerar prints para o PDF/apresentacao)
------------------------------------------------------------

-- Teste 1: matriz de elegibilidade (funcao chamada direto no SELECT)
SELECT p.NOME,
       d.COD_DIREITO,
       FN_AVALIAR_ELEGIBILIDADE(p.ID_PESSOA, d.COD_DIREITO, DATE '2026-11-05') AS RESULTADO
FROM T_DF_PESSOA p
CROSS JOIN T_DF_DIREITO d
WHERE p.ID_PESSOA IN (1, 2, 3)
ORDER BY p.ID_PESSOA, d.ID_DIREITO;

-- Teste 2: funcao com motivo (procedure de avaliacao) - caso POSSIVEL (Rita x BPC_IDOSO)
DECLARE
    v_status VARCHAR2(15);
    v_motivo VARCHAR2(300);
BEGIN
    PRC_AVALIAR_DIREITO(5, 1, DATE '2026-11-05', v_status, v_motivo);
    DBMS_OUTPUT.PUT_LINE(v_status || ' - ' || v_motivo);
    -- teste negativo: Marcos (sem deficiencia) x BPC_PCD
    PRC_AVALIAR_DIREITO(4, 2, DATE '2026-11-05', v_status, v_motivo);
    DBMS_OUTPUT.PUT_LINE(v_status || ' - ' || v_motivo);
END;
/

-- Teste 3: erro tratado na funcao (direito inexistente)
BEGIN
    DBMS_OUTPUT.PUT_LINE(FN_AVALIAR_ELEGIBILIDADE(1, 'DIREITO_INEXISTENTE', DATE '2026-11-05'));
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Erro tratado: ' || SQLERRM);
END;
/

-- Teste 4: gatilho de validacao - transicao invalida (caso CONCEDIDO nao volta a ABERTO)
DECLARE
    v_id NUMBER;
BEGIN
    SELECT c.ID_CASO INTO v_id
    FROM T_DF_CASO c JOIN T_DF_DIREITO d ON d.ID_DIREITO = c.ID_DIREITO
    WHERE c.ID_PESSOA = 1 AND d.COD_DIREITO = 'CIPTEA';
    PRC_ATUALIZAR_STATUS_CASO(v_id, 'ABERTO', DATE '2026-11-09');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Erro tratado: ' || SQLERRM);
END;
/

-- Teste 5: trilha de auditoria (ultimas operacoes)
SELECT ID_AUDITORIA, NOME_USUARIO, TIPO_OPERACAO, DATA_OPERACAO, ID_CASO_REF,
       STATUS_ANTERIOR, STATUS_NOVO
FROM T_DF_AUDITORIA_CASO
ORDER BY ID_AUDITORIA DESC
FETCH FIRST 8 ROWS ONLY;

-- Teste 6: idempotencia do documento - o mesmo evento entregue duas vezes nao cria segundo registro
BEGIN
    PRC_CARGA_DOCUMENTO(1, 'dotnet-doc-0001', 'laudo_lucas_almeida.jpg', 'image/jpeg', 482113, 'demo-idem-0001', 'RECEBIDO', SYSDATE, NULL);
END;
/
SELECT COUNT(*) AS DOCUMENTOS_COM_A_CHAVE FROM T_DF_DOCUMENTO WHERE DES_CHAVE_IDEMPOTENCIA = 'demo-idem-0001';

-- Teste 7: log de erros gravado pelas procedures (deve conter os erros dos testes 4 e 6)
SELECT ID_LOG, NOME_PROCEDURE, CODIGO_ERRO, SUBSTR(MENSAGEM_ERRO, 1, 80) AS MENSAGEM
FROM T_DF_LOG_ERRO
ORDER BY ID_LOG;
