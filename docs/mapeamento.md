# Mapeamento Relacional – Liga FACOM Fantasy

* **tecnico** (<u>id_tecnico</u>, nome, email, apelido, data_cadastro)
  * *Origem:* Entidade forte `TÉCNICO`. O atributo `email` possui restrição `UNIQUE`.
* **time** (<u>id_time</u>, nome, patrimonio, id_tecnico -> tecnico)
  * *Origem:* Entidade forte `TIME`. Recebeu a chave estrangeira do relacionamento 1:1 `POSSUI` (com restrição `UNIQUE` em `id_tecnico`).
* **liga** (<u>id_liga</u>, nome, descricao, codigo_convite, limite_participantes, publica, id_dono -> tecnico)
  * *Origem:* Entidade forte `LIGA`. Recebeu a chave estrangeira do relacionamento 1:N `É_DONO`. O atributo `codigo_convite` possui restrição `UNIQUE`.
* **participa** (<u>id_tecnico</u> -> tecnico, <u>id_liga</u> -> liga, data_entrada)
  * *Origem:* Tabela associativa gerada pelo relacionamento N:M `PARTICIPA`.
* **clube** (<u>id_clube</u>, nome, abreviacao, url_escudo)
  * *Origem:* Entidade forte `CLUBE`.
* **posicao** (<u>id_posicao</u>, nome, abreviacao)
  * *Origem:* Entidade forte `POSIÇÃO`.
* **situacao** (<u>id_situacao</u>, descricao)
  * *Origem:* Entidade forte `SITUAÇÃO`.
* **atleta** (<u>id_atleta</u>, nome_completo, apelido, id_posicao -> posicao, id_situacao -> situacao)
  * *Origem:* Entidade forte `ATLETA`. Recebeu as chaves estrangeiras dos relacionamentos 1:N `JOGA_NA` e `ESTÁ_EM`.
* **rodada** (<u>numero</u>, estado)
  * *Origem:* Entidade forte `RODADA`.
* **desempenho_na_rodada** (<u>id_atleta</u> -> atleta, <u>numero_rodada</u> -> rodada, preco, entrou_em_campo, pontuacao)
  * *Origem:* Tabela associativa gerada pelo relacionamento N:M `DESEMPENHO_NA_RODADA` com atributos.
* **esquema_tatico** (<u>id_esquema</u>, nome)
  * *Origem:* Entidade forte `ESQUEMA_TATICO`.
* **exige** (<u>id_esquema</u> -> esquema_tatico, <u>id_posicao</u> -> posicao, quantidade)
  * *Origem:* Tabela associativa gerada pelo relacionamento N:M `EXIGE`.
* **partida** (<u>id_partida</u>, local, data_hora, placar_mandante, placar_visitante, valida, id_clube_mandante -> clube, id_clube_visitante -> clube, numero_rodada -> rodada)
  * *Origem:* Entidade forte `PARTIDA`. Recebeu as chaves estrangeiras dos relacionamentos 1:N `MANDANTE`, `VISITANTE` e `CONTÉM`.
* **pertence** (<u>id_atleta</u> -> atleta, <u>numero_rodada</u> -> rodada, id_clube -> clube)
  * *Origem:* Tabela associativa gerada pelo relacionamento ternário N:M:P `PERTENCE`.
* **tipo_scout** (<u>sigla</u>, descricao, valor_pontos)
  * *Origem:* Entidade forte `TIPO_SCOUT`.
* **vale_para** (<u>sigla_scout</u> -> tipo_scout, <u>id_posicao</u> -> posicao)
  * *Origem:* Tabela associativa gerada pelo relacionamento N:M `VALE_PARA`.
* **registra_scout** (<u>id_atleta</u> -> atleta, <u>id_partida</u> -> partida, <u>sigla_scout</u> -> tipo_scout, quantidade)
  * *Origem:* Tabela associativa gerada pelo relacionamento ternário N:M:P `REGISTRA_SCOUT`.
* **escalacao** (<u>id_time</u> -> time, <u>numero_rodada</u> -> rodada, estado, data_confirmacao, id_esquema -> esquema_tatico)
  * *Origem:* Entidade fraca `ESCALAÇÃO` identificada por `TIME` (`MONTA`) e `RODADA` (`REFERE_SE`), recebendo a chave estrangeira do relacionamento 1:N `USA`.
* **compoe** (<u>id_time</u> -> time, <u>numero_rodada</u> -> rodada, <u>id_atleta</u> -> atleta, preco_pago, capitao)
  * *Origem:* Tabela associativa gerada pelo relacionamento N:M `COMPÕE` entre a entidade fraca `ESCALAÇÃO` e `ATLETA`.

---

## Justificativas das Decisões

1. **Uso dos números da API como Chave Primária:** Optamos por utilizar os identificadores numéricos originais fornecidos pela API do Cartola (`id_clube`, `id_atleta`, `id_posicao`, `id_situacao`, `id_partida`) diretamente como chaves primárias (PK) em vez de criar chaves artificiais (`SERIAL`). Isso evita duplicidade de registros quando o programa de carga é executado mais de uma vez e simplifica as junções (`JOIN`) sem depender de tabelas auxiliares de mapeamento.
2. **Armazenamento de Valores Derivados:** Decidimos armazenar fisicamente o atributo derivado `pontuacao` na tabela `desempenho_na_rodada`. Embora pudesse ser recalculado a cada consulta multiplicando os scouts em `registra_scout` pelos pesos de `tipo_scout`, persistir o valor otimiza o desempenho das consultas de ranking e histórico, ficando a cargo dos gatilhos (`triggers`) do banco manter esse valor sempre sincronizado.