-- =====================================================================
-- PROJETO FINAL BD-II  |  TEMA: E-COMMERCE DE ELETRÔNICOS (PostgreSQL)
-- ALUNO 1 - Modelagem e DDL
-- Arquivo: 01_ddl_estrutura.sql
-- Prefixos: tb_ (tabela), ta_ (tabela associativa), idt_ (identificador),
--           nme_ (texto/nome), vlr_ (valor monetário), num_ (número),
--           qtd_ (quantidade), dta_ (data/hora), flg_ (booleano)
-- =====================================================================

DROP TABLE IF EXISTS tb_log_produto  CASCADE;
DROP TABLE IF EXISTS tb_avaliacao    CASCADE;
DROP TABLE IF EXISTS ta_item_pedido  CASCADE;
DROP TABLE IF EXISTS tb_pedido       CASCADE;
DROP TABLE IF EXISTS tb_produto      CASCADE;
DROP TABLE IF EXISTS tb_cliente      CASCADE;
DROP TABLE IF EXISTS tb_fornecedor   CASCADE;
DROP TABLE IF EXISTS tb_categoria    CASCADE;

-- ---------------------------------------------------------------------
-- 1) tb_categoria  (1:N com tb_produto)
-- ---------------------------------------------------------------------
CREATE TABLE tb_categoria (
    idt_categoria   BIGSERIAL    PRIMARY KEY,
    nme_categoria   VARCHAR(60)  NOT NULL,
    nme_descricao   VARCHAR(200),
    flg_ativo       BOOLEAN      NOT NULL DEFAULT TRUE,
    dta_criacao     TIMESTAMP    NOT NULL DEFAULT now(),
    CONSTRAINT uq_categoria_nome UNIQUE (nme_categoria)          -- UNIQUE 1
);

-- ---------------------------------------------------------------------
-- 2) tb_fornecedor  (1:N com tb_produto)
-- ---------------------------------------------------------------------
CREATE TABLE tb_fornecedor (
    idt_fornecedor  BIGSERIAL    PRIMARY KEY,
    nme_fornecedor  VARCHAR(100) NOT NULL,
    num_cnpj        CHAR(14)     NOT NULL,
    nme_cidade      VARCHAR(60)  NOT NULL,
    flg_ativo       BOOLEAN      NOT NULL DEFAULT TRUE,
    dta_cadastro    TIMESTAMP    NOT NULL DEFAULT now(),
    CONSTRAINT uq_fornecedor_cnpj UNIQUE (num_cnpj)              -- UNIQUE 2
);

-- ---------------------------------------------------------------------
-- 3) tb_cliente  (1:N com tb_pedido e tb_avaliacao)
-- ---------------------------------------------------------------------
CREATE TABLE tb_cliente (
    idt_cliente     BIGSERIAL    PRIMARY KEY,
    nme_cliente     VARCHAR(100) NOT NULL,
    nme_email       VARCHAR(120) NOT NULL,
    num_cpf         CHAR(11)     NOT NULL,
    dta_cadastro    TIMESTAMP    NOT NULL DEFAULT now(),
    flg_ativo       BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_cliente_email UNIQUE (nme_email),              -- UNIQUE 3
    CONSTRAINT uq_cliente_cpf   UNIQUE (num_cpf)                 -- UNIQUE 4
);

-- ---------------------------------------------------------------------
-- 4) tb_produto  (N lado de categoria e fornecedor)
-- ---------------------------------------------------------------------
CREATE TABLE tb_produto (
    idt_produto     BIGSERIAL     PRIMARY KEY,
    idt_categoria   BIGINT        NOT NULL,
    idt_fornecedor  BIGINT        NOT NULL,
    nme_produto     VARCHAR(120)  NOT NULL,
    vlr_preco       DECIMAL(10,2) NOT NULL,
    vlr_custo       DECIMAL(10,2) NOT NULL,
    num_estoque     INTEGER       NOT NULL DEFAULT 0,
    flg_ativo       BOOLEAN       NOT NULL DEFAULT TRUE,
    dta_cadastro    TIMESTAMP     NOT NULL DEFAULT now(),
    CONSTRAINT fk_produto_categoria  FOREIGN KEY (idt_categoria)
        REFERENCES tb_categoria (idt_categoria),
    CONSTRAINT fk_produto_fornecedor FOREIGN KEY (idt_fornecedor)
        REFERENCES tb_fornecedor (idt_fornecedor),
    CONSTRAINT ck_produto_preco   CHECK (vlr_preco > 0),         -- CHECK 1
    CONSTRAINT ck_produto_custo   CHECK (vlr_custo >= 0),        -- CHECK 2
    CONSTRAINT ck_produto_estoque CHECK (num_estoque >= 0)       -- CHECK 3
);

-- ---------------------------------------------------------------------
-- 5) tb_pedido  (TABELA PRINCIPAL; N lado de cliente)
-- ---------------------------------------------------------------------
CREATE TABLE tb_pedido (
    idt_pedido           BIGSERIAL     PRIMARY KEY,
    idt_cliente          BIGINT        NOT NULL,
    dta_pedido           TIMESTAMP     NOT NULL DEFAULT now(),
    nme_status           VARCHAR(15)   NOT NULL DEFAULT 'PENDENTE',
    nme_forma_pagamento  VARCHAR(20)   NOT NULL,
    vlr_total            DECIMAL(12,2) NOT NULL DEFAULT 0,
    vlr_desconto         DECIMAL(10,2) NOT NULL DEFAULT 0,
    dta_entrega          TIMESTAMP,
    CONSTRAINT fk_pedido_cliente FOREIGN KEY (idt_cliente)
        REFERENCES tb_cliente (idt_cliente),
    CONSTRAINT ck_pedido_status CHECK (nme_status IN
        ('PENDENTE','PAGO','ENVIADO','ENTREGUE','CANCELADO')),   -- CHECK 4
    CONSTRAINT ck_pedido_pagto  CHECK (nme_forma_pagamento IN
        ('PIX','CARTAO_CREDITO','CARTAO_DEBITO','BOLETO')),      -- CHECK 5
    CONSTRAINT ck_pedido_valores CHECK (vlr_total >= 0 AND vlr_desconto >= 0), -- CHECK 6
    CONSTRAINT ck_pedido_entrega CHECK (dta_entrega IS NULL OR dta_entrega >= dta_pedido) -- CHECK 7
);

-- ---------------------------------------------------------------------
-- 6) ta_item_pedido  (TABELA ASSOCIATIVA: N:N entre tb_pedido e tb_produto)
-- ---------------------------------------------------------------------
CREATE TABLE ta_item_pedido (
    idt_pedido      BIGINT        NOT NULL,
    idt_produto     BIGINT        NOT NULL,
    qtd_item        INTEGER       NOT NULL,
    vlr_unitario    DECIMAL(10,2) NOT NULL,
    vlr_desconto_item DECIMAL(10,2) NOT NULL DEFAULT 0,
    vlr_subtotal    DECIMAL(12,2) GENERATED ALWAYS AS
                    (qtd_item * vlr_unitario - vlr_desconto_item) STORED,
    CONSTRAINT pk_item_pedido PRIMARY KEY (idt_pedido, idt_produto),
    CONSTRAINT fk_item_pedido  FOREIGN KEY (idt_pedido)
        REFERENCES tb_pedido (idt_pedido) ON DELETE CASCADE,
    CONSTRAINT fk_item_produto FOREIGN KEY (idt_produto)
        REFERENCES tb_produto (idt_produto),
    CONSTRAINT ck_item_qtd   CHECK (qtd_item > 0),               -- CHECK 8
    CONSTRAINT ck_item_valor CHECK (vlr_unitario > 0 AND vlr_desconto_item >= 0)
);

-- ---------------------------------------------------------------------
-- 7) tb_avaliacao  (N:N cliente x produto, com atributos próprios)
-- ---------------------------------------------------------------------
CREATE TABLE tb_avaliacao (
    idt_avaliacao   BIGSERIAL    PRIMARY KEY,
    idt_cliente     BIGINT       NOT NULL,
    idt_produto     BIGINT       NOT NULL,
    num_nota        SMALLINT     NOT NULL,
    nme_titulo      VARCHAR(80)  NOT NULL,
    nme_comentario  VARCHAR(300),
    dta_avaliacao   TIMESTAMP    NOT NULL DEFAULT now(),
    CONSTRAINT fk_avaliacao_cliente FOREIGN KEY (idt_cliente)
        REFERENCES tb_cliente (idt_cliente),
    CONSTRAINT fk_avaliacao_produto FOREIGN KEY (idt_produto)
        REFERENCES tb_produto (idt_produto),
    CONSTRAINT uq_avaliacao_cli_prod UNIQUE (idt_cliente, idt_produto),
    CONSTRAINT ck_avaliacao_nota CHECK (num_nota BETWEEN 1 AND 5) -- CHECK 9
);

-- ---------------------------------------------------------------------
-- 8) tb_log_produto  (TABELA DE AUDITORIA - alimentada por trigger)
--    Sem FK em idt_produto de propósito: o log deve sobreviver ao DELETE
--    do produto auditado.
-- ---------------------------------------------------------------------
CREATE TABLE tb_log_produto (
    idt_log              BIGSERIAL     PRIMARY KEY,
    idt_produto          BIGINT        NOT NULL,
    nme_operacao         VARCHAR(10)   NOT NULL,
    vlr_preco_antigo     DECIMAL(10,2),
    vlr_preco_novo       DECIMAL(10,2),
    num_estoque_antigo   INTEGER,
    dta_operacao         TIMESTAMP     NOT NULL DEFAULT now(),
    nme_usuario          VARCHAR(60)   NOT NULL DEFAULT current_user,
    CONSTRAINT ck_log_operacao CHECK (nme_operacao IN ('UPDATE','DELETE'))
);

-- Comentários de documentação
COMMENT ON TABLE tb_pedido        IS 'Tabela principal do sistema (mín. 500 registros).';
COMMENT ON TABLE ta_item_pedido   IS 'Associativa N:N entre tb_pedido e tb_produto.';
COMMENT ON TABLE tb_log_produto   IS 'Auditoria de UPDATE/DELETE em tb_produto (trigger).';
