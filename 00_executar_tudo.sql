-- Execução completa (psql, dentro da pasta dos scripts):
--   createdb loja_bd2 && psql -d loja_bd2 -f 00_executar_tudo.sql
\set ON_ERROR_STOP on
\i 01_ddl_estrutura.sql
\i 02_dml_povoamento.sql
\i 04_plpgsql_triggers.sql
\i 04_plpgsql_procedures.sql
-- o script 05 contém ERROS PROPOSITAIS (testes de permissão e rollback)
\set ON_ERROR_STOP off
\i 05_seguranca_transacoes.sql
\i 03_otimizacao_indices.sql
\i 06_consultas_dql.sql
