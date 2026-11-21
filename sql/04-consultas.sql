SET search_path TO liga_facom;

-- (a) Visão do mercado: atletas disponíveis na rodada aberta
CREATE OR REPLACE VIEW vw_mercado AS
SELECT
    a.id_atleta,
    a.apelido,
    c.nome AS clube,
    p.nome AS posicao,
    p.abreviacao AS pos_abrev,
    s.descricao AS situacao,
    d.preco AS preco_atual,
    COALESCE((
        SELECT ROUND(AVG(d2.pontuacao), 2)
        FROM desempenho_na_rodada d2
        JOIN rodada r2 ON r2.numero = d2.numero_rodada
        WHERE d2.id_atleta = a.id_atleta
          AND LOWER(r2.estado) = 'consolidada'
          AND d2.entrou_em_campo = TRUE
    ), 0.00) AS media,
    COALESCE((
        SELECT d3.pontuacao
        FROM desempenho_na_rodada d3
        JOIN rodada r3 ON r3.numero = d3.numero_rodada
        WHERE d3.id_atleta = a.id_atleta
          AND LOWER(r3.estado) = 'consolidada'
          AND d3.entrou_em_campo = TRUE
        ORDER BY d3.numero_rodada DESC
        LIMIT 1
    ), 0.00) AS ultima_pontuacao
FROM atleta a
JOIN situacao s ON s.id_situacao = a.id_situacao
JOIN posicao p ON p.id_posicao = a.id_posicao
JOIN rodada r ON LOWER(r.estado) = 'aberta'
JOIN desempenho_na_rodada d ON d.id_atleta = a.id_atleta AND d.numero_rodada = r.numero
LEFT JOIN pertence pe ON pe.id_atleta = a.id_atleta AND pe.numero_rodada = r.numero
LEFT JOIN clube c ON c.id_clube = pe.id_clube
WHERE LOWER(s.descricao) IN ('provável', 'provavel', 'dúvida', 'duvida');

-- (b) Visão do ranking acumulado por liga 
CREATE OR REPLACE VIEW vw_ranking AS
SELECT
    l.id_liga,
    l.nome AS nome_liga,
    t.id_tecnico,
    t.apelido AS tecnico,
    tm.nome AS nome_time,
    COALESCE(SUM(fn_pontuacao_escalacao(tm.id_time, r.numero)), 0.00) AS pontuacao_acumulada,
    RANK() OVER (
        PARTITION BY l.id_liga
        ORDER BY COALESCE(SUM(fn_pontuacao_escalacao(tm.id_time, r.numero)), 0.00) DESC
    ) AS posicao_ranking
FROM liga l
JOIN participa pa ON pa.id_liga = l.id_liga
JOIN tecnico t ON t.id_tecnico = pa.id_tecnico
JOIN time tm ON tm.id_tecnico = t.id_tecnico
LEFT JOIN escalacao e ON e.id_time = tm.id_time AND LOWER(e.estado) = 'confirmada'
LEFT JOIN rodada r ON r.numero = e.numero_rodada AND LOWER(r.estado) = 'consolidada'
GROUP BY l.id_liga, l.nome, t.id_tecnico, t.apelido, tm.nome;

-- Função auxiliar de ranking por rodada 
CREATE OR REPLACE FUNCTION fn_ranking_rodada(p_id_liga INT, p_rodada INT)
RETURNS TABLE (
    tecnico VARCHAR,
    nome_time VARCHAR,
    pontuacao_rodada NUMERIC,
    posicao_ranking BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        t.apelido,
        tm.nome,
        fn_pontuacao_escalacao(tm.id_time, p_rodada) AS pts,
        RANK() OVER (ORDER BY fn_pontuacao_escalacao(tm.id_time, p_rodada) DESC)
    FROM participa pa
    JOIN tecnico t ON t.id_tecnico = pa.id_tecnico
    JOIN time tm ON tm.id_tecnico = t.id_tecnico
    WHERE pa.id_liga = p_id_liga;
END;
$$ LANGUAGE plpgsql;

-- (c) Os 5 atletas de cada posição com melhor custo no geral
WITH stats_atleta AS (
    SELECT
        a.id_atleta,
        a.apelido,
        p.nome AS posicao,
        ROUND(AVG(d.pontuacao), 2) AS media_pontos,
        (
            SELECT d_atual.preco
            FROM desempenho_na_rodada d_atual
            WHERE d_atual.id_atleta = a.id_atleta
            ORDER BY d_atual.numero_rodada DESC
            LIMIT 1
        ) AS preco_atual
    FROM atleta a
    JOIN posicao p ON p.id_posicao = a.id_posicao
    JOIN desempenho_na_rodada d ON d.id_atleta = a.id_atleta
    JOIN rodada r ON r.numero = d.numero_rodada
    WHERE LOWER(r.estado) = 'consolidada'
      AND d.entrou_em_campo = TRUE
    GROUP BY a.id_atleta, a.apelido, p.nome
    HAVING COUNT(*) >= 3
),
ranqueados AS (
    SELECT
        posicao,
        apelido,
        media_pontos,
        preco_atual,
        ROUND(media_pontos / preco_atual, 3) AS custo_beneficio,
        ROW_NUMBER() OVER (
            PARTITION BY posicao
            ORDER BY (media_pontos / preco_atual) DESC
        ) AS pos_rank
    FROM stats_atleta
)
SELECT posicao, apelido, media_pontos, preco_atual, custo_beneficio
FROM ranqueados
WHERE pos_rank <= 5
ORDER BY posicao, pos_rank;

-- (d) O melhor da rodada 
SELECT
    t.apelido AS tecnico,
    tm.nome AS nome_time,
    fn_pontuacao_escalacao(tm.id_time, e.numero_rodada) AS pontuacao_rodada,
    a_cap.apelido AS capitao
FROM escalacao e
JOIN time tm ON tm.id_time = e.id_time
JOIN tecnico t ON t.id_tecnico = tm.id_tecnico
JOIN compoe c ON c.id_time = e.id_time AND c.numero_rodada = e.numero_rodada AND c.capitao = TRUE
JOIN atleta a_cap ON a_cap.id_atleta = c.id_atleta
WHERE e.numero_rodada = 1 -- Parâmetro: número da rodada consolidada
  AND LOWER(e.estado) = 'confirmada'
ORDER BY pontuacao_rodada DESC, e.data_confirmacao ASC
LIMIT 1;

-- (e) O clube com mais jogos sem sofrer gol nas últimas 5 rodadas 
WITH ultimas_5 AS (
    SELECT numero
    FROM rodada
    WHERE LOWER(estado) = 'consolidada'
    ORDER BY numero DESC
    LIMIT 5
),
jogos_sem_sofrer_gol AS (
    SELECT id_clube_mandante AS id_clube
    FROM partida
    WHERE numero_rodada IN (SELECT numero FROM ultimas_5)
      AND valida = TRUE AND placar_visitante = 0
    UNION ALL
    SELECT id_clube_visitante AS id_clube
    FROM partida
    WHERE numero_rodada IN (SELECT numero FROM ultimas_5)
      AND valida = TRUE AND placar_mandante = 0
)
SELECT c.nome AS clube, COUNT(*) AS jogos_sem_sofrer_gol
FROM jogos_sem_sofrer_gol j
JOIN clube c ON c.id_clube = j.id_clube
GROUP BY c.id_clube, c.nome
ORDER BY jogos_sem_sofrer_gol DESC
LIMIT 1;

-- (f) O atleta mais escolhido como capitão dentro de uma liga 
SELECT
    a.apelido AS atleta,
    COUNT(*) AS vezes_capitao
FROM participa pa
JOIN time tm ON tm.id_tecnico = pa.id_tecnico
JOIN escalacao e ON e.id_time = tm.id_time AND LOWER(e.estado) = 'confirmada'
JOIN compoe c ON c.id_time = e.id_time AND c.numero_rodada = e.numero_rodada AND c.capitao = TRUE
JOIN atleta a ON a.id_atleta = c.id_atleta
WHERE pa.id_liga = 1 -- Parâmetro: id da liga
GROUP BY a.id_atleta, a.apelido
ORDER BY vezes_capitao DESC
LIMIT 1;

-- (g) Os técnicos que nunca escalaram nenhum atleta de um clube informado 
SELECT t.id_tecnico, t.nome, t.apelido
FROM tecnico t
WHERE NOT EXISTS (
    SELECT 1
    FROM time tm
    JOIN escalacao e ON e.id_time = tm.id_time AND LOWER(e.estado) = 'confirmada'
    JOIN compoe c ON c.id_time = e.id_time AND c.numero_rodada = e.numero_rodada
    JOIN pertence pe ON pe.id_atleta = c.id_atleta AND pe.numero_rodada = e.numero_rodada
    WHERE tm.id_tecnico = t.id_tecnico
      AND pe.id_clube = 262 -- Parâmetro: id do clube
);

-- (h) Atletas que, em todas as rodadas consolidadas em que entraram em campo, pontuaram acima da média da sua posição naquela rodada
WITH media_posicao_rodada AS (
    SELECT
        a.id_posicao,
        d.numero_rodada,
        AVG(d.pontuacao) AS media_pos
    FROM desempenho_na_rodada d
    JOIN atleta a ON a.id_atleta = d.id_atleta
    JOIN rodada r ON r.numero = d.numero_rodada
    WHERE LOWER(r.estado) = 'consolidada'
      AND d.entrou_em_campo = TRUE
    GROUP BY a.id_posicao, d.numero_rodada
)
SELECT a.id_atleta, a.apelido, p.nome AS posicao
FROM atleta a
JOIN posicao p ON p.id_posicao = a.id_posicao
WHERE EXISTS (
    SELECT 1
    FROM desempenho_na_rodada d
    JOIN rodada r ON r.numero = d.numero_rodada
    WHERE d.id_atleta = a.id_atleta
      AND LOWER(r.estado) = 'consolidada'
      AND d.entrou_em_campo = TRUE
)
AND NOT EXISTS (
    SELECT 1
    FROM desempenho_na_rodada d
    JOIN rodada r ON r.numero = d.numero_rodada
    JOIN media_posicao_rodada mpr ON mpr.id_posicao = a.id_posicao AND mpr.numero_rodada = d.numero_rodada
    WHERE d.id_atleta = a.id_atleta
      AND LOWER(r.estado) = 'consolidada'
      AND d.entrou_em_campo = TRUE
      AND d.pontuacao <= mpr.media_pos
);

-- (i) Evolução do patrimônio de um técnico rodada a rodada, com variação 
WITH patrimonio_por_rodada AS (
    SELECT
        r.numero AS rodada,
        100.00 + COALESCE(SUM(
            (SELECT COALESCE(SUM(d_prox.preco - c.preco_pago), 0.00)
             FROM escalacao e
             JOIN compoe c ON c.id_time = e.id_time AND c.numero_rodada = e.numero_rodada
             JOIN desempenho_na_rodada d_prox ON d_prox.id_atleta = c.id_atleta AND d_prox.numero_rodada = e.numero_rodada + 1
             WHERE e.id_time = tm.id_time
               AND LOWER(e.estado) = 'confirmada'
               AND e.numero_rodada <= r.numero)
        ), 0.00) AS patrimonio_fim_rodada
    FROM rodada r
    CROSS JOIN time tm
    WHERE tm.id_tecnico = 1 -- Parâmetro: id do técnico
      AND LOWER(r.estado) = 'consolidada'
    GROUP BY r.numero, tm.id_time
)
SELECT
    rodada,
    patrimonio_fim_rodada,
    patrimonio_fim_rodada - LAG(patrimonio_fim_rodada, 1, 100.00) OVER (ORDER BY rodada) AS variacao_rodada
FROM patrimonio_por_rodada
ORDER BY rodada;

-- (j) Ligas com pelo menos 3 participantes cuja média acumulada seja maior que a média geral do sistema
WITH pontos_por_tecnico AS (
    SELECT
        t.id_tecnico,
        COALESCE(SUM(fn_pontuacao_escalacao(tm.id_time, r.numero)), 0.00) AS total_pontos
    FROM tecnico t
    JOIN time tm ON tm.id_tecnico = t.id_tecnico
    LEFT JOIN escalacao e ON e.id_time = tm.id_time AND LOWER(e.estado) = 'confirmada'
    LEFT JOIN rodada r ON r.numero = e.numero_rodada AND LOWER(r.estado) = 'consolidada'
    GROUP BY t.id_tecnico
)
SELECT
    l.id_liga,
    l.nome AS liga,
    COUNT(pa.id_tecnico) AS qtd_participantes,
    ROUND(AVG(pt.total_pontos), 2) AS media_liga
FROM liga l
JOIN participa pa ON pa.id_liga = l.id_liga
JOIN pontos_por_tecnico pt ON pt.id_tecnico = pa.id_tecnico
GROUP BY l.id_liga, l.nome
HAVING COUNT(pa.id_tecnico) >= 3
   AND AVG(pt.total_pontos) > (SELECT AVG(total_pontos) FROM pontos_por_tecnico);

-- (k) Seleção da rodada simplificada e custo total 
WITH melhores_por_posicao AS (
    SELECT
        p.nome AS posicao,
        a.apelido AS atleta,
        d.preco,
        d.pontuacao,
        ROW_NUMBER() OVER (
            PARTITION BY p.id_posicao
            ORDER BY d.pontuacao DESC, d.preco ASC
        ) AS rn
    FROM desempenho_na_rodada d
    JOIN atleta a ON a.id_atleta = d.id_atleta
    JOIN posicao p ON p.id_posicao = a.id_posicao
    WHERE d.numero_rodada = 1 -- Parâmetro: número da rodada consolidada
      AND d.entrou_em_campo = TRUE
      AND d.preco <= 12.00
)
SELECT
    posicao,
    atleta,
    preco,
    pontuacao,
    SUM(preco) OVER () AS custo_total_selecao
FROM melhores_por_posicao
WHERE rn = 1;