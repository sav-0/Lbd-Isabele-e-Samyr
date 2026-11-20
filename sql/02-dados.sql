SET search_path TO liga_facom;

-- Garante as 6 posições básicas caso este script rode antes da carga da API
INSERT INTO posicao (id_posicao, nome, abreviacao) VALUES
    (1, 'Goleiro', 'gol'),
    (2, 'Lateral', 'lat'),
    (3, 'Zagueiro', 'zag'),
    (4, 'Meia', 'mei'),
    (5, 'Atacante', 'ata'),
    (6, 'Técnico', 'tec')
ON CONFLICT (id_posicao) DO NOTHING;

-- Garante os 7 esquemas táticos aceitos no jogo
INSERT INTO esquema_tatico (id_esquema, nome) VALUES
    (1, '3-4-3'),
    (2, '3-5-2'),
    (3, '4-3-3'),
    (4, '4-4-2'),
    (5, '4-5-1'),
    (6, '5-3-2'),
    (7, '5-4-1')
ON CONFLICT (id_esquema) DO NOTHING;

INSERT INTO exige (id_esquema, id_posicao, quantidade) VALUES
    -- 3-4-3
    (1, 1, 1), (1, 2, 0), (1, 3, 3), (1, 4, 4), (1, 5, 3), (1, 6, 1),
    -- 3-5-2
    (2, 1, 1), (2, 2, 0), (2, 3, 3), (2, 4, 5), (2, 5, 2), (2, 6, 1),
    -- 4-3-3
    (3, 1, 1), (3, 2, 2), (3, 3, 2), (3, 4, 3), (3, 5, 3), (3, 6, 1),
    -- 4-4-2
    (4, 1, 1), (4, 2, 2), (4, 3, 2), (4, 4, 4), (4, 5, 2), (4, 6, 1),
    -- 4-5-1
    (5, 1, 1), (5, 2, 2), (5, 3, 2), (5, 4, 5), (5, 5, 1), (5, 6, 1),
    -- 5-3-2
    (6, 1, 1), (6, 2, 2), (6, 3, 3), (6, 4, 3), (6, 5, 2), (6, 6, 1),
    -- 5-4-1
    (7, 1, 1), (7, 2, 2), (7, 3, 3), (7, 4, 4), (7, 5, 1), (7, 6, 1)
ON CONFLICT (id_esquema, id_posicao) DO NOTHING;

-- 1. Os 19 tipos de scout
INSERT INTO tipo_scout (sigla, descricao, valor_pontos) VALUES
    ('G',  'Gol', 8.0),
    ('A',  'Assistência', 5.0),
    ('FT', 'Finalização na trave', 3.0),
    ('FD', 'Finalização defendida pelo goleiro', 1.2),
    ('FF', 'Finalização para fora', 0.8),
    ('FS', 'Falta sofrida', 0.5),
    ('PS', 'Pênalti sofrido', 1.0),
    ('DS', 'Desarme', 1.5),
    ('SG', 'Jogo sem sofrer gol', 5.0),
    ('DE', 'Defesa', 1.3),
    ('DP', 'Defesa de pênalti', 7.0),
    ('GS', 'Gol sofrido', -1.0),
    ('FC', 'Falta cometida', -0.3),
    ('I',  'Impedimento', -0.1),
    ('CA', 'Cartão amarelo', -1.0),
    ('CV', 'Cartão vermelho', -3.0),
    ('GC', 'Gol contra', -3.0),
    ('PC', 'Pênalti cometido', -1.0),
    ('PP', 'Pênalti perdido', -4.0)
ON CONFLICT (sigla) DO NOTHING;

-- 2. Relação VALE_PARA (quais posições pontuam em cada scout)
INSERT INTO vale_para (sigla_scout, id_posicao)
SELECT s.sigla, p.id_posicao
FROM tipo_scout s
CROSS JOIN posicao p
WHERE s.sigla NOT IN ('SG', 'DE', 'DP', 'GS')
  AND p.id_posicao IN (1, 2, 3, 4, 5)
ON CONFLICT (sigla_scout, id_posicao) DO NOTHING;

INSERT INTO vale_para (sigla_scout, id_posicao) VALUES
    ('SG', 1), ('SG', 2), ('SG', 3),
    ('DE', 1), ('DP', 1), ('GS', 1)
ON CONFLICT (sigla_scout, id_posicao) DO NOTHING;

-- 3. Cadastro de 8 técnicos e seus 8 times (patrimônio inicial C$ 100.00)
INSERT INTO tecnico (id_tecnico, nome, email, apelido) VALUES
    (1, 'Samyr Arruda',      'samyr@facom.ufms.br',    'SamyrFC'),
    (2, 'Isabele Firmino',   'isabele@facom.ufms.br',  'IsaTech'),
    (3, 'Lucas Andrade',     'lucas@facom.ufms.br',    'LucaoMS'),
    (4, 'Mariana Costa',     'mariana@facom.ufms.br',  'MariGol'),
    (5, 'Pedro Henrique',    'pedro@facom.ufms.br',    'PedroH'),
    (6, 'Camila Rocha',      'camila@facom.ufms.br',   'CamiR'),
    (7, 'Rafael Mendes',     'rafael@facom.ufms.br',   'RafaM'),
    (8, 'Beatriz Lima',      'beatriz@facom.ufms.br',  'BiaLima')
ON CONFLICT (id_tecnico) DO NOTHING;

SELECT setval(pg_get_serial_sequence('tecnico', 'id_tecnico'), 8);

INSERT INTO time (id_time, nome, patrimonio, id_tecnico) VALUES
    (1, 'Bits Futebol Clube',   100.00, 1),
    (2, 'Query United',         100.00, 2),
    (3, 'Select Stars',         100.00, 3),
    (4, 'Join Atlético',        100.00, 4),
    (5, 'Trigger Real',         100.00, 5),
    (6, 'Commit Esporte',       100.00, 6),
    (7, 'Index City',           100.00, 7),
    (8, 'Rollback Rovers',      100.00, 8)
ON CONFLICT (id_time) DO NOTHING;

SELECT setval(pg_get_serial_sequence('time', 'id_time'), 8);

-- 4. Cadastro de 3 ligas (2 públicas e 1 privada)
INSERT INTO liga (id_liga, nome, descricao, codigo_convite, limite_participantes, publica, id_dono) VALUES
    (1, 'Liga Geral FACOM',     'Liga aberta para toda a faculdade', NULL,       50, TRUE,  1),
    (2, 'Copa LBD 2026',        'Disputa privada da turma de LBD',  'LBD2026',  15, FALSE, 2),
    (3, 'Desafio Calouros',     'Liga pública de treino',            NULL,       30, TRUE,  3)
ON CONFLICT (id_liga) DO NOTHING;

SELECT setval(pg_get_serial_sequence('liga', 'id_liga'), 3);

-- 5. Participações (donos nas próprias ligas + técnico 1 em várias ligas)
INSERT INTO participa (id_tecnico, id_liga) VALUES
    (1, 1), (2, 1), (3, 1), (4, 1), (5, 1), (6, 1), (7, 1), (8, 1),
    (2, 2), (1, 2), (3, 2), (4, 2),
    (3, 3), (1, 3), (5, 3)
ON CONFLICT (id_tecnico, id_liga) DO NOTHING;