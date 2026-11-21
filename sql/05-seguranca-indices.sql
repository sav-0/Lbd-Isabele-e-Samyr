SET search_path TO liga_facom;

-- Índices para acelerar as consultas 
CREATE INDEX IF NOT EXISTS idx_desempenho_rodada ON desempenho_na_rodada (numero_rodada);
CREATE INDEX IF NOT EXISTS idx_partida_rodada ON partida (numero_rodada);
CREATE INDEX IF NOT EXISTS idx_registra_scout_atleta ON registra_scout (id_atleta, id_partida);
CREATE INDEX IF NOT EXISTS idx_compoe_atleta ON compoe (id_atleta);
CREATE INDEX IF NOT EXISTS idx_participa_liga ON participa (id_liga);

-- Papéis de acesso: Técnico e Administrador
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'perfil_tecnico') THEN
        CREATE ROLE perfil_tecnico;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'perfil_admin') THEN
        CREATE ROLE perfil_admin;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA liga_facom TO perfil_tecnico, perfil_admin;

-- Permissões do Técnico
GRANT SELECT ON ALL TABLES IN SCHEMA liga_facom TO perfil_tecnico;
GRANT INSERT, UPDATE ON tecnico, time, liga, participa, escalacao TO perfil_tecnico;
GRANT INSERT, UPDATE, DELETE ON compoe TO perfil_tecnico;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA liga_facom TO perfil_tecnico;
GRANT EXECUTE ON FUNCTION fn_pontuacao_atleta(INT, INT), fn_pontuacao_escalacao(INT, INT), fn_ranking_rodada(INT, INT) TO perfil_tecnico;
GRANT EXECUTE ON PROCEDURE sp_cadastrar_tecnico(VARCHAR, VARCHAR, VARCHAR, VARCHAR), sp_confirmar_escalacao(INT, INT), sp_entrar_liga(INT, INT, VARCHAR) TO perfil_tecnico;

-- Permissões do Administrador
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA liga_facom TO perfil_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA liga_facom TO perfil_admin;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA liga_facom TO perfil_admin;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA liga_facom TO perfil_admin;