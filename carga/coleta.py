# baixa os dados da API do Cartola e salva em carga/json/
#rodar: python3 coleta.py
import json, os, time, requests
os.makedirs("json", exist_ok=True)

def baixar(endpoint, arquivo):
    dados = requests.get("https://api.cartola.globo.com" + endpoint, headers={"User-Agent": "Mozilla/5.0"}).json()
    with open("json/" + arquivo + ".json", "w") as f:
        json.dump(dados, f, ensure_ascii=False, indent=2)
    time.sleep(1) 
    return dados

status = baixar("/mercado/status", "status")
baixar("/atletas/mercado", "mercado")
baixar("/esquemas", "esquemas")

#tem que fazer loop pra conseguir todas as rodadas
for r in range(1, status["rodada_atual"]):
    baixar(f"/partidas/{r}", f"partidas_{r}")
    baixar(f"/atletas/pontuados/{r}", f"pontuados_{r}")
