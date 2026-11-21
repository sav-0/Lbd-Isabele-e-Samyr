# Liga FACOM Fantasy

Trabalho prático de Laboratório de Banco de Dados (LBD 2026/2 - FACOM/UFMS).

## Integrantes

| Nome | RGA |
|---|---|
| Isabele Maria Firmino | 202519070584 |
| Samyr Arruda Vilanova | 202219040078 |


## O que tem em cada pasta

```
docs/    diagrama ER (der.png), mapeamento relacional, lista de regras e explicação das decisões
sql/     scripts do banco (01-ddl.sql, 02-dados.sql, 03-programacao.sql, 04-consultas.sql, 05-seguranca-indices.sql)
carga/   coleta.py (baixa os dados da API do Cartola), carga.py (insere no banco) e json/ com os arquivos baixados
app/     aplicação de terminal
```

## Como subir o banco

Usamos o PostgreSQL no Docker, o mesmo container da disciplina (`postgresql-simples.yaml`):

```bash
docker compose -f postgresql-simples.yaml up -d
```

Banco `lbd`, usuário `lbd`, senha `lbd2026`, porta `5432`.

## Instalar as dependências do Python

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Ordem de execução

Rodar da pasta raiz do repositório, em um banco vazio:

```bash
docker exec -i lbd-postgres psql -U lbd -d lbd < sql/01-ddl.sql
docker exec -i lbd-postgres psql -U lbd -d lbd < sql/02-dados.sql
cd carga && python3 carga.py && cd ..
docker exec -i lbd-postgres psql -U lbd -d lbd < sql/03-programacao.sql
docker exec -i lbd-postgres psql -U lbd -d lbd < sql/04-consultas.sql
docker exec -i lbd-postgres psql -U lbd -d lbd < sql/05-seguranca-indices.sql
```

## Carga de dados

Os dados da API já estão salvos em `carga/json/`, não precisa baixar de novo.
Se quiser baixar de novo: `cd carga && python3 coleta.py`.

- `python3 carga.py` carrega clubes, posições, situações, atletas, esquemas, as 38 rodadas, as partidas e os scouts das rodadas 1 a 34.
- `python3 carga.py 35` carrega só os scouts da rodada 35. Ela é a rodada jogada no vídeo, então esse comando roda depois de fechar o mercado.

A carga pode rodar duas vezes seguidas sem duplicar dados.
