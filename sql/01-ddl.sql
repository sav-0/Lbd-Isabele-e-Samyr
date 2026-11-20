-- Usamos NUMERIC para cartoletas e pontuações, e não REAL ou DOUBLE PRECISION.
-- REAL e DOUBLE guardam valores aproximados (0.1 + 0.2 dá 0.30000000000000004),
-- o que daria erro de centavos no patrimônio e nas pontuações.
-- NUMERIC guarda o valor exato.
--
-- Em todas as FKs usamos ON UPDATE CASCADE: se uma chave mudar, a mudança vai junto.
-- ON DELETE CASCADE: quando a linha não faz sentido sem a outra.
-- ON DELETE RESTRICT: quando apagar faria perder histórico ou dados ainda usados.

CREATE SCHEMA IF NOT EXISTS liga_facom;
SET search_path TO liga_facom;

CREATE TABLE tecnico (
    id_tecnico SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    apelido VARCHAR(50) NOT NULL,
    data_cadastro DATE NOT NULL DEFAULT CURRENT_DATE
);

-- CASCADE: não existe time sem técnico.
CREATE TABLE time (
    id_time SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    patrimonio NUMERIC(10,2) NOT NULL DEFAULT 100.00 CHECK (patrimonio >= 0),
    id_tecnico INTEGER NOT NULL UNIQUE,
    CONSTRAINT fk_time_tecnico FOREIGN KEY (id_tecnico) REFERENCES tecnico(id_tecnico) 
        ON DELETE CASCADE ON UPDATE CASCADE
);

-- RESTRICT: não pode apagar um técnico que é dono de liga, a liga ficaria sem dono.
CREATE TABLE liga (
    id_liga SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    descricao TEXT,
    codigo_convite VARCHAR(20) NOT NULL UNIQUE,
    limite_participantes INTEGER NOT NULL CHECK (limite_participantes > 0),
    publica BOOLEAN NOT NULL DEFAULT TRUE,
    id_dono INTEGER NOT NULL,
    CONSTRAINT fk_liga_dono FOREIGN KEY (id_dono) REFERENCES tecnico(id_tecnico) 
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CASCADE: a participação só existe se o técnico e a liga existirem.
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
    url_escudo TEXT,
    CONSTRAINT ck_clube_abreviacao CHECK (char_length(abreviacao) = 3)
);

CREATE TABLE posicao (
    id_posicao INTEGER PRIMARY KEY,
    nome VARCHAR(50) NOT NULL UNIQUE,
    abreviacao VARCHAR(5) NOT NULL UNIQUE,
    CONSTRAINT ck_posicao_abreviacao CHECK (abreviacao IN ('gol', 'lat', 'zag', 'mei', 'ata', 'tec'))
);

CREATE TABLE situacao (
    id_situacao INTEGER PRIMARY KEY,
    descricao VARCHAR(50) NOT NULL UNIQUE
);

-- RESTRICT: não pode apagar uma posição ou situação que algum atleta usa.
-- nome_completo e id_situacao aceitam NULL porque atletas que só aparecem
-- nos pontuados de rodadas antigas (e não estão mais no mercado) não têm esses dados na API.
CREATE TABLE atleta (
    id_atleta INTEGER PRIMARY KEY,
    nome_completo VARCHAR(150),
    apelido VARCHAR(100) NOT NULL,
    id_posicao INTEGER NOT NULL,
    id_situacao INTEGER,
    CONSTRAINT fk_atleta_posicao FOREIGN KEY (id_posicao) REFERENCES posicao(id_posicao) 
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_atleta_situacao FOREIGN KEY (id_situacao) REFERENCES situacao(id_situacao) 
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- O estado 'Futura' foi adicionado para poder subir as 38 rodadas na carga sem quebrar
-- a regra de só uma rodada aberta por vez. Ele é a rodada que ainda não começou.
-- Ordem dos estados: Futura -> Aberta -> Fechada -> Consolidada.
CREATE TABLE rodada (
    numero INTEGER PRIMARY KEY CHECK (numero BETWEEN 1 AND 38),
    estado VARCHAR(20) NOT NULL DEFAULT 'Futura'
        CHECK (estado IN ('Futura', 'Aberta', 'Fechada', 'Consolidada'))
);

-- CASCADE: o desempenho só existe se o atleta e a rodada existirem.
CREATE TABLE desempenho_na_rodada (
    id_atleta INTEGER NOT NULL,
    numero_rodada INTEGER NOT NULL,
    preco NUMERIC(10,2) NOT NULL CHECK (preco >= 1.00),
    entrou_em_campo BOOLEAN NOT NULL DEFAULT FALSE,
    pontuacao NUMERIC(5,2) NOT NULL DEFAULT 0.00,
    PRIMARY KEY (id_atleta, numero_rodada),
    CONSTRAINT fk_desempenho_atleta FOREIGN KEY (id_atleta) REFERENCES atleta(id_atleta) 
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_desempenho_rodada FOREIGN KEY (numero_rodada) REFERENCES rodada(numero)
        ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE esquema_tatico (
    id_esquema INTEGER PRIMARY KEY,
    nome VARCHAR(10) NOT NULL UNIQUE
);

-- CASCADE no esquema: as quantidades fazem parte do esquema.
-- RESTRICT na posição: não pode apagar uma posição usada em um esquema.
CREATE TABLE exige (
    id_esquema INTEGER NOT NULL,
    id_posicao INTEGER NOT NULL,
    quantidade INTEGER NOT NULL CHECK (quantidade >= 0),
    PRIMARY KEY (id_esquema, id_posicao),
    CONSTRAINT fk_exige_esquema FOREIGN KEY (id_esquema) REFERENCES esquema_tatico(id_esquema)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_exige_posicao FOREIGN KEY (id_posicao) REFERENCES posicao(id_posicao)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- RESTRICT: não pode apagar um clube ou rodada que tem partidas, perderia o histórico.
CREATE TABLE partida (
    id_partida INTEGER PRIMARY KEY,
    local VARCHAR(100),
    data_hora TIMESTAMP NOT NULL,
    placar_mandante INTEGER,
    placar_visitante INTEGER,
    valida BOOLEAN NOT NULL DEFAULT TRUE,
    id_clube_mandante INTEGER NOT NULL,
    id_clube_visitante INTEGER NOT NULL,
    numero_rodada INTEGER NOT NULL,
    CONSTRAINT fk_partida_mandante FOREIGN KEY (id_clube_mandante) REFERENCES clube(id_clube)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_partida_visitante FOREIGN KEY (id_clube_visitante) REFERENCES clube(id_clube)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_partida_rodada FOREIGN KEY (numero_rodada) REFERENCES rodada(numero)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_partida_clubes_distintos CHECK (id_clube_mandante <> id_clube_visitante)
);

-- CASCADE no atleta: o vínculo só existe se o atleta existir.
-- RESTRICT na rodada e no clube: não pode apagar se ainda tem atletas ligados.
CREATE TABLE pertence (
    id_atleta INTEGER NOT NULL,
    numero_rodada INTEGER NOT NULL,
    id_clube INTEGER NOT NULL,
    PRIMARY KEY (id_atleta, numero_rodada),
    CONSTRAINT fk_pertence_atleta FOREIGN KEY (id_atleta) REFERENCES atleta(id_atleta)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_pertence_rodada FOREIGN KEY (numero_rodada) REFERENCES rodada(numero)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_pertence_clube FOREIGN KEY (id_clube) REFERENCES clube(id_clube)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE tipo_scout (
    sigla VARCHAR(2) PRIMARY KEY,
    descricao VARCHAR(100) NOT NULL,
    valor_pontos NUMERIC(4,1) NOT NULL
);

-- CASCADE no scout: a regra faz parte do tipo de scout.
-- RESTRICT na posição: não pode apagar uma posição usada nessa regra.
CREATE TABLE vale_para (
    sigla_scout VARCHAR(2) NOT NULL,
    id_posicao INTEGER NOT NULL,
    PRIMARY KEY (sigla_scout, id_posicao),
    CONSTRAINT fk_vale_para_scout FOREIGN KEY (sigla_scout) REFERENCES tipo_scout(sigla)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_vale_para_posicao FOREIGN KEY (id_posicao) REFERENCES posicao(id_posicao)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CASCADE no atleta e na partida: o scout não existe sem eles.
-- RESTRICT no tipo de scout: apagar mudaria pontuações já calculadas.
CREATE TABLE registra_scout (
    id_atleta INTEGER NOT NULL,
    id_partida INTEGER NOT NULL,
    sigla_scout VARCHAR(2) NOT NULL,
    quantidade INTEGER NOT NULL CHECK (quantidade > 0),
    PRIMARY KEY (id_atleta, id_partida, sigla_scout),
    CONSTRAINT fk_registra_atleta FOREIGN KEY (id_atleta) REFERENCES atleta(id_atleta)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_registra_partida FOREIGN KEY (id_partida) REFERENCES partida(id_partida)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_registra_scout FOREIGN KEY (sigla_scout) REFERENCES tipo_scout(sigla)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CASCADE no time: a escalação é entidade fraca, não existe sem o time.
-- RESTRICT na rodada e no esquema: não pode apagar se já tem escalações.
CREATE TABLE escalacao (
    id_time INTEGER NOT NULL,
    numero_rodada INTEGER NOT NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'Edicao',
    data_confirmacao TIMESTAMP,
    id_esquema INTEGER NOT NULL,
    PRIMARY KEY (id_time, numero_rodada),
    CONSTRAINT fk_escalacao_time FOREIGN KEY (id_time) REFERENCES time(id_time)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_escalacao_rodada FOREIGN KEY (numero_rodada) REFERENCES rodada(numero)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_escalacao_esquema FOREIGN KEY (id_esquema) REFERENCES esquema_tatico(id_esquema)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_escalacao_estado CHECK (estado IN ('Edicao', 'Confirmada')),
    CONSTRAINT ck_escalacao_data_confirmacao
        CHECK ((estado = 'Edicao' AND data_confirmacao IS NULL)
            OR (estado = 'Confirmada' AND data_confirmacao IS NOT NULL))
);

-- CASCADE na escalação: os atletas escolhidos fazem parte dela.
-- RESTRICT no atleta: não pode apagar um atleta já escalado, perderia o preço pago.
CREATE TABLE compoe (
    id_time INTEGER NOT NULL,
    numero_rodada INTEGER NOT NULL,
    id_atleta INTEGER NOT NULL,
    preco_pago NUMERIC(10,2) NOT NULL CHECK (preco_pago >= 1.00),
    capitao BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (id_time, numero_rodada, id_atleta),
    CONSTRAINT fk_compoe_escalacao FOREIGN KEY (id_time, numero_rodada)
        REFERENCES escalacao(id_time, numero_rodada)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_compoe_atleta FOREIGN KEY (id_atleta) REFERENCES atleta(id_atleta)
        ON DELETE RESTRICT ON UPDATE CASCADE
);