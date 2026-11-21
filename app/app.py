# Aplicação de terminal da Liga FACOM Fantasy
# rodar da pasta raiz do repositório: python3 app/app.py
# As regras (orçamento, esquema, capitão, situação, estado da rodada) ficam no banco:
# aqui só mandamos o pedido e mostramos a mensagem de erro que o banco devolver.
import os, subprocess, sys, psycopg

con = psycopg.connect("host=localhost dbname=lbd user=lbd password=lbd2026 options=-csearch_path=liga_facom",
                      autocommit=True)
tecnico = None  # (id_tecnico, apelido, id_time)


def sql(comando, params=()):
    try:
        cur = con.execute(comando, params)
        return cur.fetchall() if cur.description else cur.rowcount
    except psycopg.Error as e:
        print("\n  Recusado pelo banco:", e.diag.message_primary or e)
        return None


def tabela(linhas, titulos):
    if not linhas:
        print("  (nada encontrado)")
        return
    larg = [max(len(str(x)) for x in col) for col in zip(titulos, *linhas)]
    for linha in [titulos] + linhas:
        print("  " + "  ".join(str(x).ljust(w) for x, w in zip(linha, larg)))


def ler(msg):
    texto = input("  " + msg + ": ").strip()
    return texto or None


def rodada_aberta():
    r = sql("SELECT numero FROM rodada WHERE estado = 'Aberta'")
    return r[0][0] if r else None


def cadastrar():
    if sql("CALL sp_cadastrar_tecnico(%s, %s, %s, %s)",
           (ler("Nome"), ler("E-mail"), ler("Apelido"), ler("Nome do time"))) is not None:
        print("  Técnico cadastrado com C$ 100,00.")


def escolher():
    global tecnico
    tabela(sql("""SELECT t.id_tecnico, t.apelido, tm.nome, tm.patrimonio
                  FROM tecnico t JOIN time tm USING (id_tecnico) ORDER BY 1"""),
           ["id", "apelido", "time", "patrimônio"])
    r = sql("""SELECT t.id_tecnico, t.apelido, tm.id_time FROM tecnico t JOIN time tm USING (id_tecnico)
               WHERE t.id_tecnico = %s""", (int(ler("id do técnico")),))
    if r:
        tecnico = r[0]


def criar_liga():
    publica = (ler("Pública? (s/n)") or "s").lower() == "s"
    if sql("""INSERT INTO liga (nome, descricao, codigo_convite, limite_participantes, publica, id_dono)
              VALUES (%s, %s, %s, %s, %s, %s)""",
           (ler("Nome da liga"), ler("Descrição (opcional)"), ler("Código de convite"),
            int(ler("Limite de participantes")), publica, tecnico[0])) is not None:
        print("  Liga criada, você já participa dela.")


def listar_ligas():
    tabela(sql("""SELECT l.id_liga, l.nome, CASE WHEN l.publica THEN 'pública' ELSE 'privada' END,
                         count(p.id_tecnico) || '/' || l.limite_participantes
                  FROM liga l LEFT JOIN participa p USING (id_liga) GROUP BY l.id_liga ORDER BY 1"""),
           ["id", "liga", "tipo", "participantes"])


def entrar_liga():
    listar_ligas()
    if sql("CALL sp_entrar_liga(%s, %s, %s)",
           (tecnico[0], int(ler("id da liga")), ler("Código de convite (enter se for pública)"))) is not None:
        print("  Você entrou na liga.")


def mercado():
    print("  Filtros (enter para não filtrar)")
    pos, clube, preco = ler("Posição (gol, lat, zag, mei, ata, tec)"), ler("Clube"), ler("Preço máximo")
    tabela(sql("""SELECT id_atleta, apelido, clube, pos_abrev, situacao, preco_atual, media, ultima_pontuacao
                  FROM vw_mercado
                  WHERE (%(pos)s::text IS NULL OR pos_abrev = %(pos)s)
                    AND (%(clube)s::text IS NULL OR clube ILIKE '%%' || %(clube)s || '%%')
                    AND (%(preco)s::numeric IS NULL OR preco_atual <= %(preco)s::numeric)
                  ORDER BY pos_abrev, preco_atual DESC""",
               {"pos": pos, "clube": clube, "preco": preco}),
           ["id", "atleta", "clube", "pos", "situação", "preço", "média", "última"])


def escalacao():
    rodada = rodada_aberta()
    if rodada is None:
        print("  Nenhuma rodada aberta no momento.")
        return
    while True:
        esc = sql("""SELECT e.estado, et.nome FROM escalacao e JOIN esquema_tatico et USING (id_esquema)
                     WHERE e.id_time = %s AND e.numero_rodada = %s""", (tecnico[2], rodada))
        print(f"\n  --- Escalação da rodada {rodada}:",
              f"{esc[0][1]} ({esc[0][0]})" if esc else "ainda não criada (escolha o esquema)")
        tabela(sql("""SELECT a.id_atleta, a.apelido, p.abreviacao, c.preco_pago,
                             CASE WHEN c.capitao THEN 'capitão' ELSE '' END
                      FROM compoe c JOIN atleta a USING (id_atleta) JOIN posicao p USING (id_posicao)
                      WHERE c.id_time = %s AND c.numero_rodada = %s ORDER BY a.id_posicao""",
                   (tecnico[2], rodada)), ["id", "atleta", "pos", "preço pago", ""])
        total = sql("SELECT COALESCE(SUM(preco_pago), 0) FROM compoe WHERE id_time = %s AND numero_rodada = %s",
                    (tecnico[2], rodada))
        patrimonio = sql("SELECT patrimonio FROM time WHERE id_time = %s", (tecnico[2],))
        print(f"  Total: C$ {total[0][0]}  |  Patrimônio: C$ {patrimonio[0][0]}")
        op = ler("1 esquema | 2 incluir atleta | 3 remover atleta | 4 capitão | 5 confirmar | 0 voltar")
        if op == "1":
            tabela(sql("SELECT id_esquema, nome FROM esquema_tatico ORDER BY 1"), ["id", "esquema"])
            sql("""INSERT INTO escalacao (id_time, numero_rodada, id_esquema) VALUES (%s, %s, %s)
                   ON CONFLICT (id_time, numero_rodada) DO UPDATE SET id_esquema = EXCLUDED.id_esquema""",
                (tecnico[2], rodada, int(ler("id do esquema"))))
        elif op == "2":
            # o preço pago é preenchido pelo gatilho do banco com o preço do atleta na rodada
            sql("INSERT INTO compoe (id_time, numero_rodada, id_atleta) VALUES (%s, %s, %s)",
                (tecnico[2], rodada, int(ler("id do atleta"))))
        elif op == "3":
            sql("DELETE FROM compoe WHERE id_time = %s AND numero_rodada = %s AND id_atleta = %s",
                (tecnico[2], rodada, int(ler("id do atleta"))))
        elif op == "4":
            sql("UPDATE compoe SET capitao = (id_atleta = %s) WHERE id_time = %s AND numero_rodada = %s",
                (int(ler("id do capitão")), tecnico[2], rodada))
        elif op == "5":
            if sql("CALL sp_confirmar_escalacao(%s, %s)", (tecnico[2], rodada)) is not None:
                print("  Escalação confirmada!")
        elif op == "0":
            return


def ranking():
    listar_ligas()
    liga, rodada = int(ler("id da liga")), ler("Rodada (enter para o acumulado)")
    if rodada:
        tabela(sql("""SELECT posicao_ranking, tecnico, nome_time, pontuacao_rodada
                      FROM fn_ranking_rodada(%s, %s) ORDER BY 1""", (liga, int(rodada))),
               ["pos", "técnico", "time", "pontos"])
    else:
        tabela(sql("""SELECT posicao_ranking, tecnico, nome_time, pontuacao_acumulada
                      FROM vw_ranking WHERE id_liga = %s ORDER BY 1""", (liga,)),
               ["pos", "técnico", "time", "pontos"])


def admin():
    while True:
        print("\n  --- Administrador")
        tabela(sql("SELECT numero, estado FROM rodada WHERE estado <> 'Consolidada' ORDER BY numero LIMIT 4"),
               ["rodada", "estado"])
        op = ler("1 abrir rodada | 2 fechar mercado | 3 carregar estatísticas | 4 consolidar | 0 voltar")
        if op == "1":
            sql("UPDATE rodada SET estado = 'Aberta' WHERE numero = %s", (int(ler("Rodada")),))
        elif op == "2":
            sql("UPDATE rodada SET estado = 'Fechada' WHERE estado = 'Aberta'")
        elif op == "3":
            # os scouts da rodada vêm dos json salvos, pelo mesmo programa de carga
            pasta_carga = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "carga")
            subprocess.run([sys.executable, "carga.py", ler("Rodada")], cwd=pasta_carga)
        elif op == "4":
            if sql("CALL sp_consolidar_rodada(%s)", (int(ler("Rodada")),)) is not None:
                print("  Rodada consolidada.")
        elif op == "0":
            return


opcoes = {"1": cadastrar, "2": escolher, "3": criar_liga, "4": entrar_liga,
          "5": mercado, "6": escalacao, "7": ranking, "8": admin}
precisa_tecnico = {"3", "4", "6"}

while True:
    print("\n=== Liga FACOM Fantasy ===")
    print("  Técnico atual:", f"{tecnico[1]}" if tecnico else "nenhum (use a opção 2)")
    print("  1 Cadastrar técnico   2 Escolher técnico   3 Criar liga   4 Entrar em liga")
    print("  5 Mercado             6 Escalação          7 Ranking      8 Administrador   0 Sair")
    op = ler("Opção")
    if op == "0":
        break
    if op in precisa_tecnico and not tecnico:
        print("  Escolha um técnico primeiro (opção 2).")
    elif op in opcoes:
        try:
            opcoes[op]()
        except (ValueError, TypeError):
            print("  Valor inválido.")
