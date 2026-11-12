-- =====================================================================
--  Trabalho em Grupo - Banco de Dados I
--  Rede de Hotéis - MODELO FÍSICO (MySQL / MariaDB)
--  Testado no MySQL 8.0.46 e no MariaDB 10.11.14
--
--  Como executar:
--     mysql -u root -p < rede_hoteis.sql
--  (ou abrir no MySQL Workbench / phpMyAdmin / HeidiSQL e executar tudo)
--
--  Todas as tabelas usam ENGINE=InnoDB, que é o mecanismo do MySQL que
--  suporta transações (COMMIT/ROLLBACK) e chaves estrangeiras.
-- =====================================================================

SET NAMES utf8mb4;   -- garante que os acentos sejam gravados corretamente

DROP DATABASE IF EXISTS rede_hoteis;
CREATE DATABASE rede_hoteis
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;
USE rede_hoteis;

-- ---------------------------------------------------------------------
-- HOTEL: cada unidade da rede
-- ---------------------------------------------------------------------
CREATE TABLE hotel (
    id_hotel        INT          NOT NULL AUTO_INCREMENT,
    nome            VARCHAR(100) NOT NULL,
    cidade          VARCHAR(80)  NOT NULL,
    CONSTRAINT pk_hotel PRIMARY KEY (id_hotel)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- CLIENTE: identificado pelo CPF.
--   * endereço (atributo composto) -> uma coluna por componente
--   * idade (atributo derivado)    -> NÃO é armazenada; é calculada
--                                     na view vw_cliente
--   * telefones e e-mails (multivalorados) -> tabelas próprias
-- ---------------------------------------------------------------------
CREATE TABLE cliente (
    cpf             CHAR(11)     NOT NULL,
    nome            VARCHAR(100) NOT NULL,
    rg              VARCHAR(15)  NOT NULL,
    data_nascimento DATE         NOT NULL,
    logradouro      VARCHAR(120) NOT NULL,
    numero          VARCHAR(10)  NOT NULL,      -- texto: aceita "s/n", "120A"
    complemento     VARCHAR(60)  NULL,
    bairro          VARCHAR(60)  NOT NULL,
    cidade          VARCHAR(80)  NOT NULL,
    CONSTRAINT pk_cliente     PRIMARY KEY (cpf),
    CONSTRAINT ck_cliente_cpf CHECK (cpf REGEXP '^[0-9]{11}$')
) ENGINE = InnoDB;

CREATE TABLE telefone_cliente (
    cpf_cliente     CHAR(11)     NOT NULL,
    telefone        VARCHAR(20)  NOT NULL,
    CONSTRAINT pk_telefone_cliente PRIMARY KEY (cpf_cliente, telefone),
    CONSTRAINT fk_telefone_cliente FOREIGN KEY (cpf_cliente)
        REFERENCES cliente (cpf)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE = InnoDB;

CREATE TABLE email_cliente (
    cpf_cliente     CHAR(11)     NOT NULL,
    email           VARCHAR(120) NOT NULL,
    CONSTRAINT pk_email_cliente PRIMARY KEY (cpf_cliente, email),
    CONSTRAINT fk_email_cliente FOREIGN KEY (cpf_cliente)
        REFERENCES cliente (cpf)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- QUARTO: número é único dentro de cada hotel
-- ---------------------------------------------------------------------
CREATE TABLE quarto (
    id_quarto       INT          NOT NULL AUTO_INCREMENT,
    id_hotel        INT          NOT NULL,
    numero          SMALLINT     NOT NULL,
    andar           SMALLINT     NOT NULL,
    qtd_camas       TINYINT      NOT NULL,
    categoria       ENUM('luxo', 'standard') NOT NULL,
    situacao        ENUM('livre', 'ocupado') NOT NULL DEFAULT 'livre',
    CONSTRAINT pk_quarto        PRIMARY KEY (id_quarto),
    CONSTRAINT uq_quarto_numero UNIQUE (id_hotel, numero),
    CONSTRAINT ck_quarto_camas  CHECK (qtd_camas > 0),
    CONSTRAINT fk_quarto_hotel  FOREIGN KEY (id_hotel)
        REFERENCES hotel (id_hotel)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- RESERVA: feita antecipadamente pelo cliente.
--   situacao = 'em_hospedagem' -> o cliente fez check-in (é hóspede)
-- ---------------------------------------------------------------------
CREATE TABLE reserva (
    id_reserva          INT       NOT NULL AUTO_INCREMENT,
    cpf_cliente         CHAR(11)  NOT NULL,
    id_hotel            INT       NOT NULL,
    data_reserva        DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    qtd_pessoas         TINYINT   NOT NULL,
    data_hora_entrada   DATETIME  NOT NULL,     -- período previsto
    data_hora_saida     DATETIME  NOT NULL,
    data_hora_checkin   DATETIME  NULL,         -- preenchido no balcão
    data_hora_checkout  DATETIME  NULL,
    situacao            ENUM('reservada', 'em_hospedagem', 'encerrada', 'cancelada')
                        NOT NULL DEFAULT 'reservada',
    CONSTRAINT pk_reserva          PRIMARY KEY (id_reserva),
    CONSTRAINT ck_reserva_pessoas  CHECK (qtd_pessoas > 0),
    CONSTRAINT ck_reserva_periodo  CHECK (data_hora_saida > data_hora_entrada),
    CONSTRAINT fk_reserva_cliente  FOREIGN KEY (cpf_cliente)
        REFERENCES cliente (cpf)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_reserva_hotel    FOREIGN KEY (id_hotel)
        REFERENCES hotel (id_hotel)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- RESERVA_QUARTO: entidade associativa entre RESERVA e QUARTO.
--   Criada no check-in. É o "relacionamento entre hóspede e quarto"
--   ao qual a copa e a lavanderia vinculam os pedidos.
--   titular_no_quarto indica em qual quarto o próprio cliente dorme.
-- ---------------------------------------------------------------------
CREATE TABLE reserva_quarto (
    id_reserva_quarto   INT       NOT NULL AUTO_INCREMENT,
    id_reserva          INT       NOT NULL,
    id_quarto           INT       NOT NULL,
    titular_no_quarto   BOOLEAN   NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_reserva_quarto PRIMARY KEY (id_reserva_quarto),
    CONSTRAINT uq_reserva_quarto UNIQUE (id_reserva, id_quarto),
    CONSTRAINT fk_rq_reserva FOREIGN KEY (id_reserva)
        REFERENCES reserva (id_reserva)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_rq_quarto  FOREIGN KEY (id_quarto)
        REFERENCES quarto (id_quarto)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- ACOMPANHANTE e ACOMPANHANTE_QUARTO (quem ocupa cada quarto)
-- ---------------------------------------------------------------------
CREATE TABLE acompanhante (
    cpf             CHAR(11)     NOT NULL,
    rg              VARCHAR(15)  NOT NULL,
    nome            VARCHAR(100) NOT NULL,
    CONSTRAINT pk_acompanhante     PRIMARY KEY (cpf),
    CONSTRAINT ck_acompanhante_cpf CHECK (cpf REGEXP '^[0-9]{11}$')
) ENGINE = InnoDB;

CREATE TABLE acompanhante_quarto (
    id_reserva_quarto   INT       NOT NULL,
    cpf_acompanhante    CHAR(11)  NOT NULL,
    CONSTRAINT pk_acompanhante_quarto PRIMARY KEY (id_reserva_quarto, cpf_acompanhante),
    CONSTRAINT fk_aq_reserva_quarto FOREIGN KEY (id_reserva_quarto)
        REFERENCES reserva_quarto (id_reserva_quarto)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_aq_acompanhante   FOREIGN KEY (cpf_acompanhante)
        REFERENCES acompanhante (cpf)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- COPA: cardápio, pedido (cabeçalho) e itens do pedido
--   valor_unitario em item_pedido_copa = preço cobrado no momento do
--   pedido (histórico); o cardápio pode mudar de preço depois.
-- ---------------------------------------------------------------------
CREATE TABLE item_cardapio (
    codigo          INT           NOT NULL AUTO_INCREMENT,
    nome            VARCHAR(80)   NOT NULL,
    descricao       VARCHAR(500)  NOT NULL,
    preco_unitario  DECIMAL(10,2) NOT NULL,
    unidade         VARCHAR(20)   NOT NULL,     -- ex.: lata, porção, unidade
    categoria       ENUM('bebida', 'prato', 'lanche') NOT NULL,
    CONSTRAINT pk_item_cardapio    PRIMARY KEY (codigo),
    CONSTRAINT ck_cardapio_preco   CHECK (preco_unitario >= 0)
) ENGINE = InnoDB;

CREATE TABLE pedido_copa (
    id_pedido_copa      INT       NOT NULL AUTO_INCREMENT,
    id_reserva_quarto   INT       NOT NULL,
    data_hora           DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_pedido_copa PRIMARY KEY (id_pedido_copa),
    CONSTRAINT fk_pc_reserva_quarto FOREIGN KEY (id_reserva_quarto)
        REFERENCES reserva_quarto (id_reserva_quarto)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB;

CREATE TABLE item_pedido_copa (
    id_pedido_copa  INT           NOT NULL,
    codigo_item     INT           NOT NULL,
    quantidade      INT           NOT NULL,
    valor_unitario  DECIMAL(10,2) NOT NULL,
    CONSTRAINT pk_item_pedido_copa PRIMARY KEY (id_pedido_copa, codigo_item),
    CONSTRAINT ck_ipc_quantidade   CHECK (quantidade > 0),
    CONSTRAINT ck_ipc_valor        CHECK (valor_unitario >= 0),
    CONSTRAINT fk_ipc_pedido FOREIGN KEY (id_pedido_copa)
        REFERENCES pedido_copa (id_pedido_copa)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_ipc_item   FOREIGN KEY (codigo_item)
        REFERENCES item_cardapio (codigo)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- LAVANDERIA: mesma estrutura da copa
--   quantidade é DECIMAL porque há serviços cobrados por kg
-- ---------------------------------------------------------------------
CREATE TABLE item_lavanderia (
    codigo          INT           NOT NULL AUTO_INCREMENT,
    descricao       VARCHAR(200)  NOT NULL,
    valor_unitario  DECIMAL(10,2) NOT NULL,
    unidade         VARCHAR(20)   NOT NULL,     -- ex.: peça, kg
    CONSTRAINT pk_item_lavanderia  PRIMARY KEY (codigo),
    CONSTRAINT ck_lavanderia_valor CHECK (valor_unitario >= 0)
) ENGINE = InnoDB;

CREATE TABLE pedido_lavanderia (
    id_pedido_lavanderia INT      NOT NULL AUTO_INCREMENT,
    id_reserva_quarto    INT      NOT NULL,
    data_hora            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_pedido_lavanderia PRIMARY KEY (id_pedido_lavanderia),
    CONSTRAINT fk_pl_reserva_quarto FOREIGN KEY (id_reserva_quarto)
        REFERENCES reserva_quarto (id_reserva_quarto)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB;

CREATE TABLE item_pedido_lavanderia (
    id_pedido_lavanderia INT           NOT NULL,
    codigo_item          INT           NOT NULL,
    quantidade           DECIMAL(8,2)  NOT NULL,
    valor_unitario       DECIMAL(10,2) NOT NULL,
    CONSTRAINT pk_item_pedido_lavanderia PRIMARY KEY (id_pedido_lavanderia, codigo_item),
    CONSTRAINT ck_ipl_quantidade CHECK (quantidade > 0),
    CONSTRAINT ck_ipl_valor      CHECK (valor_unitario >= 0),
    CONSTRAINT fk_ipl_pedido FOREIGN KEY (id_pedido_lavanderia)
        REFERENCES pedido_lavanderia (id_pedido_lavanderia)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_ipl_item   FOREIGN KEY (codigo_item)
        REFERENCES item_lavanderia (codigo)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB;

-- =====================================================================
--  VIEWS
-- =====================================================================

-- Cliente com a idade calculada a partir da data de nascimento
CREATE VIEW vw_cliente AS
SELECT c.cpf,
       c.nome,
       c.rg,
       c.data_nascimento,
       TIMESTAMPDIFF(YEAR, c.data_nascimento, CURDATE()) AS idade,
       c.logradouro,
       c.numero,
       c.complemento,
       c.bairro,
       c.cidade
FROM cliente c;

-- Quem ocupa cada quarto nas hospedagens em andamento
CREATE VIEW vw_ocupacao_quartos AS
SELECT h.nome          AS hotel,
       q.numero        AS quarto,
       q.categoria,
       r.id_reserva,
       c.nome          AS hospede_responsavel,
       CONCAT_WS(', ',
                 IF(rq.titular_no_quarto, c.nome, NULL),
                 GROUP_CONCAT(a.nome ORDER BY a.nome SEPARATOR ', ')
       )               AS ocupantes
FROM reserva_quarto rq
JOIN reserva r                ON r.id_reserva = rq.id_reserva
JOIN cliente c                ON c.cpf = r.cpf_cliente
JOIN quarto q                 ON q.id_quarto = rq.id_quarto
JOIN hotel h                  ON h.id_hotel = q.id_hotel
LEFT JOIN acompanhante_quarto aq ON aq.id_reserva_quarto = rq.id_reserva_quarto
LEFT JOIN acompanhante a         ON a.cpf = aq.cpf_acompanhante
WHERE r.situacao = 'em_hospedagem'
GROUP BY rq.id_reserva_quarto, h.nome, q.numero, q.categoria,
         r.id_reserva, c.nome, rq.titular_no_quarto;

-- Extrato de serviços (copa + lavanderia) por reserva e quarto
CREATE VIEW vw_extrato_servicos AS
SELECT rq.id_reserva, q.numero AS quarto, 'copa' AS servico,
       p.data_hora, i.nome AS item, ip.quantidade, ip.valor_unitario,
       CAST(ip.quantidade * ip.valor_unitario AS DECIMAL(10,2)) AS subtotal
FROM item_pedido_copa ip
JOIN pedido_copa p     ON p.id_pedido_copa = ip.id_pedido_copa
JOIN item_cardapio i   ON i.codigo = ip.codigo_item
JOIN reserva_quarto rq ON rq.id_reserva_quarto = p.id_reserva_quarto
JOIN quarto q          ON q.id_quarto = rq.id_quarto
UNION ALL
SELECT rq.id_reserva, q.numero, 'lavanderia',
       p.data_hora, i.descricao, ip.quantidade, ip.valor_unitario,
       CAST(ip.quantidade * ip.valor_unitario AS DECIMAL(10,2))
FROM item_pedido_lavanderia ip
JOIN pedido_lavanderia p ON p.id_pedido_lavanderia = ip.id_pedido_lavanderia
JOIN item_lavanderia i   ON i.codigo = ip.codigo_item
JOIN reserva_quarto rq   ON rq.id_reserva_quarto = p.id_reserva_quarto
JOIN quarto q            ON q.id_quarto = rq.id_quarto;

-- =====================================================================
--  DADOS DE EXEMPLO (fictícios; CPFs gerados com dígito verificador válido)
-- =====================================================================

INSERT INTO hotel (id_hotel, nome, cidade) VALUES
    (1, 'Hotel Guaíba Centro', 'Porto Alegre'),
    (2, 'Hotel Serra Gaúcha',  'Gramado');

INSERT INTO cliente (cpf, nome, rg, data_nascimento, logradouro, numero, complemento, bairro, cidade) VALUES
    ('52601815906', 'Ana Paula Ferreira',  '1023456789', '1985-03-14', 'Rua dos Andradas',     '1200', 'Apto 501', 'Centro Histórico', 'Porto Alegre'),
    ('08301661305', 'Carlos Eduardo Silva','2034567891', '1978-11-02', 'Av. Ipiranga',         '6681', NULL,       'Partenon',         'Porto Alegre'),
    ('18609139034', 'Mariana Costa Lima',  '3045678912', '1992-07-21', 'Rua Pinheiro Machado', '455',  NULL,       'São Pelegrino',    'Caxias do Sul'),
    ('99603082430', 'João Pedro Souza',    '4056789123', '2000-01-30', 'Rua Sete de Setembro', '88',   'Casa 2',   'Centro',           'Pelotas');

INSERT INTO telefone_cliente (cpf_cliente, telefone) VALUES
    ('52601815906', '(51) 99876-5432'),
    ('52601815906', '(51) 3221-4455'),
    ('08301661305', '(51) 98765-1122'),
    ('18609139034', '(54) 99123-7788'),
    ('99603082430', '(53) 98111-2233');

INSERT INTO email_cliente (cpf_cliente, email) VALUES
    ('52601815906', 'ana.ferreira@email.com'),
    ('08301661305', 'carlos.silva@email.com'),
    ('08301661305', 'cadu.silva@trabalho.com'),
    ('18609139034', 'mariana.lima@email.com'),
    ('99603082430', 'joao.souza@email.com');

INSERT INTO quarto (id_quarto, id_hotel, numero, andar, qtd_camas, categoria, situacao) VALUES
    (1, 1, 101, 1, 2, 'standard', 'ocupado'),
    (2, 1, 102, 1, 3, 'standard', 'ocupado'),
    (3, 1, 201, 2, 2, 'luxo',     'ocupado'),
    (4, 1, 202, 2, 1, 'luxo',     'livre'),
    (5, 1, 301, 3, 4, 'standard', 'livre'),
    (6, 2, 101, 1, 2, 'standard', 'livre'),
    (7, 2, 102, 1, 2, 'standard', 'livre'),
    (8, 2, 201, 2, 2, 'luxo',     'livre');

INSERT INTO reserva (id_reserva, cpf_cliente, id_hotel, data_reserva, qtd_pessoas,
                     data_hora_entrada, data_hora_saida, data_hora_checkin, data_hora_checkout, situacao) VALUES
    (1, '52601815906', 1, '2026-09-01 10:15:00', 4, '2026-09-28 14:00:00', '2026-10-03 12:00:00', '2026-09-28 14:35:00', NULL, 'em_hospedagem'),
    (2, '08301661305', 1, '2026-09-20 18:40:00', 2, '2026-09-30 15:00:00', '2026-10-02 11:00:00', '2026-09-30 15:20:00', NULL, 'em_hospedagem'),
    (3, '18609139034', 2, '2026-09-25 09:05:00', 1, '2026-10-15 14:00:00', '2026-10-18 12:00:00', NULL, NULL, 'reservada'),
    (4, '99603082430', 1, '2026-07-30 21:00:00', 2, '2026-08-10 14:00:00', '2026-08-12 12:00:00', '2026-08-10 14:10:00', '2026-08-12 11:30:00', 'encerrada');

-- Reserva 1 (família): dois quartos; reserva 2 e 4: um quarto
INSERT INTO reserva_quarto (id_reserva_quarto, id_reserva, id_quarto, titular_no_quarto) VALUES
    (1, 1, 3, TRUE),     -- Ana no 201
    (2, 1, 2, FALSE),    -- filhos da Ana no 102
    (3, 2, 1, TRUE),     -- Carlos no 101
    (4, 4, 5, TRUE);     -- João no 301 (hospedagem encerrada)

INSERT INTO acompanhante (cpf, rg, nome) VALUES
    ('62819482112', '5067891234', 'Roberto Ferreira'),
    ('99351819019', '6078912345', 'Pedro Ferreira'),
    ('93786579741', '7089123456', 'Júlia Ferreira'),
    ('54323194897', '8091234567', 'Fernanda Silva'),
    ('75749118606', '9012345678', 'Bruno Alves');

INSERT INTO acompanhante_quarto (id_reserva_quarto, cpf_acompanhante) VALUES
    (1, '62819482112'),  -- Roberto com a Ana no 201
    (2, '99351819019'),  -- Pedro no 102
    (2, '93786579741'),  -- Júlia no 102
    (3, '54323194897'),  -- Fernanda com o Carlos no 101
    (4, '75749118606');  -- Bruno com o João no 301

INSERT INTO item_cardapio (codigo, nome, descricao, preco_unitario, unidade, categoria) VALUES
    (1, 'Água mineral',        'Água mineral sem gás, garrafa de 500 ml',                         5.00, 'garrafa', 'bebida'),
    (2, 'Refrigerante',        'Refrigerante em lata de 350 ml (cola, guaraná ou laranja)',       7.00, 'lata',    'bebida'),
    (3, 'Cerveja long neck',   'Cerveja pilsen, garrafa long neck de 355 ml',                    12.00, 'garrafa', 'bebida'),
    (4, 'Filé à parmegiana',   'Filé bovino empanado com molho de tomate e queijo, arroz e fritas', 68.00, 'porção',  'prato'),
    (5, 'Risoto de cogumelos', 'Arroz arbóreo com cogumelos frescos e parmesão',                 59.00, 'porção',  'prato'),
    (6, 'Sanduíche natural',   'Pão integral, frango desfiado, cenoura e requeijão',             22.00, 'unidade', 'lanche'),
    (7, 'Torrada com queijo',  'Pão de forma tostado com queijo derretido',                      15.00, 'unidade', 'lanche');

INSERT INTO item_lavanderia (codigo, descricao, valor_unitario, unidade) VALUES
    (1, 'Lavagem de camisa',              12.00, 'peça'),
    (2, 'Lavagem e passagem de calça',    15.00, 'peça'),
    (3, 'Lavagem de roupas por quilo',    25.00, 'kg'),
    (4, 'Lavagem a seco de terno',        45.00, 'peça');

INSERT INTO pedido_copa (id_pedido_copa, id_reserva_quarto, data_hora) VALUES
    (1, 4, '2026-08-11 19:00:00'),
    (2, 1, '2026-09-28 20:10:00'),
    (3, 2, '2026-09-29 16:00:00'),
    (4, 3, '2026-09-30 21:30:00');

-- O pedido 1 foi feito quando a torrada custava R$ 14,00:
-- o valor cobrado fica registrado no item do pedido.
INSERT INTO item_pedido_copa (id_pedido_copa, codigo_item, quantidade, valor_unitario) VALUES
    (1, 7, 2, 14.00),
    (1, 2, 2,  7.00),
    (2, 4, 2, 68.00),
    (2, 2, 2,  7.00),
    (3, 6, 2, 22.00),
    (3, 1, 2,  5.00),
    (4, 5, 1, 59.00),
    (4, 3, 2, 12.00);

INSERT INTO pedido_lavanderia (id_pedido_lavanderia, id_reserva_quarto, data_hora) VALUES
    (1, 1, '2026-09-29 09:00:00'),
    (2, 3, '2026-10-01 08:30:00');

INSERT INTO item_pedido_lavanderia (id_pedido_lavanderia, codigo_item, quantidade, valor_unitario) VALUES
    (1, 1, 3.00, 12.00),
    (1, 2, 2.00, 15.00),
    (2, 3, 2.50, 25.00);

-- =====================================================================
--  CONSULTAS DE EXEMPLO
-- =====================================================================

-- 1) Clientes com idade, telefones e e-mails
SELECT v.cpf, v.nome, v.idade,
       (SELECT GROUP_CONCAT(t.telefone SEPARATOR ' / ')
          FROM telefone_cliente t WHERE t.cpf_cliente = v.cpf) AS telefones,
       (SELECT GROUP_CONCAT(e.email SEPARATOR ' / ')
          FROM email_cliente e WHERE e.cpf_cliente = v.cpf)    AS emails
FROM vw_cliente v
ORDER BY v.nome;

-- 2) Quem ocupa cada quarto agora
SELECT * FROM vw_ocupacao_quartos ORDER BY hotel, quarto;

-- 3) Quartos livres por hotel e categoria (usados no check-in)
SELECT h.nome AS hotel, q.numero, q.andar, q.qtd_camas, q.categoria
FROM quarto q
JOIN hotel h ON h.id_hotel = q.id_hotel
WHERE q.situacao = 'livre'
ORDER BY h.nome, q.numero;

-- 4) Total de serviços consumidos por reserva
SELECT id_reserva, servico, SUM(subtotal) AS total
FROM vw_extrato_servicos
GROUP BY id_reserva, servico
ORDER BY id_reserva, servico;
