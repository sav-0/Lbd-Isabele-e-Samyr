Cada técnico tem exatamente um time, e o time tem nome e patrimônio próprios, por isso o time virou uma entidade separada, ligada ao técnico por um relacionamento 1:1 com linha dupla nos dois lados já que não existe técnico sem time, nem time sem técnico.

No futebol real, clube, atleta, posição e situação viraram entidades porque a fonte de dados identifica cada um por um número próprio, e o texto pede para guardar esses números. 
A posição se liga a outras coisas então também precisa ser entidade, os esquemas dizem quantos jogadores de cada posição são exigidos, e alguns scouts só valem para certas posições. O técnico real do clube não ganhou entidade própria, ele tem clube, preço, situação e é escalado como qualquer jogador, então foi tratado como um atleta com posição dee tecnico.

O atleta não foi ligado direto ao clube porque ele pode ser transferido no meio do campeonato, e a liga precisa saber em qual clube ele estava em cada rodada. Por isso o relacionamento PERTENCE junta atleta, rodada e clube: para cada atleta, em cada rodada, existe um único clube
A partida tem dois clubes com papéis diferentes, um mandante e um visitante. Por isso foram feitos dois relacionamentos, MANDANTE e VISITANTE, em vez de um só. Assim fica claro de qual clube é cada placar, pensei e colocar como atributo do clube, porém muda  a cada rodada então não faria sentido.

O preço do atleta não ficou dentro de ATLETA porque ele muda a cada rodada e o texto pede o histórico. O mesmo vale para a informação de se ele entrou em campo e para a pontuação, por isso as três ficaram no relacionamento DESEMPENHO_NA_RODADA, entre atleta e rodada. A pontuação aparece tracejada porque é calculada a partir dos scouts

O tipo de scout virou entidade porque tem dados próprios: sigla, descrição e valor em pontos. O scout em si não tem identidade própria, ele é só "quantas vezes tal atleta fez tal ação em tal partida". Por isso virou um relacionamento entre atleta, partida e tipo de scout, guardando só a quantidade

A quantidade de jogadores exigida num esquema depende do esquema e da posição juntos. No 4-3-3 são dois laterais, no 3-4-3 nenhum. Por isso essa quantidade ficou no relacionamento EXIGE, entre esquema e posição.

A escalação virou entidade fraca porque não existe sozinha: ela é sempre de um time numa rodada, como é identificada por eles juntos, o diagrama impede que um técnico tenha duas escalações na mesma rodada. Os atletas escolhidos entram pelo relacionamento COMPÕE, que guarda o preço pago e quem é o capitão. Esses dois dados ficam ali porque é sobre o atleta dentro daquela escalação específica. O preço pago precisa ser guardado porque o preço do atleta depois muda, e a diferença entre os dois altera o patrimônio

Na liga, o técnico tem duas relações diferentes: pode ser o dono e pode ser participante. Por isso foram feitos dois relacionamentos. A data de entrada ficou em PARTICIPA porque depende do técnico e da liga juntos.

O diagrama não tem atributos compostos nem multivalorados porque nenhum dado do texto tem partes internas ou vários valores para a mesma coisa.

as regras que dependem de contas, de valores específicos ou da ordem dos acontecimentos não aparecem no desenho e estão na lista de regras, garantidas por restrições do banco, gatilhos, funções e procedimentos como pedido