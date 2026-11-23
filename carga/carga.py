# Carga dos json que a coleta.py salvou em carga/json/
# rodar de dentro da pasta carga:
#   python3 carga.py      -> carga base + scouts das rodadas 1 a 34
#   python3 carga.py 35   -> só os scouts da rodada 35, depois de fechar o mercado, separado para demonstracao do video
import json, sys, psycopg

def ler(nome):
    with open("json/" + nome + ".json") as f:
        return json.load(f)

mercado = ler("mercado")
# no mercado.json tem 15 atletas com preco_num menor que 1, mas o preço nunca fica abaixo de C$ 1,00, então esses entram com 1
precos = {str(a["atleta_id"]): max(a["preco_num"], 1) for a in mercado["atletas"]}

con = psycopg.connect("host=localhost dbname=lbd user=lbd password=lbd2026 options=-csearch_path=liga_facom")
cur = con.cursor()

def carregar_scouts(r):
    partidas = ler(f"partidas_{r}")["partidas"]
    for id_atleta, a in ler(f"pontuados_{r}")["atletas"].items():
        # somando as 35 rodadas, 120 atletas dos pontuados não estão no mercado.json e o pontuados não tem nome completo e sem situação
        cur.execute("INSERT INTO atleta (id_atleta, apelido, id_posicao) VALUES (%s, %s, %s) ON CONFLICT DO NOTHING",
                    (id_atleta, a["apelido"], a["posicao_id"]))
        cur.execute("INSERT INTO pertence VALUES (%s, %s, %s) ON CONFLICT DO NOTHING",
                    (id_atleta, r, a["clube_id"]))
        cur.execute("""INSERT INTO desempenho_na_rodada (id_atleta, numero_rodada, preco, entrou_em_campo)
                       VALUES (%s, %s, %s, %s)
                       ON CONFLICT (id_atleta, numero_rodada) DO UPDATE SET entrou_em_campo = EXCLUDED.entrou_em_campo""",
                    (id_atleta, r, precos.get(id_atleta, 1), a["entrou_em_campo"]))
        # o pontuados não tem partida_id, só clube_id, então a partida é a da rodada que o clube aparece como clube_casa_id ou clube_visitante_id
        id_partida = next(p["partida_id"] for p in partidas
                          if a["clube_id"] in (p["clube_casa_id"], p["clube_visitante_id"]))
        for sigla, qtd in (a["scout"] or {}).items():
            # o scout V só aparece nos técnicos (posicao_id 6), 241 vezes, e não está na tabela de scouts do enunciado, pontuação de técnico na liga sai do placar
            if sigla != "V":
                cur.execute("INSERT INTO registra_scout VALUES (%s, %s, %s, %s) ON CONFLICT DO NOTHING",
                            (id_atleta, id_partida, sigla, qtd))

if len(sys.argv) > 1:
    carregar_scouts(int(sys.argv[1]))
else:
    # no mercado o campo nome do clube vem igual à sigla (FLA) e o apelido é o apelido mesmo (Mengão, Timão,
    # e Fluminense e São Paulo são os dois "Tricolor"). Erro encontrado: antes usávamos o apelido e o mercado
    # mostrava "Mengão" no lugar de Flamengo. A API não tem o nome completo, então usamos o slug
    # (flamengo, sao-paulo) trocando o "-" por espaço: Flamengo, Sao Paulo
    for c in mercado["clubes"].values():
        cur.execute("INSERT INTO clube VALUES (%s, %s, %s, %s) ON CONFLICT DO NOTHING",
                    (c["id"], c["slug"].replace("-", " ").title(), c["abreviacao"], c["escudos"]["60x60"]))
    for p in mercado["posicoes"].values():
        cur.execute("INSERT INTO posicao VALUES (%s, %s, %s) ON CONFLICT DO NOTHING",
                    (p["id"], p["nome"], p["abreviacao"]))
    # as situações não tem 1 e 4
    for s in mercado["status"].values():
        cur.execute("INSERT INTO situacao VALUES (%s, %s) ON CONFLICT DO NOTHING", (s["id"], s["nome"]))
    for a in mercado["atletas"]:
        cur.execute("INSERT INTO atleta VALUES (%s, %s, %s, %s, %s) ON CONFLICT DO NOTHING",
                    (a["atleta_id"], a["nome"], a["apelido"], a["posicao_id"], a["status_id"]))

    # o esquemas.json traz a quantidade pela sigla da posição (gol, lat, zag...) e não pelo id, por isso busca o id_posicao pela abreviacao
    for e in ler("esquemas"):
        cur.execute("INSERT INTO esquema_tatico VALUES (%s, %s) ON CONFLICT DO NOTHING", (e["esquema_id"], e["nome"]))
        for abrev, qtd in e["posicoes"].items():
            cur.execute("""INSERT INTO exige SELECT %s, id_posicao, %s FROM posicao WHERE abreviacao = %s
                           ON CONFLICT DO NOTHING""", (e["esquema_id"], qtd, abrev))

    #a API está na rodada 36 com o mercado aberto, então 1 a 35 já foram jogadas
    for r in range(1, 39):
        cur.execute("INSERT INTO rodada VALUES (%s, %s) ON CONFLICT DO NOTHING",
                    (r, "Consolidada" if r <= 34 else "Futura"))
    # partida adiada continua na lista da rodada, só vem com valida false
    for r in range(1, 36):
        for p in ler(f"partidas_{r}")["partidas"]:
            cur.execute("INSERT INTO partida VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s) ON CONFLICT DO NOTHING",
                        (p["partida_id"], p["local"], p["partida_data"], p["placar_oficial_mandante"],
                         p["placar_oficial_visitante"], p["valida"], p["clube_casa_id"], p["clube_visitante_id"], r))

    # rodada 35: clube e preço de agora de cada atleta do mercado
    for a in mercado["atletas"]:
        cur.execute("INSERT INTO pertence VALUES (%s, 35, %s) ON CONFLICT DO NOTHING", (a["atleta_id"], a["clube_id"]))
        cur.execute("INSERT INTO desempenho_na_rodada (id_atleta, numero_rodada, preco) VALUES (%s, 35, %s) ON CONFLICT DO NOTHING",
                    (a["atleta_id"], precos[str(a["atleta_id"])]))

    for r in range(1, 35):
        carregar_scouts(r)

con.commit()
print("concluído")
