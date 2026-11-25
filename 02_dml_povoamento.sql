-- =====================================================================
-- ALUNO 2 - Povoamento DML (dados sintéticos)
-- Arquivo: 02_dml_povoamento.sql
-- Executar APÓS 01_ddl_estrutura.sql e ANTES de 04_plpgsql_triggers.sql
-- (assim a carga em massa não dispara a baixa de estoque nem a auditoria).
--
-- Volume gerado:
--   tb_categoria 10 | tb_fornecedor 30 | tb_cliente 500 | tb_produto 300
--   tb_pedido 1500  | ta_item_pedido ~2500 | tb_avaliacao 600
--   TOTAL ~ 5.440 registros (mín. exigido: 1.000; tb_pedido >= 500)
-- =====================================================================

SELECT setseed(0.42);   -- torna a carga reproduzível

BEGIN;

-- 1) Categorias ---------------------------------------------------------
INSERT INTO tb_categoria (nme_categoria, nme_descricao)
SELECT n, 'Categoria de ' || lower(n)
FROM unnest(ARRAY['Smartphone','Notebook','Fone de Ouvido','Monitor','Teclado',
                  'Mouse','Webcam','Tablet','Caixa de Som','Smartwatch']) AS n;

-- 2) Fornecedores (30) --------------------------------------------------
INSERT INTO tb_fornecedor (nme_fornecedor, num_cnpj, nme_cidade, dta_cadastro)
SELECT 'Fornecedor ' || g || ' Ltda',
       lpad(g::text, 14, '0'),
       (ARRAY['Brasília','São Paulo','Rio de Janeiro','Curitiba','Belo Horizonte',
              'Porto Alegre','Goiânia','Recife'])[1 + g % 8],
       timestamp '2024-01-01' + random() * interval '300 days'
FROM generate_series(1, 30) g;

-- 3) Clientes (500) -----------------------------------------------------
INSERT INTO tb_cliente (nme_cliente, nme_email, num_cpf, dta_cadastro, flg_ativo)
SELECT (ARRAY['Ana','Bruno','Carla','Diego','Eduarda','Felipe','Gabriela','Henrique',
              'Isabela','João','Kauan','Larissa','Marcos','Natália','Otávio','Paula'])[1 + g % 16]
       || ' ' ||
       (ARRAY['Silva','Souza','Oliveira','Santos','Pereira','Lima','Costa','Ribeiro',
              'Almeida','Carvalho'])[1 + (g / 16) % 10],
       'cliente' || g || '@email.com',
       lpad(g::text, 11, '0'),
       timestamp '2024-06-01' + random() * interval '400 days',
       (random() > 0.05)
FROM generate_series(1, 500) g;

-- 4) Produtos (300) - categoria = (g % 10) + 1 -------------------------
INSERT INTO tb_produto (idt_categoria, idt_fornecedor, nme_produto,
                        vlr_preco, vlr_custo, num_estoque, flg_ativo, dta_cadastro)
SELECT c.idt_categoria,
       1 + (g % 30),
       c.nme_categoria || ' ' ||
       (ARRAY['Nova','Prime','Max','Lite','Pro','Ultra'])[1 + g % 6] || ' ' ||
       (ARRAY['Alpha','Beta','Gama','Delta','Sigma'])[1 + (g / 6) % 5] || ' ' || g,
       p.preco,
       round(p.preco * 0.6, 2),
       50 + floor(random() * 450)::int,
       (random() > 0.03),
       timestamp '2024-02-01' + random() * interval '300 days'
FROM generate_series(1, 300) g
JOIN tb_categoria c ON c.idt_categoria = (g % 10) + 1
CROSS JOIN LATERAL (SELECT round((50 + random() * 4950)::numeric, 2) AS preco) p;

-- 5) Pedidos (1.500) - TABELA PRINCIPAL ---------------------------------
INSERT INTO tb_pedido (idt_cliente, dta_pedido, nme_status, nme_forma_pagamento, vlr_desconto)
SELECT 1 + floor(random() * 500)::int,
       timestamp '2025-01-01' + random() * interval '690 days',
       (ARRAY['PENDENTE','PAGO','ENVIADO','ENTREGUE','ENTREGUE','ENTREGUE','CANCELADO'])
           [1 + floor(random() * 7)::int],
       (ARRAY['PIX','CARTAO_CREDITO','CARTAO_DEBITO','BOLETO'])[1 + floor(random() * 4)::int],
       0
FROM generate_series(1, 1500);

-- 6) Itens (1 a 3 produtos distintos por pedido) ------------------------
--    (idt_pedido*7 + k*53) % 300 + 1  => produtos distintos para k = 1..3
INSERT INTO ta_item_pedido (idt_pedido, idt_produto, qtd_item, vlr_unitario)
SELECT p.idt_pedido,
       pr.idt_produto,
       1 + floor(random() * 3)::int,
       pr.vlr_preco
FROM tb_pedido p
CROSS JOIN generate_series(1, 3) k
JOIN tb_produto pr ON pr.idt_produto = ((p.idt_pedido * 7 + k * 53) % 300) + 1
WHERE k = 1
   OR (k = 2 AND p.idt_pedido % 2 = 0)
   OR (k = 3 AND p.idt_pedido % 3 = 0);

-- 7) Ajusta totais e data de entrega dos pedidos ------------------------
UPDATE tb_pedido p
SET vlr_total = t.total
FROM (SELECT idt_pedido, SUM(vlr_subtotal) AS total
      FROM ta_item_pedido GROUP BY idt_pedido) t
WHERE t.idt_pedido = p.idt_pedido;

UPDATE tb_pedido
SET dta_entrega = dta_pedido + (3 + floor(random() * 10)) * interval '1 day'
WHERE nme_status = 'ENTREGUE';

-- 8) Avaliações (600, pares cliente/produto distintos) ------------------
INSERT INTO tb_avaliacao (idt_cliente, idt_produto, num_nota, nme_titulo, nme_comentario, dta_avaliacao)
SELECT (g % 500) + 1,
       ((g * 37) % 300) + 1,
       1 + floor(random() * 5)::int,
       (ARRAY['Excelente','Muito bom','Ok','Poderia ser melhor','Não recomendo'])[1 + g % 5],
       'Comentário automático da avaliação ' || g,
       timestamp '2025-02-01' + random() * interval '650 days'
FROM generate_series(1, 600) g;

COMMIT;

-- Atualiza estatísticas para o otimizador
ANALYZE;

-- Conferência rápida do volume
SELECT 'tb_categoria' AS tabela, COUNT(*) FROM tb_categoria UNION ALL
SELECT 'tb_fornecedor',          COUNT(*) FROM tb_fornecedor UNION ALL
SELECT 'tb_cliente',             COUNT(*) FROM tb_cliente    UNION ALL
SELECT 'tb_produto',             COUNT(*) FROM tb_produto    UNION ALL
SELECT 'tb_pedido',              COUNT(*) FROM tb_pedido     UNION ALL
SELECT 'ta_item_pedido',         COUNT(*) FROM ta_item_pedido UNION ALL
SELECT 'tb_avaliacao',           COUNT(*) FROM tb_avaliacao;
