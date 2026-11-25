-- =====================================================================
-- ALUNO 2 - Estratégia de Indexação + Relatório EXPLAIN ANALYZE
-- Arquivo: 03_otimizacao_indices.sql
--
-- COMO USAR (psql):
--   1) \i 03_otimizacao_indices.sql          -> roda ANTES, cria índices, roda DEPOIS
--   2) Copie "Execution Time", "Planning Time", "Buffers" de cada bloco
--      para a tabela do README.md (seção "Relatório de Desempenho").
-- =====================================================================

\timing on

-- Garante estado "sem índices" (PKs e UNIQUEs permanecem)
DROP INDEX IF EXISTS idx_pedido_cliente_data;
DROP INDEX IF EXISTS idx_item_produto;
DROP INDEX IF EXISTS idx_produto_busca_gin;
ANALYZE;

-- =====================================================================
-- CONSULTAS-ALVO (as mais frequentes de um e-commerce)
-- =====================================================================
-- C1: histórico de pedidos de um cliente em um período
-- C2: total vendido (qtd e receita) de um produto
-- C3: busca textual por nome de produto

-- ---------------------------------------------------------------------
-- >>> ANTES DOS ÍNDICES
-- ---------------------------------------------------------------------
\echo '=== C1 ANTES ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT idt_pedido, dta_pedido, vlr_total
FROM tb_pedido
WHERE idt_cliente = 42
  AND dta_pedido BETWEEN '2025-06-01' AND '2026-06-01'
ORDER BY dta_pedido;

\echo '=== C2 ANTES ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT SUM(qtd_item) AS qtd_vendida, SUM(vlr_subtotal) AS receita
FROM ta_item_pedido
WHERE idt_produto = 150;

\echo '=== C3 ANTES ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT idt_produto, nme_produto, vlr_preco
FROM tb_produto
WHERE to_tsvector('portuguese', nme_produto) @@ to_tsquery('portuguese', 'notebook & pro');

-- ---------------------------------------------------------------------
-- >>> CRIAÇÃO DOS 3 ÍNDICES
-- ---------------------------------------------------------------------

-- IDX 1 - B-Tree COMPOSTO (idt_cliente, dta_pedido)
-- Justificativa: C1 filtra por IGUALDADE em idt_cliente e por FAIXA em dta_pedido,
-- e ordena por dta_pedido. B-Tree é o único tipo que suporta faixa/ordenação, e a
-- ordem (igualdade primeiro, faixa depois) permite varrer só o trecho do cliente já
-- ordenado, eliminando o Sort. Também acelera o JOIN tb_cliente x tb_pedido (FK sem índice
-- automático no PostgreSQL).
CREATE INDEX idx_pedido_cliente_data
    ON tb_pedido USING btree (idt_cliente, dta_pedido);

-- IDX 2 - B-Tree em ta_item_pedido (idt_produto)
-- Justificativa: a PK composta é (idt_pedido, idt_produto); buscas começando por
-- idt_produto NÃO usam a PK. Esse índice atende C2, os JOINs produto x item das
-- consultas de BI (ranking de vendas, faturamento por categoria) e a checagem de FK.
CREATE INDEX idx_item_produto
    ON ta_item_pedido USING btree (idt_produto);

-- IDX 3 - GIN full-text em tb_produto (nme_produto)
-- Justificativa: busca por palavras dentro do nome (C3). B-Tree/Hash só ajudam
-- em igualdade/prefixo do valor inteiro; GIN indexa cada lexema (índice invertido),
-- ideal para tsvector. (Hash foi descartado: só serve para '=' e sem ganho sobre
-- B-Tree nas consultas deste sistema; ex.: nme_status tem apenas 5 valores,
-- baixa seletividade, o índice não seria usado.)
CREATE INDEX idx_produto_busca_gin
    ON tb_produto USING gin (to_tsvector('portuguese', nme_produto));

ANALYZE;

-- ---------------------------------------------------------------------
-- >>> DEPOIS DOS ÍNDICES
-- ---------------------------------------------------------------------
\echo '=== C1 DEPOIS ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT idt_pedido, dta_pedido, vlr_total
FROM tb_pedido
WHERE idt_cliente = 42
  AND dta_pedido BETWEEN '2025-06-01' AND '2026-06-01'
ORDER BY dta_pedido;

\echo '=== C2 DEPOIS ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT SUM(qtd_item) AS qtd_vendida, SUM(vlr_subtotal) AS receita
FROM ta_item_pedido
WHERE idt_produto = 150;

\echo '=== C3 DEPOIS ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT idt_produto, nme_produto, vlr_preco
FROM tb_produto
WHERE to_tsvector('portuguese', nme_produto) @@ to_tsquery('portuguese', 'notebook & pro');

-- Observação: com apenas alguns milhares de linhas o PostgreSQL pode preferir Seq Scan
-- em tabelas pequenas (poucas páginas). Se isso ocorrer, para fins didáticos:
--   SET enable_seqscan = off;   -- (apenas para demonstração; RESET enable_seqscan; depois)
-- ou aumente o volume (ex.: tb_pedido para 10.000 linhas) para evidenciar o ganho.
