-- =====================================================================
-- ALUNO 4 - Controle de Acesso (DCL) e Transações
-- Arquivo: 05_seguranca_transacoes.sql
-- Executar como superusuário/dono do banco, APÓS os scripts 01 a 04.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) ROLES
--    (troque as senhas em ambiente real!)
-- ---------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'usr_admin') THEN
        CREATE ROLE usr_admin LOGIN PASSWORD 'Admin#2026';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'usr_operador') THEN
        CREATE ROLE usr_operador LOGIN PASSWORD 'Operador#2026';
    END IF;
END
$$;

-- Parte do zero: ninguém herda privilégios implícitos de PUBLIC
REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_registrar_pedido(BIGINT, BIGINT, INTEGER, VARCHAR) FROM PUBLIC;
REVOKE ALL ON PROCEDURE sp_cancelar_pedido(BIGINT) FROM PUBLIC;

GRANT USAGE ON SCHEMA public TO usr_admin, usr_operador;

-- ---------------------------------------------------------------------
-- 2) usr_admin: acesso total
-- ---------------------------------------------------------------------
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA public TO usr_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO usr_admin;
GRANT EXECUTE ON ALL FUNCTIONS  IN SCHEMA public TO usr_admin;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA public TO usr_admin;

-- ---------------------------------------------------------------------
-- 3) usr_operador: acesso restrito
--    - lê o catálogo e os pedidos
--    - cadastra clientes/pedidos/itens/avaliações
--    - NÃO apaga nada, NÃO altera produtos/preços diretamente, NÃO vê o log de auditoria
-- ---------------------------------------------------------------------
GRANT SELECT ON tb_categoria, tb_fornecedor, tb_produto, tb_cliente,
                tb_pedido, ta_item_pedido, tb_avaliacao TO usr_operador;

GRANT INSERT, UPDATE ON tb_cliente, tb_pedido TO usr_operador;
GRANT INSERT         ON ta_item_pedido, tb_avaliacao TO usr_operador;

GRANT USAGE ON SEQUENCE tb_cliente_idt_cliente_seq,
                        tb_pedido_idt_pedido_seq,
                        tb_avaliacao_idt_avaliacao_seq TO usr_operador;

GRANT EXECUTE ON FUNCTION  fn_registrar_pedido(BIGINT, BIGINT, INTEGER, VARCHAR) TO usr_operador;
GRANT EXECUTE ON PROCEDURE sp_cancelar_pedido(BIGINT)                            TO usr_operador;

REVOKE DELETE, TRUNCATE ON ALL TABLES IN SCHEMA public FROM usr_operador;
REVOKE ALL ON tb_log_produto FROM usr_operador;

-- ---------------------------------------------------------------------
-- 4) TESTES DE PERMISSÃO (cada comando abaixo é executado como usr_operador)
-- ---------------------------------------------------------------------
SET ROLE usr_operador;
SELECT COUNT(*) FROM tb_produto;                              -- OK
SELECT fn_registrar_pedido(1, 10, 1, 'PIX');                  -- OK (trigger DEFINER baixa estoque)
DELETE FROM tb_cliente WHERE idt_cliente = 1;                 -- ERRO esperado: permission denied
UPDATE tb_produto SET vlr_preco = 1 WHERE idt_produto = 1;    -- ERRO esperado: permission denied
SELECT * FROM tb_log_produto;                                 -- ERRO esperado: permission denied
RESET ROLE;

-- =====================================================================
-- 5) TRANSAÇÕES EXPLÍCITAS - operação crítica: FINALIZAR COMPRA
--    Pedido + item + baixa de estoque + total devem ocorrer juntos (atomicidade).
-- =====================================================================

-- ---- Cenário A: sucesso -> COMMIT ----------------------------------
BEGIN;

    -- trava o produto: outras sessões que tentem vender o mesmo item esperam
    SELECT idt_produto, num_estoque
      FROM tb_produto
     WHERE idt_produto = 20
       FOR UPDATE;

    INSERT INTO tb_pedido (idt_cliente, nme_forma_pagamento)
    VALUES (2, 'CARTAO_CREDITO');

    INSERT INTO ta_item_pedido (idt_pedido, idt_produto, qtd_item, vlr_unitario)
    SELECT currval('tb_pedido_idt_pedido_seq'), idt_produto, 2, vlr_preco
      FROM tb_produto WHERE idt_produto = 20;           -- trigger baixa 2 unidades

    UPDATE tb_pedido
       SET vlr_total = (SELECT SUM(vlr_subtotal) FROM ta_item_pedido
                         WHERE idt_pedido = currval('tb_pedido_idt_pedido_seq'))
     WHERE idt_pedido = currval('tb_pedido_idt_pedido_seq');

COMMIT;

-- ---- Cenário B: falha no meio -> SAVEPOINT + ROLLBACK ---------------
SELECT COUNT(*) AS qtd_pedidos_antes FROM tb_pedido;

BEGIN;
    INSERT INTO tb_pedido (idt_cliente, nme_forma_pagamento) VALUES (3, 'PIX');

    SAVEPOINT sp_item;
    -- quantidade impossível: o trigger lança EXCEPTION "Estoque insuficiente"
    INSERT INTO ta_item_pedido (idt_pedido, idt_produto, qtd_item, vlr_unitario)
    VALUES (currval('tb_pedido_idt_pedido_seq'), 20, 999999, 100);

    ROLLBACK TO SAVEPOINT sp_item;   -- desfaz só o item; a transação volta a ser usável
    -- (poderíamos tentar uma quantidade menor aqui; neste exemplo desistimos)
ROLLBACK;                            -- desfaz também o pedido

SELECT COUNT(*) AS qtd_pedidos_depois FROM tb_pedido;  -- igual a qtd_pedidos_antes

-- ---- Cenário C: concorrência (rodar em DUAS sessões psql) ----------
-- Sessão 1:                                   Sessão 2:
--   BEGIN;                                      BEGIN;
--   SELECT num_estoque FROM tb_produto
--     WHERE idt_produto = 30 FOR UPDATE;
--                                               SELECT num_estoque FROM tb_produto
--                                                 WHERE idt_produto = 30 FOR UPDATE;
--                                               -- (BLOQUEADA, aguardando a sessão 1)
--   -- vende 5 unidades
--   COMMIT;
--                                               -- libera e enxerga o estoque JÁ atualizado
--                                               COMMIT;
-- Sem FOR UPDATE (e sem a trava dentro de fn_baixar_estoque) as duas sessões poderiam ler
-- o mesmo estoque e vender além do disponível (lost update). O CHECK (num_estoque >= 0)
-- é a última linha de defesa.
