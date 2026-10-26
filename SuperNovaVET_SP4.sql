-- =====================================================================
-- SuperNova Vet (CLYVO VET) - Challenge 2026 - 2 semestre
-- Mastering Relational and Non-Relational Database - Sprint 4
-- Felipe Augusto Lopes Ferreira - RM563982
-- Kaique Mascarenhas dos Santos - RM565802
--
-- O que mudou da Sprint 3 para a Sprint 4:
--  * Functions, procedures e a logica das triggers foram EMPACOTADAS em
--    PACKAGES (modularidade e reutilizacao).
--  * pkg_log: registro de erros com PRAGMA AUTONOMOUS_TRANSACTION (antes
--    havia COMMIT dentro de function chamada via SELECT, o que da ORA-14551).
--  * pkg_pet_app: procedures de CRUD que o backend Java chama.
--  * pkg_pet_json: gera o dataset JSON (manual, sem funcoes JSON do Oracle)
--    que sera importado no MongoDB.
--  * Obs.: no Oracle o TRIGGER nao pode ficar dentro do package; ele
--    continua como objeto separado, mas so CHAMA os packages.
--
-- Ordem: 1) tabelas  2) packages  3) trigger de risco  4) inserts
--        5) trigger de auditoria  6) testes (prints / video)
-- Rodar num schema limpo. Para refazer, descomente a secao 0.
-- =====================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED;

-- ---------------------------------------------------------------
-- 0) LIMPEZA (opcional) - descomente para refazer tudo do zero
-- ---------------------------------------------------------------
-- DROP TRIGGER trg_auditoria_pet;
-- DROP TRIGGER trg_definir_risco_pet;
-- DROP PACKAGE pkg_pet_app;
-- DROP PACKAGE pkg_pet_auditoria;
-- DROP PACKAGE pkg_pet_relatorio;
-- DROP PACKAGE pkg_pet_json;
-- DROP PACKAGE pkg_pet_regras;
-- DROP PACKAGE pkg_log;
-- -- objetos "soltos" da Sprint 3 (agora vivem dentro dos packages):
-- DROP FUNCTION fn_montar_json_pet;
-- DROP FUNCTION fn_classificar_risco_por_idade;
-- DROP PROCEDURE pr_listar_pets_tutores_json;
-- DROP PROCEDURE pr_relatorio_peso_tutor_especie;
-- DROP TABLE ch_pet_auditoria PURGE;
-- DROP TABLE ch_log_erro PURGE;
-- DROP TABLE ch_lembrete PURGE;
-- DROP TABLE ch_medicamento PURGE;
-- DROP TABLE ch_consulta PURGE;
-- DROP TABLE ch_vacina PURGE;
-- DROP TABLE ch_pet PURGE;
-- DROP TABLE ch_tutor PURGE;

-- ---------------------------------------------------------------
-- 1) CREATE TABLE (modelo relacional da Sprint 3)
-- ---------------------------------------------------------------
CREATE TABLE ch_tutor (
    id_tutor    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nm_tutor    VARCHAR2(100) NOT NULL,
    ds_email    VARCHAR2(100) NOT NULL UNIQUE,
    nr_telefone VARCHAR2(20)
);

CREATE TABLE ch_pet (
    id_pet         NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nm_pet         VARCHAR2(100) NOT NULL,
    ds_especie     VARCHAR2(50) NOT NULL,
    ds_raca        VARCHAR2(50),
    nr_idade       NUMBER,
    nr_peso        NUMBER(5,2),
    ds_sexo        CHAR(1),
    id_tutor       NUMBER NOT NULL,
    ds_nivel_risco VARCHAR2(20),
    CONSTRAINT fk_pet_tutor FOREIGN KEY (id_tutor) REFERENCES ch_tutor(id_tutor)
);

CREATE TABLE ch_vacina (
    id_vacina       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nm_vacina       VARCHAR2(100) NOT NULL,
    dt_aplicacao    DATE NOT NULL,
    dt_proxima_dose DATE,
    id_pet          NUMBER NOT NULL,
    CONSTRAINT fk_vacina_pet FOREIGN KEY (id_pet) REFERENCES ch_pet(id_pet)
);

CREATE TABLE ch_consulta (
    id_consulta    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dt_consulta    DATE NOT NULL,
    ds_consulta    VARCHAR2(300),
    nm_veterinario VARCHAR2(100),
    id_pet         NUMBER NOT NULL,
    CONSTRAINT fk_consulta_pet FOREIGN KEY (id_pet) REFERENCES ch_pet(id_pet)
);

CREATE TABLE ch_medicamento (
    id_medicamento NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nm_medicamento VARCHAR2(100) NOT NULL,
    ds_dosagem     VARCHAR2(50),
    ds_horario     VARCHAR2(50),
    dt_inicio      DATE,
    dt_fim         DATE,
    id_pet         NUMBER NOT NULL,
    CONSTRAINT fk_medicamento_pet FOREIGN KEY (id_pet) REFERENCES ch_pet(id_pet)
);

CREATE TABLE ch_lembrete (
    id_lembrete  NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ds_mensagem  VARCHAR2(300) NOT NULL,
    dt_lembrete  DATE NOT NULL,
    ds_status    VARCHAR2(20),
    id_pet       NUMBER NOT NULL,
    CONSTRAINT fk_lembrete_pet FOREIGN KEY (id_pet) REFERENCES ch_pet(id_pet)
);

CREATE TABLE ch_log_erro (
    id_log         NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nm_procedure   VARCHAR2(100),
    nm_usuario_bd  VARCHAR2(100),
    dt_erro        DATE,
    cd_erro        NUMBER,
    ds_erro        VARCHAR2(4000)
);

CREATE TABLE ch_pet_auditoria (
    id_auditoria       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nm_usuario         VARCHAR2(100),
    tp_operacao        VARCHAR2(10),
    dt_operacao        DATE,
    ds_valores_antigos VARCHAR2(500),
    ds_valores_novos   VARCHAR2(500)
);

-- =====================================================================
-- 2) PACKAGES
-- =====================================================================

-- ---------------------------------------------------------------
-- 2.1) PKG_LOG - registro de erros
-- AUTONOMOUS_TRANSACTION: o COMMIT do log nao mexe na transacao de quem
-- chamou (e pode ser usado dentro de function chamada por SELECT).
-- ---------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_log AS
    PROCEDURE pr_registrar_erro (
        p_origem  IN VARCHAR2,
        p_cd_erro IN NUMBER,
        p_ds_erro IN VARCHAR2
    );
END pkg_log;
/

CREATE OR REPLACE PACKAGE BODY pkg_log AS
    PROCEDURE pr_registrar_erro (
        p_origem  IN VARCHAR2,
        p_cd_erro IN NUMBER,
        p_ds_erro IN VARCHAR2
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO ch_log_erro (nm_procedure, nm_usuario_bd, dt_erro, cd_erro, ds_erro)
        VALUES (p_origem, SYS_CONTEXT('USERENV','SESSION_USER'), SYSDATE, p_cd_erro, SUBSTR(p_ds_erro, 1, 4000));
        COMMIT;
    END pr_registrar_erro;
END pkg_log;
/

-- ---------------------------------------------------------------
-- 2.2) PKG_PET_REGRAS - regras de negocio (Function 2 da Sprint 3)
-- ---------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_pet_regras AS
    -- faixas de idade usadas na classificacao de risco
    gc_idade_risco_alto  CONSTANT NUMBER := 7;
    gc_idade_risco_medio CONSTANT NUMBER := 4;

    FUNCTION fn_classificar_risco_por_idade (p_nr_idade IN NUMBER) RETURN VARCHAR2;
END pkg_pet_regras;
/

CREATE OR REPLACE PACKAGE BODY pkg_pet_regras AS

    -- Trata 3 excecoes: idade nula, idade negativa e OTHERS
    FUNCTION fn_classificar_risco_por_idade (p_nr_idade IN NUMBER) RETURN VARCHAR2 IS
        e_idade_nula     EXCEPTION;
        e_idade_negativa EXCEPTION;
    BEGIN
        IF p_nr_idade IS NULL THEN
            RAISE e_idade_nula;
        END IF;
        IF p_nr_idade < 0 THEN
            RAISE e_idade_negativa;
        END IF;

        IF p_nr_idade >= gc_idade_risco_alto THEN
            RETURN 'ALTO';
        ELSIF p_nr_idade >= gc_idade_risco_medio THEN
            RETURN 'MEDIO';
        ELSE
            RETURN 'BAIXO';
        END IF;
    EXCEPTION
        WHEN e_idade_nula THEN
            RETURN 'NAO_DEFINIDO';
        WHEN e_idade_negativa THEN
            RETURN 'IDADE_INVALIDA';
        WHEN OTHERS THEN
            pkg_log.pr_registrar_erro('pkg_pet_regras.fn_classificar_risco_por_idade', SQLCODE, SQLERRM);
            RETURN 'ERRO';
    END fn_classificar_risco_por_idade;

END pkg_pet_regras;
/

-- ---------------------------------------------------------------
-- 2.3) PKG_PET_JSON - relacional -> JSON (manual, sem JSON_OBJECT etc.)
--   fn_montar_json_pet          : Function 1 da Sprint 3
--   pr_listar_pets_tutores_json : Procedure 1 da Sprint 3 (JOIN + JSON)
--   fn_exportar_dataset_json    : dataset completo (1 documento por pet,
--                                 com tutor, vacinas, consultas,
--                                 medicamentos e lembretes aninhados)
--   pr_exportar_dataset_json    : imprime o dataset (1 documento por linha)
-- ---------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_pet_json AS
    FUNCTION fn_montar_json_pet (
        p_nm_pet      IN VARCHAR2,
        p_ds_especie  IN VARCHAR2,
        p_nivel_risco IN VARCHAR2,
        p_nm_tutor    IN VARCHAR2,
        p_ds_email    IN VARCHAR2
    ) RETURN VARCHAR2;

    PROCEDURE pr_listar_pets_tutores_json;

    FUNCTION fn_exportar_dataset_json RETURN CLOB;

    PROCEDURE pr_exportar_dataset_json;
END pkg_pet_json;
/

CREATE OR REPLACE PACKAGE BODY pkg_pet_json AS

    -- ---------- helpers privados (formatam um valor como JSON) ----------
    FUNCTION fn_texto (p_valor IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        IF p_valor IS NULL THEN
            RETURN 'null';
        END IF;
        RETURN '"' ||
               REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(p_valor,
                   '\', '\\'), '"', '\"'), CHR(10), '\n'), CHR(13), '\r'), CHR(9), '\t')
               || '"';
    END fn_texto;

    FUNCTION fn_numero (p_valor IN NUMBER) RETURN VARCHAR2 IS
        v_txt VARCHAR2(60);
    BEGIN
        IF p_valor IS NULL THEN
            RETURN 'null';
        END IF;
        -- NLS fixo com ponto decimal (JSON nao aceita virgula)
        v_txt := TO_CHAR(p_valor, 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,''');
        -- TM remove o zero a esquerda (.5) -> JSON exige 0.5
        IF SUBSTR(v_txt, 1, 1) = '.' THEN
            v_txt := '0' || v_txt;
        ELSIF SUBSTR(v_txt, 1, 2) = '-.' THEN
            v_txt := '-0' || SUBSTR(v_txt, 2);
        END IF;
        RETURN v_txt;
    END fn_numero;

    FUNCTION fn_data (p_valor IN DATE) RETURN VARCHAR2 IS
    BEGIN
        IF p_valor IS NULL THEN
            RETURN 'null';
        END IF;
        RETURN '"' || TO_CHAR(p_valor, 'YYYY-MM-DD') || '"';
    END fn_data;

    -- ---------- Function 1: monta o JSON de uma linha (pet + tutor) ----------
    -- Trata 3 excecoes: parametro obrigatorio nulo, JSON acima do limite, OTHERS
    FUNCTION fn_montar_json_pet (
        p_nm_pet      IN VARCHAR2,
        p_ds_especie  IN VARCHAR2,
        p_nivel_risco IN VARCHAR2,
        p_nm_tutor    IN VARCHAR2,
        p_ds_email    IN VARCHAR2
    ) RETURN VARCHAR2 IS
        v_json VARCHAR2(32767);
        e_parametro_obrigatorio_nulo EXCEPTION;
        e_json_excedeu_limite        EXCEPTION;
    BEGIN
        IF p_nm_pet IS NULL OR p_nm_tutor IS NULL THEN
            RAISE e_parametro_obrigatorio_nulo;
        END IF;

        v_json := '{'
            || '"pet":'         || fn_texto(p_nm_pet)                       || ','
            || '"especie":'     || fn_texto(p_ds_especie)                   || ','
            || '"nivel_risco":' || fn_texto(NVL(p_nivel_risco, 'NAO_DEFINIDO')) || ','
            || '"tutor":'       || fn_texto(p_nm_tutor)                     || ','
            || '"email":'       || fn_texto(p_ds_email)
            || '}';

        IF LENGTH(v_json) > 4000 THEN
            RAISE e_json_excedeu_limite;
        END IF;

        RETURN v_json;
    EXCEPTION
        WHEN e_parametro_obrigatorio_nulo THEN
            RETURN '{"erro":"nome do pet ou do tutor esta nulo"}';
        WHEN e_json_excedeu_limite THEN
            RETURN '{"erro":"json excedeu o tamanho maximo permitido"}';
        WHEN OTHERS THEN
            pkg_log.pr_registrar_erro('pkg_pet_json.fn_montar_json_pet', SQLCODE, SQLERRM);
            RETURN '{"erro":"falha inesperada ao montar json"}';
    END fn_montar_json_pet;

    -- ---------- Procedure 1: JOIN ch_pet + ch_tutor -> array JSON ----------
    -- Trata 3 excecoes: NO_DATA_FOUND, VALUE_ERROR e OTHERS
    PROCEDURE pr_listar_pets_tutores_json IS
        CURSOR c_pets_tutores IS
            SELECT p.nm_pet, p.ds_especie, p.ds_nivel_risco, t.nm_tutor, t.ds_email
            FROM   ch_pet p
            INNER JOIN ch_tutor t ON p.id_tutor = t.id_tutor
            ORDER BY p.id_pet;

        v_json_array VARCHAR2(32767) := '[';
        v_separador  VARCHAR2(1)     := '';
        v_qtd_linhas NUMBER          := 0;
    BEGIN
        FOR r_pet IN c_pets_tutores LOOP
            v_json_array := v_json_array || v_separador || fn_montar_json_pet(
                r_pet.nm_pet, r_pet.ds_especie, r_pet.ds_nivel_risco, r_pet.nm_tutor, r_pet.ds_email);
            v_separador  := ',';
            v_qtd_linhas := v_qtd_linhas + 1;
        END LOOP;

        v_json_array := v_json_array || ']';

        IF v_qtd_linhas = 0 THEN
            RAISE NO_DATA_FOUND;
        END IF;

        DBMS_OUTPUT.PUT_LINE(v_json_array);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('Nenhum pet/tutor encontrado para montar o JSON.');
        WHEN VALUE_ERROR THEN
            DBMS_OUTPUT.PUT_LINE('Erro de conversao de valores ao montar o JSON.');
        WHEN OTHERS THEN
            pkg_log.pr_registrar_erro('pkg_pet_json.pr_listar_pets_tutores_json', SQLCODE, SQLERRM);
            RAISE;
    END pr_listar_pets_tutores_json;

    -- ---------- Dataset completo para o MongoDB ----------
    -- 1 documento por pet, com tutor (embutido) e listas embutidas.
    -- Trata 3 excecoes: dataset vazio, VALUE_ERROR (documento grande demais), OTHERS
    FUNCTION fn_exportar_dataset_json RETURN CLOB IS
        CURSOR c_pets IS
            SELECT p.id_pet, p.nm_pet, p.ds_especie, p.ds_raca, p.nr_idade, p.nr_peso,
                   p.ds_sexo, p.ds_nivel_risco,
                   t.id_tutor, t.nm_tutor, t.ds_email, t.nr_telefone
            FROM   ch_pet p
            INNER JOIN ch_tutor t ON t.id_tutor = p.id_tutor
            ORDER BY p.id_pet;

        CURSOR c_vacinas (p_id NUMBER) IS
            SELECT id_vacina, nm_vacina, dt_aplicacao, dt_proxima_dose
            FROM ch_vacina WHERE id_pet = p_id ORDER BY id_vacina;

        CURSOR c_consultas (p_id NUMBER) IS
            SELECT id_consulta, dt_consulta, ds_consulta, nm_veterinario
            FROM ch_consulta WHERE id_pet = p_id ORDER BY id_consulta;

        CURSOR c_medicamentos (p_id NUMBER) IS
            SELECT id_medicamento, nm_medicamento, ds_dosagem, ds_horario, dt_inicio, dt_fim
            FROM ch_medicamento WHERE id_pet = p_id ORDER BY id_medicamento;

        CURSOR c_lembretes (p_id NUMBER) IS
            SELECT id_lembrete, ds_mensagem, dt_lembrete, ds_status
            FROM ch_lembrete WHERE id_pet = p_id ORDER BY id_lembrete;

        v_json      CLOB;
        v_doc       VARCHAR2(32767);
        v_arr       VARCHAR2(8000);
        v_sep       VARCHAR2(1);
        v_qtd       NUMBER := 0;
        e_sem_dados EXCEPTION;
    BEGIN
        v_json := '[' || CHR(10);

        FOR r IN c_pets LOOP
            v_doc := '{'
                || '"id_pet":'         || fn_numero(r.id_pet)    || ','
                || '"nm_pet":'         || fn_texto(r.nm_pet)     || ','
                || '"ds_especie":'     || fn_texto(r.ds_especie) || ','
                || '"ds_raca":'        || fn_texto(r.ds_raca)    || ','
                || '"nr_idade":'       || fn_numero(r.nr_idade)  || ','
                || '"nr_peso":'        || fn_numero(r.nr_peso)   || ','
                || '"ds_sexo":'        || fn_texto(r.ds_sexo)    || ','
                || '"ds_nivel_risco":' || fn_texto(r.ds_nivel_risco) || ','
                || '"tutor":{'
                ||     '"id_tutor":'    || fn_numero(r.id_tutor)   || ','
                ||     '"nm_tutor":'    || fn_texto(r.nm_tutor)    || ','
                ||     '"ds_email":'    || fn_texto(r.ds_email)    || ','
                ||     '"nr_telefone":' || fn_texto(r.nr_telefone)
                || '},';

            -- vacinas
            v_arr := '['; v_sep := '';
            FOR v IN c_vacinas(r.id_pet) LOOP
                v_arr := v_arr || v_sep || '{'
                    || '"id_vacina":'      || fn_numero(v.id_vacina)     || ','
                    || '"nm_vacina":'      || fn_texto(v.nm_vacina)      || ','
                    || '"dt_aplicacao":'   || fn_data(v.dt_aplicacao)    || ','
                    || '"dt_proxima_dose":'|| fn_data(v.dt_proxima_dose)
                    || '}';
                v_sep := ',';
            END LOOP;
            v_doc := v_doc || '"vacinas":' || v_arr || '],';

            -- consultas
            v_arr := '['; v_sep := '';
            FOR c IN c_consultas(r.id_pet) LOOP
                v_arr := v_arr || v_sep || '{'
                    || '"id_consulta":'    || fn_numero(c.id_consulta)   || ','
                    || '"dt_consulta":'    || fn_data(c.dt_consulta)     || ','
                    || '"ds_consulta":'    || fn_texto(c.ds_consulta)    || ','
                    || '"nm_veterinario":' || fn_texto(c.nm_veterinario)
                    || '}';
                v_sep := ',';
            END LOOP;
            v_doc := v_doc || '"consultas":' || v_arr || '],';

            -- medicamentos
            v_arr := '['; v_sep := '';
            FOR m IN c_medicamentos(r.id_pet) LOOP
                v_arr := v_arr || v_sep || '{'
                    || '"id_medicamento":' || fn_numero(m.id_medicamento) || ','
                    || '"nm_medicamento":' || fn_texto(m.nm_medicamento)  || ','
                    || '"ds_dosagem":'     || fn_texto(m.ds_dosagem)      || ','
                    || '"ds_horario":'     || fn_texto(m.ds_horario)      || ','
                    || '"dt_inicio":'      || fn_data(m.dt_inicio)        || ','
                    || '"dt_fim":'         || fn_data(m.dt_fim)
                    || '}';
                v_sep := ',';
            END LOOP;
            v_doc := v_doc || '"medicamentos":' || v_arr || '],';

            -- lembretes
            v_arr := '['; v_sep := '';
            FOR l IN c_lembretes(r.id_pet) LOOP
                v_arr := v_arr || v_sep || '{'
                    || '"id_lembrete":' || fn_numero(l.id_lembrete) || ','
                    || '"ds_mensagem":' || fn_texto(l.ds_mensagem)  || ','
                    || '"dt_lembrete":' || fn_data(l.dt_lembrete)   || ','
                    || '"ds_status":'   || fn_texto(l.ds_status)
                    || '}';
                v_sep := ',';
            END LOOP;
            v_doc := v_doc || '"lembretes":' || v_arr || ']}';

            IF v_qtd > 0 THEN
                v_json := v_json || ',' || CHR(10);
            END IF;
            v_json := v_json || v_doc;
            v_qtd  := v_qtd + 1;
        END LOOP;

        IF v_qtd = 0 THEN
            RAISE e_sem_dados;
        END IF;

        RETURN v_json || CHR(10) || ']';
    EXCEPTION
        WHEN e_sem_dados THEN
            RETURN TO_CLOB('[]');
        WHEN VALUE_ERROR THEN
            pkg_log.pr_registrar_erro('pkg_pet_json.fn_exportar_dataset_json', SQLCODE, SQLERRM);
            RAISE_APPLICATION_ERROR(-20010, 'Documento JSON maior que o limite do buffer.');
        WHEN OTHERS THEN
            pkg_log.pr_registrar_erro('pkg_pet_json.fn_exportar_dataset_json', SQLCODE, SQLERRM);
            RAISE_APPLICATION_ERROR(-20099, 'Erro inesperado ao exportar o dataset JSON.');
    END fn_exportar_dataset_json;

    -- Imprime o dataset: cada documento em uma linha (nao quebra o JSON)
    PROCEDURE pr_exportar_dataset_json IS
        v_json CLOB;
        v_tam  NUMBER;
        v_pos  NUMBER := 1;
        v_fim  NUMBER;
        e_dataset_vazio EXCEPTION;
    BEGIN
        v_json := fn_exportar_dataset_json;
        v_tam  := NVL(DBMS_LOB.GETLENGTH(v_json), 0);

        IF v_tam = 0 THEN
            RAISE e_dataset_vazio;
        END IF;

        WHILE v_pos <= v_tam LOOP
            v_fim := DBMS_LOB.INSTR(v_json, CHR(10), v_pos);
            IF v_fim = 0 THEN
                v_fim := v_tam + 1;
            END IF;
            IF v_fim > v_pos THEN
                DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(v_json, v_fim - v_pos, v_pos));
            END IF;
            v_pos := v_fim + 1;
        END LOOP;
    EXCEPTION
        WHEN e_dataset_vazio THEN
            DBMS_OUTPUT.PUT_LINE('Dataset vazio: nada para exportar.');
        WHEN VALUE_ERROR THEN
            DBMS_OUTPUT.PUT_LINE('Erro de conversao ao imprimir o dataset JSON.');
        WHEN OTHERS THEN
            pkg_log.pr_registrar_erro('pkg_pet_json.pr_exportar_dataset_json', SQLCODE, SQLERRM);
            RAISE;
    END pr_exportar_dataset_json;

END pkg_pet_json;
/

-- ---------------------------------------------------------------
-- 2.4) PKG_PET_RELATORIO - Procedure 2 da Sprint 3
-- Soma peso por tutor + especie e calcula MANUALMENTE o subtotal por
-- tutor e o total geral (sem ROLLUP/CUBE/GROUPING SETS).
-- Trata 3 excecoes: NO_DATA_FOUND, ZERO_DIVIDE e OTHERS
-- ---------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_pet_relatorio AS
    PROCEDURE pr_relatorio_peso_tutor_especie;
END pkg_pet_relatorio;
/

CREATE OR REPLACE PACKAGE BODY pkg_pet_relatorio AS

    PROCEDURE pr_relatorio_peso_tutor_especie IS
        CURSOR c_pets IS
            SELECT t.nm_tutor, p.ds_especie, SUM(p.nr_peso) AS peso_total
            FROM   ch_pet p
            INNER JOIN ch_tutor t ON p.id_tutor = t.id_tutor
            GROUP BY t.nm_tutor, p.ds_especie
            ORDER BY t.nm_tutor, p.ds_especie;

        v_tutor_atual ch_tutor.nm_tutor%TYPE;
        v_subtotal    NUMBER := 0;
        v_total_geral NUMBER := 0;
        v_qtd_linhas  NUMBER := 0;
    BEGIN
        DBMS_OUTPUT.PUT_LINE(RPAD('TUTOR', 25) || RPAD('ESPECIE', 12) || 'PESO');
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 25, '-') || RPAD('-', 12, '-') || '-------');

        FOR r IN c_pets LOOP
            v_qtd_linhas := v_qtd_linhas + 1;

            IF v_tutor_atual IS NOT NULL AND v_tutor_atual <> r.nm_tutor THEN
                DBMS_OUTPUT.PUT_LINE(RPAD('Sub Total', 37) || TO_CHAR(v_subtotal, '9999990.00'));
                v_subtotal := 0;
            END IF;

            v_tutor_atual := r.nm_tutor;
            DBMS_OUTPUT.PUT_LINE(RPAD(r.nm_tutor, 25) || RPAD(r.ds_especie, 12) || TO_CHAR(r.peso_total, '9999990.00'));

            v_subtotal    := v_subtotal + r.peso_total;
            v_total_geral := v_total_geral + r.peso_total;
        END LOOP;

        IF v_qtd_linhas = 0 THEN
            RAISE NO_DATA_FOUND;
        END IF;

        DBMS_OUTPUT.PUT_LINE(RPAD('Sub Total', 37) || TO_CHAR(v_subtotal, '9999990.00'));
        DBMS_OUTPUT.PUT_LINE(RPAD('Total Geral', 37) || TO_CHAR(v_total_geral, '9999990.00'));
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('Nenhum registro de pet/tutor encontrado para o relatorio.');
        WHEN ZERO_DIVIDE THEN
            DBMS_OUTPUT.PUT_LINE('Erro de divisao por zero no calculo do relatorio.');
        WHEN OTHERS THEN
            pkg_log.pr_registrar_erro('pkg_pet_relatorio.pr_relatorio_peso_tutor_especie', SQLCODE, SQLERRM);
            RAISE;
    END pr_relatorio_peso_tutor_especie;

END pkg_pet_relatorio;
/

-- ---------------------------------------------------------------
-- 2.5) PKG_PET_AUDITORIA - usado pela trigger de auditoria
-- ---------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_pet_auditoria AS
    FUNCTION fn_formatar_pet (
        p_id_pet      IN NUMBER,
        p_nm_pet      IN VARCHAR2,
        p_nr_idade    IN NUMBER,
        p_nr_peso     IN NUMBER,
        p_nivel_risco IN VARCHAR2
    ) RETURN VARCHAR2;

    PROCEDURE pr_registrar (
        p_tp_operacao     IN VARCHAR2,
        p_valores_antigos IN VARCHAR2,
        p_valores_novos   IN VARCHAR2
    );
END pkg_pet_auditoria;
/

CREATE OR REPLACE PACKAGE BODY pkg_pet_auditoria AS

    FUNCTION fn_formatar_pet (
        p_id_pet      IN NUMBER,
        p_nm_pet      IN VARCHAR2,
        p_nr_idade    IN NUMBER,
        p_nr_peso     IN NUMBER,
        p_nivel_risco IN VARCHAR2
    ) RETURN VARCHAR2 IS
    BEGIN
        RETURN 'id_pet=' || p_id_pet || ';nm_pet=' || p_nm_pet ||
               ';nr_idade=' || p_nr_idade || ';nr_peso=' || p_nr_peso ||
               ';nivel_risco=' || p_nivel_risco;
    END fn_formatar_pet;

    -- Trata: tipo de operacao invalido e OTHERS
    PROCEDURE pr_registrar (
        p_tp_operacao     IN VARCHAR2,
        p_valores_antigos IN VARCHAR2,
        p_valores_novos   IN VARCHAR2
    ) IS
        e_tipo_invalido EXCEPTION;
    BEGIN
        IF p_tp_operacao NOT IN ('INSERT', 'UPDATE', 'DELETE') OR p_tp_operacao IS NULL THEN
            RAISE e_tipo_invalido;
        END IF;

        INSERT INTO ch_pet_auditoria (nm_usuario, tp_operacao, dt_operacao, ds_valores_antigos, ds_valores_novos)
        VALUES (SYS_CONTEXT('USERENV','SESSION_USER'), p_tp_operacao, SYSDATE,
                SUBSTR(p_valores_antigos, 1, 500), SUBSTR(p_valores_novos, 1, 500));
    EXCEPTION
        WHEN e_tipo_invalido THEN
            RAISE_APPLICATION_ERROR(-20020, 'Tipo de operacao de auditoria invalido.');
        WHEN OTHERS THEN
            pkg_log.pr_registrar_erro('pkg_pet_auditoria.pr_registrar', SQLCODE, SQLERRM);
            RAISE;
    END pr_registrar;

END pkg_pet_auditoria;
/

-- ---------------------------------------------------------------
-- 2.6) PKG_PET_APP - procedures chamadas pelo BACKEND (Java Spring Boot)
-- Codigos de erro levantados para a aplicacao (RAISE_APPLICATION_ERROR):
--   -20001 parametro obrigatorio nulo     -20004 valor invalido
--   -20002 registro duplicado (e-mail)    -20005 registro nao encontrado
--   -20003 tutor/pet inexistente (FK)     -20006 possui registros dependentes
--   -20099 erro inesperado (detalhe em ch_log_erro)
-- Cada procedure faz COMMIT no sucesso e ROLLBACK no erro inesperado.
-- ---------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_pet_app AS
    PROCEDURE pr_inserir_tutor (
        p_nm_tutor    IN  VARCHAR2,
        p_ds_email    IN  VARCHAR2,
        p_nr_telefone IN  VARCHAR2,
        p_id_tutor    OUT NUMBER
    );

    PROCEDURE pr_inserir_pet (
        p_nm_pet     IN  VARCHAR2,
        p_ds_especie IN  VARCHAR2,
        p_ds_raca    IN  VARCHAR2,
        p_nr_idade   IN  NUMBER,
        p_nr_peso    IN  NUMBER,
        p_ds_sexo    IN  VARCHAR2,
        p_id_tutor   IN  NUMBER,
        p_id_pet     OUT NUMBER
    );

    PROCEDURE pr_registrar_vacina (
        p_nm_vacina       IN  VARCHAR2,
        p_dt_aplicacao    IN  DATE,
        p_dt_proxima_dose IN  DATE,
        p_id_pet          IN  NUMBER,
        p_id_vacina       OUT NUMBER
    );

    PROCEDURE pr_atualizar_peso_pet (
        p_id_pet  IN NUMBER,
        p_nr_peso IN NUMBER
    );

    PROCEDURE pr_excluir_pet (p_id_pet IN NUMBER);

    PROCEDURE pr_listar_pets (p_cursor OUT SYS_REFCURSOR);
END pkg_pet_app;
/

CREATE OR REPLACE PACKAGE BODY pkg_pet_app AS

    e_param_nulo     EXCEPTION;
    e_valor_invalido EXCEPTION;
    e_nao_encontrado EXCEPTION;
    e_fk_violada     EXCEPTION;
    e_possui_filhos  EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_fk_violada,    -2291);  -- pai nao existe
    PRAGMA EXCEPTION_INIT(e_possui_filhos, -2292);  -- existem filhos

    PROCEDURE pr_inserir_tutor (
        p_nm_tutor    IN  VARCHAR2,
        p_ds_email    IN  VARCHAR2,
        p_nr_telefone IN  VARCHAR2,
        p_id_tutor    OUT NUMBER
    ) IS
    BEGIN
        IF p_nm_tutor IS NULL OR p_ds_email IS NULL THEN
            RAISE e_param_nulo;
        END IF;

        INSERT INTO ch_tutor (nm_tutor, ds_email, nr_telefone)
        VALUES (p_nm_tutor, p_ds_email, p_nr_telefone)
        RETURNING id_tutor INTO p_id_tutor;

        COMMIT;
    EXCEPTION
        WHEN e_param_nulo THEN
            RAISE_APPLICATION_ERROR(-20001, 'Nome e e-mail do tutor sao obrigatorios.');
        WHEN DUP_VAL_ON_INDEX THEN
            RAISE_APPLICATION_ERROR(-20002, 'Ja existe um tutor com este e-mail.');
        WHEN OTHERS THEN
            ROLLBACK;
            pkg_log.pr_registrar_erro('pkg_pet_app.pr_inserir_tutor', SQLCODE, SQLERRM);
            RAISE_APPLICATION_ERROR(-20099, 'Erro inesperado ao inserir tutor.');
    END pr_inserir_tutor;

    PROCEDURE pr_inserir_pet (
        p_nm_pet     IN  VARCHAR2,
        p_ds_especie IN  VARCHAR2,
        p_ds_raca    IN  VARCHAR2,
        p_nr_idade   IN  NUMBER,
        p_nr_peso    IN  NUMBER,
        p_ds_sexo    IN  VARCHAR2,
        p_id_tutor   IN  NUMBER,
        p_id_pet     OUT NUMBER
    ) IS
    BEGIN
        IF p_nm_pet IS NULL OR p_ds_especie IS NULL OR p_id_tutor IS NULL THEN
            RAISE e_param_nulo;
        END IF;
        IF NVL(p_nr_idade, 0) < 0 OR NVL(p_nr_peso, 1) <= 0 THEN
            RAISE e_valor_invalido;
        END IF;

        -- ds_nivel_risco e preenchido pela trigger trg_definir_risco_pet
        INSERT INTO ch_pet (nm_pet, ds_especie, ds_raca, nr_idade, nr_peso, ds_sexo, id_tutor)
        VALUES (p_nm_pet, p_ds_especie, p_ds_raca, p_nr_idade, p_nr_peso, p_ds_sexo, p_id_tutor)
        RETURNING id_pet INTO p_id_pet;

        COMMIT;
    EXCEPTION
        WHEN e_param_nulo THEN
            RAISE_APPLICATION_ERROR(-20001, 'Nome, especie e tutor do pet sao obrigatorios.');
        WHEN e_valor_invalido THEN
            RAISE_APPLICATION_ERROR(-20004, 'Idade nao pode ser negativa e peso deve ser maior que zero.');
        WHEN e_fk_violada THEN
            ROLLBACK;
            RAISE_APPLICATION_ERROR(-20003, 'Tutor informado nao existe.');
        WHEN OTHERS THEN
            ROLLBACK;
            pkg_log.pr_registrar_erro('pkg_pet_app.pr_inserir_pet', SQLCODE, SQLERRM);
            RAISE_APPLICATION_ERROR(-20099, 'Erro inesperado ao inserir pet.');
    END pr_inserir_pet;

    PROCEDURE pr_registrar_vacina (
        p_nm_vacina       IN  VARCHAR2,
        p_dt_aplicacao    IN  DATE,
        p_dt_proxima_dose IN  DATE,
        p_id_pet          IN  NUMBER,
        p_id_vacina       OUT NUMBER
    ) IS
    BEGIN
        IF p_nm_vacina IS NULL OR p_dt_aplicacao IS NULL OR p_id_pet IS NULL THEN
            RAISE e_param_nulo;
        END IF;
        IF p_dt_proxima_dose IS NOT NULL AND p_dt_proxima_dose < p_dt_aplicacao THEN
            RAISE e_valor_invalido;
        END IF;

        INSERT INTO ch_vacina (nm_vacina, dt_aplicacao, dt_proxima_dose, id_pet)
        VALUES (p_nm_vacina, p_dt_aplicacao, p_dt_proxima_dose, p_id_pet)
        RETURNING id_vacina INTO p_id_vacina;

        COMMIT;
    EXCEPTION
        WHEN e_param_nulo THEN
            RAISE_APPLICATION_ERROR(-20001, 'Vacina, data de aplicacao e pet sao obrigatorios.');
        WHEN e_valor_invalido THEN
            RAISE_APPLICATION_ERROR(-20004, 'A proxima dose nao pode ser anterior a aplicacao.');
        WHEN e_fk_violada THEN
            ROLLBACK;
            RAISE_APPLICATION_ERROR(-20003, 'Pet informado nao existe.');
        WHEN OTHERS THEN
            ROLLBACK;
            pkg_log.pr_registrar_erro('pkg_pet_app.pr_registrar_vacina', SQLCODE, SQLERRM);
            RAISE_APPLICATION_ERROR(-20099, 'Erro inesperado ao registrar vacina.');
    END pr_registrar_vacina;

    PROCEDURE pr_atualizar_peso_pet (
        p_id_pet  IN NUMBER,
        p_nr_peso IN NUMBER
    ) IS
    BEGIN
        IF p_id_pet IS NULL OR p_nr_peso IS NULL THEN
            RAISE e_param_nulo;
        END IF;
        IF p_nr_peso <= 0 THEN
            RAISE e_valor_invalido;
        END IF;

        UPDATE ch_pet SET nr_peso = p_nr_peso WHERE id_pet = p_id_pet;

        IF SQL%ROWCOUNT = 0 THEN
            RAISE e_nao_encontrado;
        END IF;

        COMMIT;
    EXCEPTION
        WHEN e_param_nulo THEN
            RAISE_APPLICATION_ERROR(-20001, 'Pet e peso sao obrigatorios.');
        WHEN e_valor_invalido THEN
            RAISE_APPLICATION_ERROR(-20004, 'O peso deve ser maior que zero.');
        WHEN e_nao_encontrado THEN
            RAISE_APPLICATION_ERROR(-20005, 'Pet nao encontrado.');
        WHEN OTHERS THEN
            ROLLBACK;
            pkg_log.pr_registrar_erro('pkg_pet_app.pr_atualizar_peso_pet', SQLCODE, SQLERRM);
            RAISE_APPLICATION_ERROR(-20099, 'Erro inesperado ao atualizar peso.');
    END pr_atualizar_peso_pet;

    PROCEDURE pr_excluir_pet (p_id_pet IN NUMBER) IS
    BEGIN
        IF p_id_pet IS NULL THEN
            RAISE e_param_nulo;
        END IF;

        DELETE FROM ch_pet WHERE id_pet = p_id_pet;

        IF SQL%ROWCOUNT = 0 THEN
            RAISE e_nao_encontrado;
        END IF;

        COMMIT;
    EXCEPTION
        WHEN e_param_nulo THEN
            RAISE_APPLICATION_ERROR(-20001, 'O id do pet e obrigatorio.');
        WHEN e_nao_encontrado THEN
            RAISE_APPLICATION_ERROR(-20005, 'Pet nao encontrado.');
        WHEN e_possui_filhos THEN
            ROLLBACK;
            RAISE_APPLICATION_ERROR(-20006, 'Pet possui vacinas, consultas, medicamentos ou lembretes e nao pode ser excluido.');
        WHEN OTHERS THEN
            ROLLBACK;
            pkg_log.pr_registrar_erro('pkg_pet_app.pr_excluir_pet', SQLCODE, SQLERRM);
            RAISE_APPLICATION_ERROR(-20099, 'Erro inesperado ao excluir pet.');
    END pr_excluir_pet;

    PROCEDURE pr_listar_pets (p_cursor OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_cursor FOR
            SELECT p.id_pet, p.nm_pet, p.ds_especie, p.ds_raca, p.nr_idade,
                   p.nr_peso, p.ds_nivel_risco, t.nm_tutor
            FROM   ch_pet p
            INNER JOIN ch_tutor t ON t.id_tutor = p.id_tutor
            ORDER BY p.id_pet;
    EXCEPTION
        WHEN OTHERS THEN
            pkg_log.pr_registrar_erro('pkg_pet_app.pr_listar_pets', SQLCODE, SQLERRM);
            RAISE_APPLICATION_ERROR(-20099, 'Erro inesperado ao listar pets.');
    END pr_listar_pets;

END pkg_pet_app;
/

-- =====================================================================
-- 3) TRIGGER DE NEGOCIO - classificacao de risco (so chama o package)
-- =====================================================================
CREATE OR REPLACE TRIGGER trg_definir_risco_pet
BEFORE INSERT OR UPDATE ON ch_pet
FOR EACH ROW
BEGIN
    :NEW.ds_nivel_risco := pkg_pet_regras.fn_classificar_risco_por_idade(:NEW.nr_idade);
END;
/

-- =====================================================================
-- 4) INSERTS - minimo 5 registros por tabela
-- (rodam depois da trigger de risco, entao ds_nivel_risco ja nasce preenchido)
-- =====================================================================
INSERT INTO ch_tutor (nm_tutor, ds_email, nr_telefone) VALUES ('Felipe Augusto', 'felipe@gmail.com', '11999999999');
INSERT INTO ch_tutor (nm_tutor, ds_email, nr_telefone) VALUES ('Mariana Silva', 'mariana@gmail.com', '11988888888');
INSERT INTO ch_tutor (nm_tutor, ds_email, nr_telefone) VALUES ('Carlos Eduardo Nunes', 'carlos.nunes@gmail.com', '11977777777');
INSERT INTO ch_tutor (nm_tutor, ds_email, nr_telefone) VALUES ('Ana Paula Souza', 'ana.souza@gmail.com', '11966666666');
INSERT INTO ch_tutor (nm_tutor, ds_email, nr_telefone) VALUES ('Bruno Costa Lima', 'bruno.lima@gmail.com', '11955555555');

INSERT INTO ch_pet (nm_pet, ds_especie, ds_raca, nr_idade, nr_peso, ds_sexo, id_tutor) VALUES ('Thor', 'Cachorro', 'Golden Retriever', 5, 32.5, 'M', 1);
INSERT INTO ch_pet (nm_pet, ds_especie, ds_raca, nr_idade, nr_peso, ds_sexo, id_tutor) VALUES ('Luna', 'Gato', 'Siamês', 3, 4.2, 'F', 2);
INSERT INTO ch_pet (nm_pet, ds_especie, ds_raca, nr_idade, nr_peso, ds_sexo, id_tutor) VALUES ('Mel', 'Cachorro', 'Poodle', 2, 6.8, 'F', 3);
INSERT INTO ch_pet (nm_pet, ds_especie, ds_raca, nr_idade, nr_peso, ds_sexo, id_tutor) VALUES ('Rex', 'Cachorro', 'Labrador', 8, 29.0, 'M', 4);
INSERT INTO ch_pet (nm_pet, ds_especie, ds_raca, nr_idade, nr_peso, ds_sexo, id_tutor) VALUES ('Nina', 'Gato', 'Persa', 6, 4.5, 'F', 5);

INSERT INTO ch_vacina (nm_vacina, dt_aplicacao, dt_proxima_dose, id_pet) VALUES ('Antirrábica', TO_DATE('10/01/2026','DD/MM/YYYY'), TO_DATE('10/01/2027','DD/MM/YYYY'), 1);
INSERT INTO ch_vacina (nm_vacina, dt_aplicacao, dt_proxima_dose, id_pet) VALUES ('V4', TO_DATE('15/02/2026','DD/MM/YYYY'), TO_DATE('15/02/2027','DD/MM/YYYY'), 2);
INSERT INTO ch_vacina (nm_vacina, dt_aplicacao, dt_proxima_dose, id_pet) VALUES ('V10', TO_DATE('05/03/2026','DD/MM/YYYY'), TO_DATE('05/03/2027','DD/MM/YYYY'), 3);
INSERT INTO ch_vacina (nm_vacina, dt_aplicacao, dt_proxima_dose, id_pet) VALUES ('Antirrábica', TO_DATE('12/03/2026','DD/MM/YYYY'), TO_DATE('12/03/2027','DD/MM/YYYY'), 4);
INSERT INTO ch_vacina (nm_vacina, dt_aplicacao, dt_proxima_dose, id_pet) VALUES ('Giardia', TO_DATE('20/03/2026','DD/MM/YYYY'), TO_DATE('20/03/2027','DD/MM/YYYY'), 5);

INSERT INTO ch_consulta (dt_consulta, ds_consulta, nm_veterinario, id_pet) VALUES (TO_DATE('20/03/2026','DD/MM/YYYY'), 'Consulta de rotina', 'Dr. Ricardo', 1);
INSERT INTO ch_consulta (dt_consulta, ds_consulta, nm_veterinario, id_pet) VALUES (TO_DATE('18/04/2026','DD/MM/YYYY'), 'Avaliação dermatológica', 'Dra. Fernanda', 2);
INSERT INTO ch_consulta (dt_consulta, ds_consulta, nm_veterinario, id_pet) VALUES (TO_DATE('02/05/2026','DD/MM/YYYY'), 'Check-up geral', 'Dr. Ricardo', 3);
INSERT INTO ch_consulta (dt_consulta, ds_consulta, nm_veterinario, id_pet) VALUES (TO_DATE('10/05/2026','DD/MM/YYYY'), 'Avaliação ortopédica', 'Dra. Fernanda', 4);
INSERT INTO ch_consulta (dt_consulta, ds_consulta, nm_veterinario, id_pet) VALUES (TO_DATE('15/05/2026','DD/MM/YYYY'), 'Consulta de rotina', 'Dr. Ricardo', 5);

INSERT INTO ch_medicamento (nm_medicamento, ds_dosagem, ds_horario, dt_inicio, dt_fim, id_pet) VALUES ('Prednisona', '10mg', '08:00', TO_DATE('01/05/2026','DD/MM/YYYY'), TO_DATE('10/05/2026','DD/MM/YYYY'), 1);
INSERT INTO ch_medicamento (nm_medicamento, ds_dosagem, ds_horario, dt_inicio, dt_fim, id_pet) VALUES ('Antibiótico', '5ml', '12:00', TO_DATE('02/05/2026','DD/MM/YYYY'), TO_DATE('12/05/2026','DD/MM/YYYY'), 2);
INSERT INTO ch_medicamento (nm_medicamento, ds_dosagem, ds_horario, dt_inicio, dt_fim, id_pet) VALUES ('Vermífugo', '1 comprimido', '09:00', TO_DATE('01/06/2026','DD/MM/YYYY'), TO_DATE('03/06/2026','DD/MM/YYYY'), 3);
INSERT INTO ch_medicamento (nm_medicamento, ds_dosagem, ds_horario, dt_inicio, dt_fim, id_pet) VALUES ('Anti-inflamatório', '15mg', '20:00', TO_DATE('02/06/2026','DD/MM/YYYY'), TO_DATE('09/06/2026','DD/MM/YYYY'), 4);
INSERT INTO ch_medicamento (nm_medicamento, ds_dosagem, ds_horario, dt_inicio, dt_fim, id_pet) VALUES ('Suplemento articular', '1 sachê', '19:00', TO_DATE('03/06/2026','DD/MM/YYYY'), TO_DATE('30/06/2026','DD/MM/YYYY'), 5);

INSERT INTO ch_lembrete (ds_mensagem, dt_lembrete, ds_status, id_pet) VALUES ('Aplicar vacina anual', TO_DATE('10/01/2027','DD/MM/YYYY'), 'PENDENTE', 1);
INSERT INTO ch_lembrete (ds_mensagem, dt_lembrete, ds_status, id_pet) VALUES ('Retorno veterinário', TO_DATE('20/05/2026','DD/MM/YYYY'), 'PENDENTE', 2);
INSERT INTO ch_lembrete (ds_mensagem, dt_lembrete, ds_status, id_pet) VALUES ('Dose de reforço', TO_DATE('05/09/2026','DD/MM/YYYY'), 'PENDENTE', 3);
INSERT INTO ch_lembrete (ds_mensagem, dt_lembrete, ds_status, id_pet) VALUES ('Reavaliação ortopédica', TO_DATE('10/09/2026','DD/MM/YYYY'), 'PENDENTE', 4);
INSERT INTO ch_lembrete (ds_mensagem, dt_lembrete, ds_status, id_pet) VALUES ('Exame de rotina', TO_DATE('15/09/2026','DD/MM/YYYY'), 'PENDENTE', 5);

COMMIT;

-- =====================================================================
-- 5) TRIGGER DE AUDITORIA - so chama o package pkg_pet_auditoria
-- (criada depois dos inserts para a auditoria comecar "limpa")
-- =====================================================================
CREATE OR REPLACE TRIGGER trg_auditoria_pet
AFTER INSERT OR UPDATE OR DELETE ON ch_pet
FOR EACH ROW
BEGIN
    IF INSERTING THEN
        pkg_pet_auditoria.pr_registrar('INSERT', NULL,
            pkg_pet_auditoria.fn_formatar_pet(:NEW.id_pet, :NEW.nm_pet, :NEW.nr_idade, :NEW.nr_peso, :NEW.ds_nivel_risco));
    ELSIF UPDATING THEN
        pkg_pet_auditoria.pr_registrar('UPDATE',
            pkg_pet_auditoria.fn_formatar_pet(:OLD.id_pet, :OLD.nm_pet, :OLD.nr_idade, :OLD.nr_peso, :OLD.ds_nivel_risco),
            pkg_pet_auditoria.fn_formatar_pet(:NEW.id_pet, :NEW.nm_pet, :NEW.nr_idade, :NEW.nr_peso, :NEW.ds_nivel_risco));
    ELSIF DELETING THEN
        pkg_pet_auditoria.pr_registrar('DELETE',
            pkg_pet_auditoria.fn_formatar_pet(:OLD.id_pet, :OLD.nm_pet, :OLD.nr_idade, :OLD.nr_peso, :OLD.ds_nivel_risco),
            NULL);
    END IF;
END;
/

-- =====================================================================
-- 6) TESTES (tirar prints / mostrar no video)
--    Os testes deixam os dados iguais aos do seed (inserem e removem o
--    pet de teste), so a tabela de auditoria acumula as operacoes.
-- =====================================================================

-- 6.1) Procedure 1 + Function 1 (JOIN -> JSON manual)
EXEC pkg_pet_json.pr_listar_pets_tutores_json;

-- 6.2) Procedure 2 (relatorio com subtotal e total geral manuais)
EXEC pkg_pet_relatorio.pr_relatorio_peso_tutor_especie;

-- 6.3) Function 2 + excecoes tratadas
SELECT pkg_pet_regras.fn_classificar_risco_por_idade(8)    AS risco_idade_8     FROM dual;
SELECT pkg_pet_regras.fn_classificar_risco_por_idade(NULL) AS teste_idade_nula  FROM dual;
SELECT pkg_pet_regras.fn_classificar_risco_por_idade(-3)   AS teste_idade_neg   FROM dual;
SELECT pkg_pet_json.fn_montar_json_pet(NULL, 'Cachorro', 'ALTO', NULL, 'x@x.com') AS teste_param_nulo FROM dual;

-- 6.4) Procedures do backend (pkg_pet_app): caminho feliz + trigger de auditoria
DECLARE
    v_id_pet    NUMBER;
    v_id_vacina NUMBER;
BEGIN
    pkg_pet_app.pr_inserir_pet('Bolt', 'Cachorro', 'Beagle', 9, 12.3, 'M', 1, v_id_pet);
    DBMS_OUTPUT.PUT_LINE('Pet inserido, id = ' || v_id_pet);

    pkg_pet_app.pr_registrar_vacina('V10', SYSDATE, ADD_MONTHS(SYSDATE, 12), v_id_pet, v_id_vacina);
    DBMS_OUTPUT.PUT_LINE('Vacina registrada, id = ' || v_id_vacina);

    pkg_pet_app.pr_atualizar_peso_pet(v_id_pet, 12.8);
    DBMS_OUTPUT.PUT_LINE('Peso atualizado.');

    -- limpa os dados de teste (vacina primeiro por causa da FK)
    DELETE FROM ch_vacina WHERE id_vacina = v_id_vacina;
    pkg_pet_app.pr_excluir_pet(v_id_pet);
    DBMS_OUTPUT.PUT_LINE('Pet de teste excluido.');
END;
/

SELECT id_pet, nm_pet, nr_idade, ds_nivel_risco FROM ch_pet ORDER BY id_pet;
SELECT tp_operacao, nm_usuario, TO_CHAR(dt_operacao,'DD/MM/YYYY HH24:MI:SS') AS dt_operacao,
       ds_valores_antigos, ds_valores_novos
FROM   ch_pet_auditoria ORDER BY id_auditoria;

-- 6.5) Excecoes tratadas nas procedures do backend (cada bloco mostra a mensagem)
DECLARE
    v_id NUMBER;
BEGIN
    pkg_pet_app.pr_inserir_pet('Fantasma', 'Gato', NULL, 2, 3.0, 'M', 999, v_id);   -- tutor inexistente
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Erro esperado: ' || SQLERRM);
END;
/
DECLARE
    v_id NUMBER;
BEGIN
    pkg_pet_app.pr_inserir_tutor('Duplicado', 'felipe@gmail.com', NULL, v_id);      -- e-mail repetido
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Erro esperado: ' || SQLERRM);
END;
/
BEGIN
    pkg_pet_app.pr_excluir_pet(1);                                                   -- pet tem vacina/consulta
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Erro esperado: ' || SQLERRM);
END;
/
BEGIN
    pkg_pet_app.pr_atualizar_peso_pet(999, 10);                                      -- pet inexistente
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Erro esperado: ' || SQLERRM);
END;
/

-- 6.6) Log de erros (preenchido pelas clausulas OTHERS)
SELECT * FROM ch_log_erro ORDER BY id_log;

-- 6.7) EXPORTACAO DO JSON -> rode o arquivo exportar_json.sql (SQL*Plus)
--      ou execute abaixo e copie a saida para supernova_vet.json
-- EXEC pkg_pet_json.pr_exportar_dataset_json;
