SET search_path TO liga_facom;

-- ==============================================================================
-- FUNÇÃO 1: Pontuação de um atleta ou técnico em uma rodada
-- ==============================================================================
CREATE OR REPLACE FUNCTION fn_pontuacao_atleta(p_id_atleta INT, p_rodada INT)
RETURNS NUMERIC AS $$
DECLARE
    v_entrou BOOLEAN;
    v_id_posicao INT;
    v_id_clube INT;
    v_placar_pro INT;
    v_placar_contra INT;
    v_pontos NUMERIC(6,2) := 0.00;
BEGIN
    SELECT entrou_em_campo INTO v_entrou
    FROM desempenho_na_rodada
    WHERE id_atleta = p_id_atleta AND numero_rodada = p_rodada;

    IF NOT FOUND OR v_entrou = FALSE THEN
        RETURN 0.00;
    END IF;

    SELECT id_posicao INTO v_id_posicao
    FROM atleta
    WHERE id_atleta = p_id_atleta;

    -- Técnico: 5 vitória, 2 empate, 0 derrota ou não jogou
    IF v_id_posicao = 6 THEN
        SELECT id_clube INTO v_id_clube
        FROM pertence
        WHERE id_atleta = p_id_atleta AND numero_rodada = p_rodada;

        SELECT
            CASE WHEN id_clube_mandante = v_id_clube THEN placar_mandante ELSE placar_visitante END,
            CASE WHEN id_clube_mandante = v_id_clube THEN placar_visitante ELSE placar_mandante END
        INTO v_placar_pro, v_placar_contra
        FROM partida
        WHERE numero_rodada = p_rodada
          AND valida = TRUE
          AND (id_clube_mandante = v_id_clube OR id_clube_visitante = v_id_clube)
        LIMIT 1;

        IF NOT FOUND OR v_placar_pro IS NULL OR v_placar_contra IS NULL THEN
            RETURN 0.00;
        ELSIF v_placar_pro > v_placar_contra THEN
            RETURN 5.00;
        ELSIF v_placar_pro = v_placar_contra THEN
            RETURN 2.00;
        ELSE
            RETURN 0.00;
        END IF;
    END IF;

    -- Jogadores de linha e goleiros: soma apenas scouts válidos para a posição e partidas válidas
    SELECT COALESCE(SUM(rs.quantidade * ts.valor_pontos), 0.00)
    INTO v_pontos
    FROM registra_scout rs
    JOIN partida p ON p.id_partida = rs.id_partida
    JOIN tipo_scout ts ON ts.sigla = rs.sigla_scout
    JOIN vale_para vp ON vp.sigla_scout = rs.sigla_scout AND vp.id_posicao = v_id_posicao
    WHERE rs.id_atleta = p_id_atleta
      AND p.numero_rodada = p_rodada
      AND p.valida = TRUE;

    RETURN ROUND(v_pontos, 2);
END;
$$ LANGUAGE plpgsql;

-- ==============================================================================
-- FUNÇÃO 2: Pontuação de uma escalação confirmada com capitão x 1.5
-- ==============================================================================
CREATE OR REPLACE FUNCTION fn_pontuacao_escalacao(p_id_time INT, p_rodada INT)
RETURNS NUMERIC AS $$
DECLARE
    v_estado VARCHAR(20);
    v_total NUMERIC(8,2) := 0.00;
BEGIN
    SELECT estado INTO v_estado
    FROM escalacao
    WHERE id_time = p_id_time AND numero_rodada = p_rodada;

    IF NOT FOUND OR LOWER(v_estado) <> 'confirmada' THEN
        RETURN 0.00;
    END IF;

    SELECT COALESCE(SUM(
        fn_pontuacao_atleta(c.id_atleta, p_rodada) *
        CASE WHEN c.capitao THEN 1.5 ELSE 1.0 END
    ), 0.00)
    INTO v_total
    FROM compoe c
    WHERE c.id_time = p_id_time AND c.numero_rodada = p_rodada;

    RETURN ROUND(v_total, 2);
END;
$$ LANGUAGE plpgsql;

-- ==============================================================================
-- GATILHO 1: Regras da Rodada 
-- ==============================================================================
CREATE OR REPLACE FUNCTION fn_trg_validar_rodada()
RETURNS TRIGGER AS $$
DECLARE
    v_abertas INT;
BEGIN
    -- Garante no máximo uma rodada aberta por vez
    IF LOWER(NEW.estado) = 'aberta' THEN
        SELECT COUNT(*) INTO v_abertas
        FROM rodada
        WHERE LOWER(estado) = 'aberta'
          AND numero <> NEW.numero;

        IF v_abertas > 0 THEN
            RAISE EXCEPTION 'Já existe uma rodada aberta. Feche-a antes de abrir outra.';
        END IF;
    END IF;

    -- Garante a ordem Aberta -> Fechada -> Finalizada e bloqueia alterações
    IF TG_OP = 'UPDATE' THEN
        IF LOWER(OLD.estado) = 'consolidada' THEN
            RAISE EXCEPTION 'A rodada % já está consolidada e não pode mais ser alterada.', OLD.numero;
        END IF;

        -- Erro encontrado: testando, uma rodada Futura conseguia ir direto para Fechada ou Consolidada, pulando a etapa Aberta.
        IF LOWER(OLD.estado) = 'futura' AND LOWER(NEW.estado) NOT IN ('futura', 'aberta') THEN
            RAISE EXCEPTION 'Transição inválida: uma rodada Futura só pode ir para Aberta.';
        END IF;

        IF LOWER(OLD.estado) = 'aberta' AND LOWER(NEW.estado) NOT IN ('aberta', 'fechada') THEN
            RAISE EXCEPTION 'Transição inválida: uma rodada Aberta só pode ir para Fechada.';
        END IF;

        IF LOWER(OLD.estado) = 'fechada' AND LOWER(NEW.estado) NOT IN ('fechada', 'consolidada') THEN
            RAISE EXCEPTION 'Transição inválida: uma rodada Fechada só pode ir para Consolidada.';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_rodada
BEFORE INSERT OR UPDATE ON rodada
FOR EACH ROW EXECUTE FUNCTION fn_trg_validar_rodada();

-- ==============================================================================
-- GATILHO 2: Regras da Partida 
-- ==============================================================================
CREATE OR REPLACE FUNCTION fn_trg_validar_partida()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.id_clube_mandante = NEW.id_clube_visitante THEN
        RAISE EXCEPTION 'Um clube não pode enfrentar a si mesmo.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM partida
        WHERE numero_rodada = NEW.numero_rodada
          AND id_partida <> NEW.id_partida
          AND (
              id_clube_mandante IN (NEW.id_clube_mandante, NEW.id_clube_visitante)
              OR id_clube_visitante IN (NEW.id_clube_mandante, NEW.id_clube_visitante)
          )
    ) THEN
        RAISE EXCEPTION 'Um dos clubes já possui partida cadastrada na rodada %.', NEW.numero_rodada;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_partida
BEFORE INSERT OR UPDATE ON partida
FOR EACH ROW EXECUTE FUNCTION fn_trg_validar_partida();

-- ==============================================================================
-- GATILHO 3: Dono participa automaticamente da liga + limite de participantes
-- ==============================================================================
CREATE OR REPLACE FUNCTION fn_trg_dono_participa_liga()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO participa (id_tecnico, id_liga, data_entrada)
    VALUES (NEW.id_dono, NEW.id_liga, CURRENT_DATE)
    ON CONFLICT (id_tecnico, id_liga) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_dono_participa_liga
AFTER INSERT ON liga
FOR EACH ROW EXECUTE FUNCTION fn_trg_dono_participa_liga();

CREATE OR REPLACE FUNCTION fn_trg_validar_participa()
RETURNS TRIGGER AS $$
DECLARE
    v_limite INT;
    v_qtd_atual INT;
BEGIN
    SELECT limite_participantes INTO v_limite
    FROM liga
    WHERE id_liga = NEW.id_liga;

    SELECT COUNT(*) INTO v_qtd_atual
    FROM participa
    WHERE id_liga = NEW.id_liga;

    IF v_limite IS NOT NULL AND v_qtd_atual >= v_limite THEN
        RAISE EXCEPTION 'Esta liga atingiu o limite máximo de % participantes.', v_limite;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_participa
BEFORE INSERT ON participa
FOR EACH ROW EXECUTE FUNCTION fn_trg_validar_participa();

-- ==============================================================================
-- GATILHO 4: Proteção na tabela Escalacao 
-- ==============================================================================
CREATE OR REPLACE FUNCTION fn_trg_validar_escalacao()
RETURNS TRIGGER AS $$
DECLARE
    v_estado_rodada VARCHAR(20);
BEGIN
    SELECT estado INTO v_estado_rodada FROM rodada WHERE numero = NEW.numero_rodada;

    IF LOWER(v_estado_rodada) <> 'aberta' THEN
        RAISE EXCEPTION 'Operação recusada: a rodada % não está aberta.', NEW.numero_rodada;
    END IF;

    IF TG_OP = 'UPDATE' AND LOWER(OLD.estado) = 'confirmada' THEN
        RAISE EXCEPTION 'Escalação já confirmada não pode ser alterada.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_escalacao
BEFORE INSERT OR UPDATE ON escalacao
FOR EACH ROW EXECUTE FUNCTION fn_trg_validar_escalacao();

-- ==============================================================================
-- GATILHO 5: Confirmar ao incluir, alterar ou remover atleta em ompoe
-- ==============================================================================
CREATE OR REPLACE FUNCTION fn_trg_validar_compoe()
RETURNS TRIGGER AS $$
DECLARE
    v_id_time INT;
    v_rodada INT;
    v_estado_rodada VARCHAR(20);
    v_estado_esc VARCHAR(20);
    v_id_esquema INT;
    v_situacao VARCHAR(50);
    v_id_posicao INT;
    v_nome_posicao VARCHAR(50);
    v_limite_pos INT;
    v_qtd_pos INT;
    v_preco_momento NUMERIC(10,2);
    v_patrimonio NUMERIC(10,2);
    v_gasto_atual NUMERIC(10,2);
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_id_time := OLD.id_time;
        v_rodada  := OLD.numero_rodada;
    ELSE
        v_id_time := NEW.id_time;
        v_rodada  := NEW.numero_rodada;
    END IF;

    -- 1. Rodada precisa estar aberta
    SELECT estado INTO v_estado_rodada FROM rodada WHERE numero = v_rodada;
    IF LOWER(v_estado_rodada) <> 'aberta' THEN
        RAISE EXCEPTION 'Operação recusada: a rodada % não está aberta.', v_rodada;
    END IF;

    -- 2. Escalação não pode estar confirmada
    SELECT estado, id_esquema INTO v_estado_esc, v_id_esquema
    FROM escalacao
    WHERE id_time = v_id_time AND numero_rodada = v_rodada;

    IF LOWER(v_estado_esc) = 'confirmada' THEN
        RAISE EXCEPTION 'Operação recusada: esta escalação já foi confirmada.';
    END IF;

    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        -- 3. Atleta precisa estar Provável ou Dúvida
        SELECT s.descricao, a.id_posicao, p.nome
        INTO v_situacao, v_id_posicao, v_nome_posicao
        FROM atleta a
        JOIN situacao s ON s.id_situacao = a.id_situacao
        JOIN posicao p ON p.id_posicao = a.id_posicao
        WHERE a.id_atleta = NEW.id_atleta;

        IF LOWER(v_situacao) NOT IN ('provável', 'provavel', 'dúvida', 'duvida') THEN
            RAISE EXCEPTION 'Atleta indisponível (%): só é permitido escalar atletas prováveis ou em dúvida.', v_situacao;
        END IF;

        -- 4. Qtd de posições não pode extrapolar o esquema tático
        SELECT quantidade INTO v_limite_pos
        FROM exige
        WHERE id_esquema = v_id_esquema AND id_posicao = v_id_posicao;

        SELECT COUNT(*) INTO v_qtd_pos
        FROM compoe c
        JOIN atleta a ON a.id_atleta = c.id_atleta
        WHERE c.id_time = v_id_time
          AND c.numero_rodada = v_rodada
          AND a.id_posicao = v_id_posicao
          AND c.id_atleta <> NEW.id_atleta;

        IF (v_qtd_pos + 1) > COALESCE(v_limite_pos, 0) THEN
            RAISE EXCEPTION 'Limite atingido: o esquema selecionado permite no máximo % jogador(es) na posição %.',
                COALESCE(v_limite_pos, 0), v_nome_posicao;
        END IF;

        -- 5. Preenche automaticamente o preco_pago com o preço do atleta na rodada
        SELECT preco INTO v_preco_momento
        FROM desempenho_na_rodada
        WHERE id_atleta = NEW.id_atleta AND numero_rodada = v_rodada;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'O atleta selecionado ainda não possui preço definido para a rodada %.', v_rodada;
        END IF;

        NEW.preco_pago := v_preco_momento;

        -- 6. Soma dos preços não pode ultrapassar as cartoletas do técnico
        SELECT patrimonio INTO v_patrimonio FROM time WHERE id_time = v_id_time;

        SELECT COALESCE(SUM(preco_pago), 0.00) INTO v_gasto_atual
        FROM compoe
        WHERE id_time = v_id_time
          AND numero_rodada = v_rodada
          AND id_atleta <> NEW.id_atleta;

        IF (v_gasto_atual + NEW.preco_pago) > v_patrimonio THEN
            RAISE EXCEPTION 'Orçamento insuficiente: custo total (C$ %) ultrapassa o patrimônio (C$ %).',
                (v_gasto_atual + NEW.preco_pago), v_patrimonio;
        END IF;

        RETURN NEW;
    END IF;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_compoe
BEFORE INSERT OR UPDATE OR DELETE ON compoe
FOR EACH ROW EXECUTE FUNCTION fn_trg_validar_compoe();

-- ==============================================================================
-- GATILHO 6: Confirmação e atualização automática de pontuação nos Scouts
-- ==============================================================================
CREATE OR REPLACE FUNCTION fn_trg_validar_scout()
RETURNS TRIGGER AS $$
DECLARE
    v_id_atleta INT;
    v_id_partida INT;
    v_rodada INT;
    v_estado_rodada VARCHAR(20);
    v_clube_atleta INT;
    v_mandante INT;
    v_visitante INT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_id_atleta  := OLD.id_atleta;
        v_id_partida := OLD.id_partida;
    ELSE
        v_id_atleta  := NEW.id_atleta;
        v_id_partida := NEW.id_partida;
    END IF;

    -- Erro encontrado: rodando a carga duas vezes depois deste script, a segunda vez parava com "Não é permitido alterar scouts de uma rodada já consolidada", porque o gatilho roda antes
    -- do ON CONFLICT DO NOTHING da carga. 
    IF TG_OP = 'INSERT' AND EXISTS (
        SELECT 1 FROM registra_scout
        WHERE id_atleta = NEW.id_atleta
          AND id_partida = NEW.id_partida
          AND sigla_scout = NEW.sigla_scout
    ) THEN
        RETURN NULL;
    END IF;

    SELECT numero_rodada, id_clube_mandante, id_clube_visitante
    INTO v_rodada, v_mandante, v_visitante
    FROM partida
    WHERE id_partida = v_id_partida;

    SELECT estado INTO v_estado_rodada FROM rodada WHERE numero = v_rodada;

    IF LOWER(v_estado_rodada) = 'consolidada' THEN
        RAISE EXCEPTION 'Não é permitido alterar scouts de uma rodada já consolidada.';
    END IF;

    -- Verifica se o clube do atleta na rodada disputou essa partida
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        SELECT id_clube INTO v_clube_atleta
        FROM pertence
        WHERE id_atleta = v_id_atleta AND numero_rodada = v_rodada;

        IF v_clube_atleta IS NULL OR v_clube_atleta NOT IN (v_mandante, v_visitante) THEN
            RAISE EXCEPTION 'Scout inválido: o clube do atleta na rodada % não disputou esta partida.', v_rodada;
        END IF;

        RETURN NEW;
    END IF;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_scout
BEFORE INSERT OR UPDATE OR DELETE ON registra_scout
FOR EACH ROW EXECUTE FUNCTION fn_trg_validar_scout();

CREATE OR REPLACE FUNCTION fn_trg_recalcular_pontuacao_scout()
RETURNS TRIGGER AS $$
DECLARE
    v_id_atleta INT;
    v_id_partida INT;
    v_rodada INT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_id_atleta  := OLD.id_atleta;
        v_id_partida := OLD.id_partida;
    ELSE
        v_id_atleta  := NEW.id_atleta;
        v_id_partida := NEW.id_partida;
    END IF;

    SELECT numero_rodada INTO v_rodada FROM partida WHERE id_partida = v_id_partida;

    UPDATE desempenho_na_rodada
    SET pontuacao = fn_pontuacao_atleta(v_id_atleta, v_rodada)
    WHERE id_atleta = v_id_atleta AND numero_rodada = v_rodada;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_recalcular_pontuacao_scout
AFTER INSERT OR UPDATE OR DELETE ON registra_scout
FOR EACH ROW EXECUTE FUNCTION fn_trg_recalcular_pontuacao_scout();

-- ==============================================================================
-- PROCEDIMENTO 1: Cadastrar técnico e seu time juntos 
-- ==============================================================================
CREATE OR REPLACE PROCEDURE sp_cadastrar_tecnico(
    p_nome VARCHAR,
    p_email VARCHAR,
    p_apelido VARCHAR,
    p_nome_time VARCHAR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_id_tecnico INT;
BEGIN
    INSERT INTO tecnico (nome, email, apelido)
    VALUES (p_nome, p_email, p_apelido)
    RETURNING id_tecnico INTO v_id_tecnico;

    INSERT INTO time (nome, patrimonio, id_tecnico)
    VALUES (p_nome_time, 100.00, v_id_tecnico);
END;
$$;

-- ==============================================================================
-- PROCEDIMENTO 2: Confirmar escalação
-- ==============================================================================
CREATE OR REPLACE PROCEDURE sp_confirmar_escalacao(p_id_time INT, p_rodada INT)
LANGUAGE plpgsql AS $$
DECLARE
    v_estado_rodada VARCHAR(20);
    v_estado_esc VARCHAR(20);
    v_id_esquema INT;
    v_total_escalados INT;
    v_qtd_capitao INT;
    v_capitao_tecnico INT;
    v_custo_total NUMERIC(10,2);
    v_patrimonio NUMERIC(10,2);
    reg RECORD;
    v_qtd_pos INT;
BEGIN
    SELECT estado INTO v_estado_rodada FROM rodada WHERE numero = p_rodada;
    IF LOWER(v_estado_rodada) <> 'aberta' THEN
        RAISE EXCEPTION 'A rodada % não está aberta.', p_rodada;
    END IF;

    SELECT estado, id_esquema INTO v_estado_esc, v_id_esquema
    FROM escalacao
    WHERE id_time = p_id_time AND numero_rodada = p_rodada;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Escalação não encontrada para esta rodada.';
    END IF;

    IF LOWER(v_estado_esc) = 'confirmada' THEN
        RAISE EXCEPTION 'Esta escalação já está confirmada.';
    END IF;

    SELECT COUNT(*) INTO v_total_escalados
    FROM compoe
    WHERE id_time = p_id_time AND numero_rodada = p_rodada;

    IF v_total_escalados <> 12 THEN
        RAISE EXCEPTION 'Escalação incompleta: são necessários 12 integrantes (atual: %).', v_total_escalados;
    END IF;

    FOR reg IN
        SELECT e.id_posicao, p.nome, e.quantidade
        FROM exige e
        JOIN posicao p ON p.id_posicao = e.id_posicao
        WHERE e.id_esquema = v_id_esquema
    LOOP
        SELECT COUNT(*) INTO v_qtd_pos
        FROM compoe c
        JOIN atleta a ON a.id_atleta = c.id_atleta
        WHERE c.id_time = p_id_time
          AND c.numero_rodada = p_rodada
          AND a.id_posicao = reg.id_posicao;

        IF v_qtd_pos <> reg.quantidade THEN
            RAISE EXCEPTION 'Esquema inválido: a posição % exige % jogador(es), mas há %.',
                reg.nome, reg.quantidade, v_qtd_pos;
        END IF;
    END LOOP;

    SELECT COUNT(*) INTO v_qtd_capitao
    FROM compoe
    WHERE id_time = p_id_time AND numero_rodada = p_rodada AND capitao = TRUE;

    IF v_qtd_capitao <> 1 THEN
        RAISE EXCEPTION 'A escalação deve ter exatamente 1 capitão (atual: %).', v_qtd_capitao;
    END IF;

    SELECT COUNT(*) INTO v_capitao_tecnico
    FROM compoe c
    JOIN atleta a ON a.id_atleta = c.id_atleta
    WHERE c.id_time = p_id_time AND c.numero_rodada = p_rodada
      AND c.capitao = TRUE AND a.id_posicao = 6;

    IF v_capitao_tecnico > 0 THEN
        RAISE EXCEPTION 'O técnico real não pode ser escolhido como capitão.';
    END IF;

    SELECT patrimonio INTO v_patrimonio FROM time WHERE id_time = p_id_time;
    SELECT COALESCE(SUM(preco_pago), 0.00) INTO v_custo_total
    FROM compoe
    WHERE id_time = p_id_time AND numero_rodada = p_rodada;

    IF v_custo_total > v_patrimonio THEN
        RAISE EXCEPTION 'Custo total (C$ %) ultrapassa o patrimônio (C$ %).', v_custo_total, v_patrimonio;
    END IF;

    UPDATE escalacao
    SET estado = 'Confirmada', data_confirmacao = CURRENT_TIMESTAMP
    WHERE id_time = p_id_time AND numero_rodada = p_rodada;
END;
$$;

-- ==============================================================================
-- PROCEDIMENTO 3: Técnico entrar em uma liga
-- ==============================================================================
CREATE OR REPLACE PROCEDURE sp_entrar_liga(
    p_id_tecnico INT,
    p_id_liga INT,
    p_codigo_convite VARCHAR DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_publica BOOLEAN;
    v_codigo_real VARCHAR(20);
BEGIN
    SELECT publica, codigo_convite
    INTO v_publica, v_codigo_real
    FROM liga
    WHERE id_liga = p_id_liga;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Liga não encontrada.';
    END IF;

    IF EXISTS (SELECT 1 FROM participa WHERE id_tecnico = p_id_tecnico AND id_liga = p_id_liga) THEN
        RAISE EXCEPTION 'Você já participa desta liga.';
    END IF;

    IF v_publica = FALSE THEN
        IF p_codigo_convite IS NULL OR p_codigo_convite <> v_codigo_real THEN
            RAISE EXCEPTION 'Código de convite inválido para esta liga privada.';
        END IF;
    END IF;

    -- O gatilho trg_validar_participa verifica o limite de participantes
    INSERT INTO participa (id_tecnico, id_liga, data_entrada)
    VALUES (p_id_tecnico, p_id_liga, CURRENT_DATE);
END;
$$;

-- ==============================================================================
-- PROCEDIMENTO 4: Confirmar a rodada fechada 
-- ==============================================================================
CREATE OR REPLACE PROCEDURE sp_consolidar_rodada(p_rodada INT)
LANGUAGE plpgsql AS $$
DECLARE
    v_estado VARCHAR(20);
    reg_atl RECORD;
    reg_esc RECORD;
    v_pontos NUMERIC(6,2);
    v_media_anterior NUMERIC(6,2);
    v_variacao NUMERIC(6,2);
    v_novo_preco NUMERIC(10,2);
    v_diff_patrimonio NUMERIC(10,2);
BEGIN
    SELECT estado INTO v_estado FROM rodada WHERE numero = p_rodada;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Rodada % não encontrada.', p_rodada;
    END IF;

    IF LOWER(v_estado) <> 'fechada' THEN
        RAISE EXCEPTION 'Apenas rodadas fechadas podem ser consolidadas (estado atual: %).', v_estado;
    END IF;

    CREATE TEMP TABLE tmp_precos_atualizados (
        id_atleta INT PRIMARY KEY,
        novo_preco NUMERIC(10,2) NOT NULL
    ) ON COMMIT DROP;

    -- 1. Calcula pontuação e valorização de cada atleta na rodada
    FOR reg_atl IN
        SELECT id_atleta, preco, entrou_em_campo
        FROM desempenho_na_rodada
        WHERE numero_rodada = p_rodada
    LOOP
        v_pontos := fn_pontuacao_atleta(reg_atl.id_atleta, p_rodada);

        UPDATE desempenho_na_rodada
        SET pontuacao = v_pontos
        WHERE id_atleta = reg_atl.id_atleta AND numero_rodada = p_rodada;

        IF reg_atl.entrou_em_campo = TRUE THEN
            SELECT AVG(d.pontuacao) INTO v_media_anterior
            FROM desempenho_na_rodada d
            JOIN rodada r ON r.numero = d.numero_rodada
            WHERE d.id_atleta = reg_atl.id_atleta
              AND d.numero_rodada < p_rodada
              AND LOWER(r.estado) = 'consolidada'
              AND d.entrou_em_campo = TRUE;

            IF v_media_anterior IS NULL THEN
                v_variacao := 0.00;
            ELSE
                v_variacao := ROUND(0.10 * (v_pontos - v_media_anterior), 2);
                IF v_variacao > 1.50 THEN v_variacao := 1.50; END IF;
                IF v_variacao < -1.50 THEN v_variacao := -1.50; END IF;
            END IF;

            v_novo_preco := GREATEST(1.00, reg_atl.preco + v_variacao);
        ELSE
            v_novo_preco := reg_atl.preco;
        END IF;

        INSERT INTO tmp_precos_atualizados (id_atleta, novo_preco)
        VALUES (reg_atl.id_atleta, v_novo_preco);

        IF p_rodada < 38 THEN
            INSERT INTO desempenho_na_rodada (id_atleta, numero_rodada, preco, entrou_em_campo, pontuacao)
            VALUES (reg_atl.id_atleta, p_rodada + 1, v_novo_preco, FALSE, 0.00)
            ON CONFLICT (id_atleta, numero_rodada)
            DO UPDATE SET preco = EXCLUDED.preco;
        END IF;
    END LOOP;

    -- 2. Atualiza as cartoletas dos técnicos que confirmaram escalação
    FOR reg_esc IN
        SELECT id_time
        FROM escalacao
        WHERE numero_rodada = p_rodada AND LOWER(estado) = 'confirmada'
    LOOP
        SELECT COALESCE(SUM(t.novo_preco - c.preco_pago), 0.00)
        INTO v_diff_patrimonio
        FROM compoe c
        JOIN tmp_precos_atualizados t ON t.id_atleta = c.id_atleta
        WHERE c.id_time = reg_esc.id_time AND c.numero_rodada = p_rodada;

        UPDATE time
        SET patrimonio = GREATEST(0.00, patrimonio + v_diff_patrimonio)
        WHERE id_time = reg_esc.id_time;
    END LOOP;

    -- 3. Marca a rodada como finalizada
    UPDATE rodada SET estado = 'Consolidada' WHERE numero = p_rodada;
END;
$$;

-- Erro encontrado: depois da carga, todas as pontuações das rodadas 1 a 34 estavam em 0.
UPDATE desempenho_na_rodada d
SET pontuacao = fn_pontuacao_atleta(d.id_atleta, d.numero_rodada)
FROM rodada r
WHERE r.numero = d.numero_rodada
  AND LOWER(r.estado) = 'consolidada';