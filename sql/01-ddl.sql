CREATE SCHEMA IF NOT EXISTS liga_facom;
SET search_path TO liga_facom;

CREATE TABLE tecnico (
    id_tecnico SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    apelido VARCHAR(50) NOT NULL,
    data_cadastro DATE NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE time (
    id_time SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    patrimonio NUMERIC(10,2) NOT NULL DEFAULT 100.00 CHECK (patrimonio >= 0),
    id_tecnico INTEGER NOT NULL UNIQUE,
    CONSTRAINT fk_time_tecnico FOREIGN KEY (id_tecnico) REFERENCES tecnico(id_tecnico) 
        ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE liga (
    id_liga SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    descricao TEXT,
    codigo_convite VARCHAR(20) UNIQUE,
    limite_participantes INTEGER CHECK (limite_participantes > 0),
    publica BOOLEAN NOT NULL DEFAULT TRUE,
    id_dono INTEGER NOT NULL,
    CONSTRAINT fk_liga_dono FOREIGN KEY (id_dono) REFERENCES tecnico(id_tecnico) 
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE participa (
    id_tecnico INTEGER NOT NULL,
    id_liga INTEGER NOT NULL,
    data_entrada DATE NOT NULL DEFAULT CURRENT_DATE,
    PRIMARY KEY (id_tecnico, id_liga),
    CONSTRAINT fk_participa_tecnico FOREIGN KEY (id_tecnico) REFERENCES tecnico(id_tecnico) 
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_participa_liga FOREIGN KEY (id_liga) REFERENCES liga(id_liga) 
        ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE clube (
    id_clube INTEGER PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    abreviacao CHAR(3) NOT NULL,
    url_escudo TEXT
);

CREATE TABLE posicao (
    id_posicao INTEGER PRIMARY KEY,
    nome VARCHAR(50) NOT NULL,
    abreviacao VARCHAR(5) NOT NULL
);

CREATE TABLE situacao (
    id_situacao INTEGER PRIMARY KEY,
    descricao VARCHAR(50) NOT NULL
);

CREATE TABLE atleta (
    id_atleta INTEGER PRIMARY KEY,
    nome_completo VARCHAR(150) NOT NULL,
    apelido VARCHAR(100) NOT NULL,
    id_posicao INTEGER NOT NULL,
    id_situacao INTEGER NOT NULL,
    CONSTRAINT fk_atleta_posicao FOREIGN KEY (id_posicao) REFERENCES posicao(id_posicao) 
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_atleta_situacao FOREIGN KEY (id_situacao) REFERENCES situacao(id_situacao) 
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE rodada (
    numero INTEGER PRIMARY KEY CHECK (numero BETWEEN 1 AND 38),
    estado VARCHAR(20) NOT NULL DEFAULT 'Aberta' 
        CHECK (estado IN ('Aberta', 'Fechada', 'Consolidada'))
);

CREATE TABLE desempenho_na_rodada (
    id_atleta INTEGER NOT NULL,
    numero_rodada INTEGER NOT NULL,
    preco NUMERIC(10,2) NOT NULL CHECK (preco >= 1.00),
    entrou_em_campo BOOLEAN NOT NULL DEFAULT FALSE,
    pontuacao NUMERIC(5,2) DEFAULT 0.00,
    PRIMARY KEY (id_atleta, numero_rodada),
    CONSTRAINT fk_desempenho_atleta FOREIGN KEY (id_atleta) REFERENCES atleta(id_atleta) 
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_desempenho_rodada FOREIGN KEY (numero_rodada) REFERENCES rodada(numero) 
        ON DELETE CASCADE ON UPDATE CASCADE
);