-- =====================================================================
-- ALUNO 4 - Triggers e Funções de Gatilho
-- Arquivo: 04_plpgsql_triggers.sql
-- Executar APÓS o povoamento (02) para não disparar gatilhos na carga em massa.
--
-- As duas funções são SECURITY DEFINER para que um usuário com acesso restrito
-- (usr_operador) consiga disparar a baixa de estoque e a auditoria sem ter
-- permissão direta de UPDATE em tb_produto / INSERT em tb_log_produto.
-- =====================================================================

-- ---------------------------------------------------------------------
-- TRIGGER 1 (AUDITORIA): registra UPDATE/DELETE em tb_produto -> tb_log_produto
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_auditar_produto()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        -- ignora UPDATEs que não alteram nada
        IF NEW IS NOT DISTINCT FROM OLD THEN
            RETURN NEW;
        END IF;

        INSERT INTO tb_log_produto
            (idt_produto, nme_operacao, vlr_preco_antigo, vlr_preco_novo,
             num_estoque_antigo, nme_usuario)
        VALUES
            (OLD.idt_produto, 'UPDATE', OLD.vlr_preco, NEW.vlr_preco,
             OLD.num_estoque, session_user);
        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO tb_log_produto
            (idt_produto, nme_operacao, vlr_preco_antigo, vlr_preco_novo,
             num_estoque_antigo, nme_usuario)
        VALUES
            (OLD.idt_produto, 'DELETE', OLD.vlr_preco, NULL,
             OLD.num_estoque, session_user);
        RETURN OLD;
    END IF;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_auditar_produto ON tb_produto;
CREATE TRIGGER trg_auditar_produto
    AFTER UPDATE OR DELETE ON tb_produto
    FOR EACH ROW
    EXECUTE FUNCTION fn_auditar_produto();

-- ---------------------------------------------------------------------
-- TRIGGER 2 (REGRA DE NEGÓCIO): baixa automática de estoque ao inserir item
--           + validação impeditiva (RAISE EXCEPTION) de estoque/produto inativo
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_baixar_estoque()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_estoque  INTEGER;
    v_ativo    BOOLEAN;
    v_nome     VARCHAR(120);
BEGIN
    -- Trava a linha do produto: evita que duas vendas simultâneas leiam o mesmo estoque
    SELECT num_estoque, flg_ativo, nme_produto
      INTO v_estoque, v_ativo, v_nome
      FROM tb_produto
     WHERE idt_produto = NEW.idt_produto
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Produto % inexistente.', NEW.idt_produto;
    END IF;

    IF NOT v_ativo THEN
        RAISE EXCEPTION 'Produto "%" está inativo e não pode ser vendido.', v_nome;
    END IF;

    IF v_estoque < NEW.qtd_item THEN
        RAISE EXCEPTION 'Estoque insuficiente para "%": disponível %, solicitado %.',
                        v_nome, v_estoque, NEW.qtd_item;
    END IF;

    UPDATE tb_produto
       SET num_estoque = num_estoque - NEW.qtd_item
     WHERE idt_produto = NEW.idt_produto;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_baixar_estoque ON ta_item_pedido;
CREATE TRIGGER trg_baixar_estoque
    BEFORE INSERT ON ta_item_pedido
    FOR EACH ROW
    EXECUTE FUNCTION fn_baixar_estoque();

-- ---------------------------------------------------------------------
-- TESTES
-- ---------------------------------------------------------------------
-- Teste Trigger 1 (auditoria):
--   UPDATE tb_produto SET vlr_preco = vlr_preco * 1.10 WHERE idt_produto = 1;
--   SELECT * FROM tb_log_produto ORDER BY idt_log DESC LIMIT 5;
--
-- Teste Trigger 2 (estoque):
--   SELECT num_estoque FROM tb_produto WHERE idt_produto = 5;     -- anote
--   INSERT INTO tb_pedido (idt_cliente, nme_forma_pagamento) VALUES (1,'PIX');
--   INSERT INTO ta_item_pedido (idt_pedido, idt_produto, qtd_item, vlr_unitario)
--   VALUES (currval('tb_pedido_idt_pedido_seq'), 5, 2, 100);      -- estoque cai 2
--   INSERT INTO ta_item_pedido (idt_pedido, idt_produto, qtd_item, vlr_unitario)
--   VALUES (currval('tb_pedido_idt_pedido_seq'), 6, 999999, 100); -- ERRO esperado
