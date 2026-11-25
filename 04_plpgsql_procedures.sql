-- =====================================================================
-- ALUNO 4 - Stored Procedures / Functions em PL/pgSQL
-- Arquivo: 04_plpgsql_procedures.sql
-- (requer os triggers de 04_plpgsql_triggers.sql criados antes)
-- Ambas contêm IF/ELSE, manipulação de dados e tratamento de exceções.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) FUNCTION fn_registrar_pedido: cria pedido com 1 item e devolve o id.
--    Estoque é baixado pelo trigger trg_baixar_estoque.
--    Se qualquer passo falha, o bloco EXCEPTION desfaz tudo o que a função fez.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_registrar_pedido(
    p_cliente   BIGINT,
    p_produto   BIGINT,
    p_qtd       INTEGER,
    p_pagamento VARCHAR
) RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_ativo   BOOLEAN;
    v_preco   DECIMAL(10,2);
    v_pedido  BIGINT;
BEGIN
    -- valida cliente
    SELECT flg_ativo INTO v_ativo FROM tb_cliente WHERE idt_cliente = p_cliente;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cliente % não encontrado.', p_cliente;
    ELSIF NOT v_ativo THEN
        RAISE EXCEPTION 'Cliente % está inativo.', p_cliente;
    END IF;

    -- valida produto e captura o preço vigente
    SELECT vlr_preco INTO v_preco FROM tb_produto WHERE idt_produto = p_produto;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Produto % não encontrado.', p_produto;
    END IF;

    IF p_qtd IS NULL OR p_qtd <= 0 THEN
        RAISE EXCEPTION 'Quantidade inválida: %.', p_qtd;
    END IF;

    -- cria pedido e item (trigger baixa o estoque / valida disponibilidade)
    INSERT INTO tb_pedido (idt_cliente, nme_forma_pagamento)
    VALUES (p_cliente, p_pagamento)
    RETURNING idt_pedido INTO v_pedido;

    INSERT INTO ta_item_pedido (idt_pedido, idt_produto, qtd_item, vlr_unitario)
    VALUES (v_pedido, p_produto, p_qtd, v_preco);

    UPDATE tb_pedido
       SET vlr_total = (SELECT SUM(vlr_subtotal)
                          FROM ta_item_pedido
                         WHERE idt_pedido = v_pedido)
     WHERE idt_pedido = v_pedido;

    RETURN v_pedido;

EXCEPTION
    WHEN raise_exception THEN
        RAISE;                                   -- mantém a mensagem de negócio
    WHEN check_violation THEN
        RAISE EXCEPTION 'Dados inválidos ao registrar pedido: %', SQLERRM;
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Falha inesperada ao registrar pedido (SQLSTATE %): %',
                        SQLSTATE, SQLERRM;
END;
$$;

-- ---------------------------------------------------------------------
-- 2) PROCEDURE sp_cancelar_pedido: cancela pedido e devolve itens ao estoque.
--    Regras: não cancela pedido ENVIADO/ENTREGUE; cancelamento repetido é ignorado.
--    (Pedidos da carga sintética não baixaram estoque; a devolução serve para
--    pedidos criados após os triggers.)
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_cancelar_pedido(p_pedido BIGINT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_status VARCHAR(15);
BEGIN
    SELECT nme_status INTO v_status
      FROM tb_pedido
     WHERE idt_pedido = p_pedido
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pedido % não encontrado.', p_pedido;

    ELSIF v_status = 'CANCELADO' THEN
        RAISE NOTICE 'Pedido % já estava cancelado; nada a fazer.', p_pedido;
        RETURN;

    ELSIF v_status IN ('ENVIADO', 'ENTREGUE') THEN
        RAISE EXCEPTION 'Pedido % está % e não pode mais ser cancelado.', p_pedido, v_status;

    ELSE
        UPDATE tb_produto p
           SET num_estoque = p.num_estoque + i.qtd_item
          FROM ta_item_pedido i
         WHERE i.idt_pedido  = p_pedido
           AND i.idt_produto = p.idt_produto;

        UPDATE tb_pedido SET nme_status = 'CANCELADO' WHERE idt_pedido = p_pedido;

        RAISE NOTICE 'Pedido % cancelado e estoque devolvido.', p_pedido;
    END IF;

EXCEPTION
    WHEN raise_exception THEN
        RAISE;
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Erro ao cancelar pedido % (SQLSTATE %): %', p_pedido, SQLSTATE, SQLERRM;
END;
$$;

-- ---------------------------------------------------------------------
-- TESTES
-- ---------------------------------------------------------------------
-- SELECT fn_registrar_pedido(1, 10, 2, 'PIX');         -- retorna o idt_pedido
-- SELECT fn_registrar_pedido(1, 10, 999999, 'PIX');    -- erro: estoque insuficiente
-- SELECT fn_registrar_pedido(1, 10, 1, 'DINHEIRO');    -- erro: forma de pagamento inválida
-- CALL sp_cancelar_pedido(<id retornado>);             -- devolve estoque
-- CALL sp_cancelar_pedido(<id de pedido ENTREGUE>);    -- erro de regra de negócio
