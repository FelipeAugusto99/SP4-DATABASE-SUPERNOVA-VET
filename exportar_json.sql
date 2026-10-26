-- Exporta o dataset do Oracle para o arquivo supernova_vet.json
-- Como rodar (SQL*Plus / SQLcl), na pasta onde quer o arquivo:
--     sqlplus USUARIO/SENHA@host:1521/servico @exportar_json.sql
-- No SQL Developer: rode o EXEC abaixo na janela de script (F5),
-- copie a "Saida do Script" e salve como supernova_vet.json.

SET SERVEROUTPUT ON SIZE UNLIMITED FORMAT WRAPPED
SET LINESIZE 32767
SET TRIMSPOOL ON
SET TRIMOUT ON
SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SET ECHO OFF
SET TERMOUT OFF

SPOOL supernova_vet.json
EXEC pkg_pet_json.pr_exportar_dataset_json;
SPOOL OFF

SET TERMOUT ON
SET FEEDBACK ON
PROMPT Arquivo supernova_vet.json gerado.
