-- =====================================================================
-- ALUNO 3 - Consultas Avançadas (DQL / BI)
-- Arquivo: 06_consultas_dql.sql
-- 10 consultas: 4 JOIN+GROUP BY+HAVING | 3 CTE/Subquery | 3 Window Functions
-- Convenção: pedidos CANCELADOS são excluídos da receita.
-- =====================================================================

-- =====================================================================
-- BLOCO A - JOINS (>= 3 tabelas) + GROUP BY + HAVING + agregações
-- =====================================================================

-- Q1. Receita por categoria e fornecedor (4 tabelas), só combinações > R$ 50 mil
SELECT c.nme_categoria,
       f.nme_fornecedor,
       COUNT(DISTINCT i.idt_pedido)         AS qtd_pedidos,
       SUM(i.qtd_item)                      AS qtd_unidades,
       SUM(i.vlr_subtotal)                  AS vlr_receita,
       ROUND(AVG(i.vlr_unitario), 2)        AS vlr_preco_medio
FROM tb_categoria c
JOIN tb_produto       p ON p.idt_categoria  = c.idt_categoria
JOIN tb_fornecedor    f ON f.idt_fornecedor = p.idt_fornecedor
JOIN ta_item_pedido   i ON i.idt_produto    = p.idt_produto
JOIN tb_pedido       pe ON pe.idt_pedido    = i.idt_pedido
WHERE pe.nme_status <> 'CANCELADO'
GROUP BY c.nme_categoria, f.nme_fornecedor
HAVING SUM(i.vlr_subtotal) > 50000
ORDER BY vlr_receita DESC;

-- Q2. Clientes VIP: >= 3 pedidos válidos, com ticket médio e total gasto
SELECT cl.idt_cliente,
       cl.nme_cliente,
       COUNT(DISTINCT pe.idt_pedido)                         AS qtd_pedidos,
       SUM(i.vlr_subtotal)                                   AS vlr_total_gasto,
       ROUND(SUM(i.vlr_subtotal) / COUNT(DISTINCT pe.idt_pedido), 2) AS vlr_ticket_medio
FROM tb_cliente cl
JOIN tb_pedido      pe ON pe.idt_cliente = cl.idt_cliente
JOIN ta_item_pedido  i ON i.idt_pedido   = pe.idt_pedido
WHERE pe.nme_status <> 'CANCELADO'
GROUP BY cl.idt_cliente, cl.nme_cliente
HAVING COUNT(DISTINCT pe.idt_pedido) >= 3
ORDER BY vlr_total_gasto DESC
LIMIT 20;

-- Q3. Receita mensal por forma de pagamento (pedido x item x produto)
SELECT date_trunc('month', pe.dta_pedido)::date  AS dta_mes,
       pe.nme_forma_pagamento,
       COUNT(DISTINCT pe.idt_pedido)             AS qtd_pedidos,
       SUM(i.qtd_item)                           AS qtd_itens,
       SUM(i.vlr_subtotal)                       AS vlr_receita,
       SUM(i.vlr_subtotal - i.qtd_item * p.vlr_custo) AS vlr_lucro_bruto
FROM tb_pedido pe
JOIN ta_item_pedido i ON i.idt_pedido  = pe.idt_pedido
JOIN tb_produto     p ON p.idt_produto = i.idt_produto
WHERE pe.nme_status <> 'CANCELADO'
GROUP BY date_trunc('month', pe.dta_pedido), pe.nme_forma_pagamento
HAVING SUM(i.vlr_subtotal) > 10000
ORDER BY dta_mes, pe.nme_forma_pagamento;

-- Q4. Satisfação por fornecedor (fornecedor x produto x avaliação), mín. 5 avaliações
SELECT f.nme_fornecedor,
       COUNT(a.idt_avaliacao)           AS qtd_avaliacoes,
       ROUND(AVG(a.num_nota), 2)        AS num_nota_media,
       MIN(a.num_nota)                  AS num_nota_minima,
       MAX(a.num_nota)                  AS num_nota_maxima
FROM tb_fornecedor f
JOIN tb_produto   p ON p.idt_fornecedor = f.idt_fornecedor
JOIN tb_avaliacao a ON a.idt_produto    = p.idt_produto
GROUP BY f.nme_fornecedor
HAVING COUNT(a.idt_avaliacao) >= 5
ORDER BY num_nota_media DESC, qtd_avaliacoes DESC;

-- =====================================================================
-- BLOCO B - SUBCONSULTAS CORRELACIONADAS e CTEs (WITH)
-- =====================================================================

-- Q5. (CTE) Clientes que gastam acima da média geral dos clientes
WITH gasto_cliente AS (
    SELECT pe.idt_cliente, SUM(i.vlr_subtotal) AS vlr_gasto
    FROM tb_pedido pe
    JOIN ta_item_pedido i ON i.idt_pedido = pe.idt_pedido
    WHERE pe.nme_status <> 'CANCELADO'
    GROUP BY pe.idt_cliente
),
media_geral AS (
    SELECT AVG(vlr_gasto) AS vlr_media FROM gasto_cliente
)
SELECT c.nme_cliente,
       g.vlr_gasto,
       ROUND(m.vlr_media, 2)                          AS vlr_media_geral,
       ROUND(g.vlr_gasto / m.vlr_media * 100, 1)      AS num_pct_da_media
FROM gasto_cliente g
JOIN media_geral m ON TRUE
JOIN tb_cliente  c ON c.idt_cliente = g.idt_cliente
WHERE g.vlr_gasto > m.vlr_media
ORDER BY g.vlr_gasto DESC;

-- Q6. (Subquery CORRELACIONADA) Produtos com preço acima da média da própria categoria
SELECT p.idt_produto, p.nme_produto, p.vlr_preco,
       (SELECT ROUND(AVG(p2.vlr_preco), 2)
          FROM tb_produto p2
         WHERE p2.idt_categoria = p.idt_categoria)   AS vlr_media_categoria
FROM tb_produto p
WHERE p.vlr_preco > (SELECT AVG(p2.vlr_preco)
                       FROM tb_produto p2
                      WHERE p2.idt_categoria = p.idt_categoria)
ORDER BY p.idt_categoria, p.vlr_preco DESC;

-- Q7. (CTE + NOT EXISTS correlacionado) Produtos ativos SEM venda nos últimos 180 dias
--     (referência = data do último pedido da base)
WITH ref AS (
    SELECT MAX(dta_pedido) AS dta_ref FROM tb_pedido
)
SELECT p.idt_produto, p.nme_produto, p.num_estoque, p.vlr_preco
FROM tb_produto p, ref
WHERE p.flg_ativo
  AND NOT EXISTS (
        SELECT 1
          FROM ta_item_pedido i
          JOIN tb_pedido pe ON pe.idt_pedido = i.idt_pedido
         WHERE i.idt_produto = p.idt_produto
           AND pe.nme_status <> 'CANCELADO'
           AND pe.dta_pedido >= ref.dta_ref - INTERVAL '180 days')
ORDER BY p.num_estoque DESC;

-- =====================================================================
-- BLOCO C - WINDOW FUNCTIONS (OVER / PARTITION BY / ORDER BY)
-- =====================================================================

-- Q8. (RANK + DENSE_RANK) Top 3 produtos por receita dentro de cada categoria
SELECT *
FROM (
    SELECT c.nme_categoria,
           p.nme_produto,
           SUM(i.vlr_subtotal)                                        AS vlr_receita,
           RANK()       OVER (PARTITION BY c.idt_categoria ORDER BY SUM(i.vlr_subtotal) DESC) AS num_rank,
           DENSE_RANK() OVER (PARTITION BY c.idt_categoria ORDER BY SUM(i.vlr_subtotal) DESC) AS num_dense_rank
    FROM tb_categoria c
    JOIN tb_produto     p ON p.idt_categoria = c.idt_categoria
    JOIN ta_item_pedido i ON i.idt_produto   = p.idt_produto
    JOIN tb_pedido     pe ON pe.idt_pedido   = i.idt_pedido AND pe.nme_status <> 'CANCELADO'
    GROUP BY c.idt_categoria, c.nme_categoria, p.idt_produto, p.nme_produto
) t
WHERE num_rank <= 3
ORDER BY nme_categoria, num_rank;

-- Q9. (LAG) Receita mensal e variação percentual vs. mês anterior
WITH mensal AS (
    SELECT date_trunc('month', pe.dta_pedido)::date AS dta_mes,
           SUM(i.vlr_subtotal)                      AS vlr_receita
    FROM tb_pedido pe
    JOIN ta_item_pedido i ON i.idt_pedido = pe.idt_pedido
    WHERE pe.nme_status <> 'CANCELADO'
    GROUP BY 1
)
SELECT dta_mes,
       vlr_receita,
       LAG(vlr_receita) OVER (ORDER BY dta_mes)  AS vlr_receita_mes_anterior,
       ROUND( (vlr_receita - LAG(vlr_receita) OVER (ORDER BY dta_mes))
              / NULLIF(LAG(vlr_receita) OVER (ORDER BY dta_mes), 0) * 100, 1) AS num_variacao_pct
FROM mensal
ORDER BY dta_mes;

-- Q10. (ROW_NUMBER + SUM OVER) Último pedido de cada cliente e gasto acumulado
SELECT idt_cliente, nme_cliente, idt_pedido, dta_pedido, vlr_total, vlr_acumulado
FROM (
    SELECT c.idt_cliente, c.nme_cliente, pe.idt_pedido, pe.dta_pedido, pe.vlr_total,
           SUM(pe.vlr_total) OVER (PARTITION BY c.idt_cliente ORDER BY pe.dta_pedido) AS vlr_acumulado,
           ROW_NUMBER()      OVER (PARTITION BY c.idt_cliente ORDER BY pe.dta_pedido DESC) AS num_ordem
    FROM tb_cliente c
    JOIN tb_pedido pe ON pe.idt_cliente = c.idt_cliente
    WHERE pe.nme_status <> 'CANCELADO'
) t
WHERE num_ordem = 1
ORDER BY vlr_acumulado DESC
LIMIT 30;
