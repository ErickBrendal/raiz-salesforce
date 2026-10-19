#!/bin/bash
# RAIZ 4.0 — Onda 8 (Engineering Status). Requer a Onda 7. Uso: cd ~/Downloads/raiz-onda8 && bash implantar-onda8.sh
set -u
ORG=radar
TESTES="RaizEngineeringTest RaizGovernancaActionTest RaizJourneyServiceTest RaizGovernancaServiceTest RaizKnowledgeServiceTest RaizCockpitServiceTest RaizMitigationServiceTest RaizSimulationServiceTest RaizRiskEngineTest"
# Deploys anteriores do projeto (Ids das saidas das ondas). So os implantados de fato viram registro.
DEPLOYS="0AfgK00000WouiwSAB 0AfgK00000Wp7xtSAB 0AfgK00000Wp8CPSAZ 0AfgK00000WpEkrSAF 0AfgK00000WpOVhSAN 0AfgK00000WpOYvSAN 0AfgK00000WpPunSAF 0AfgK00000Wpr9VSAR 0AfgK00000Wpu5lSAB 0AfgK00000WpuFRSAZ 0AfgK00000Wtb9NSAR 0AfgK00000WtbXZSAZ 0AfgK00000Wtiu1SAB 0AfgK00000WtWEZSA3"
ONDAS="0AfgK00000Wp8CPSAZ=Onda 1|0AfgK00000WpuFRSAZ=Onda 5|0AfgK00000WtbXZSAZ=Onda 6|0AfgK00000WtWEZSA3=Onda 7"
cd "$(dirname "$0")"; mkdir -p saida/deploys
passo() { echo; echo "==== $1"; }
falhou() { echo; echo "XXXX PAROU em: $1 — veja saida/$2"; exit 1; }
resumo() { grep -aE "Status: (Succeeded|Failed|Canceled)|Passing|Failing|Deploy ID: " "$1" | sort -u | head -10; sed -n "/Component Failures/,/└/p;/Test Failures/,/└/p" "$1" | head -60; }
TL=""; CN=""; for t in $TESTES; do TL="$TL --tests $t"; CN="$CN --class-names $t"; done
SO_EV=0; [ "${1:-}" = "--evidencias" ] && SO_EV=1
if [ $SO_EV -eq 0 ]; then
passo "0/7 A Onda 7 esta na org?"
sf data query --target-org $ORG --query "SELECT Name FROM ApexClass WHERE Name = 'RaizGovernancaAction'" > saida/00-pre.txt 2>&1
grep -q RaizGovernancaAction saida/00-pre.txt || { echo "XXXX Rode antes a Onda 7."; exit 1; }
echo "ok"
passo "1/7 Validacao (dry-run)"
sf project deploy start --dry-run --source-dir force-app --target-org $ORG --test-level RunSpecifiedTests $TL --wait 40 > saida/01-validacao.txt 2>&1
R=$?; resumo saida/01-validacao.txt; [ $R -eq 0 ] || falhou "validacao" 01-validacao.txt
passo "2/7 Deploy"
sf project deploy start --source-dir force-app --target-org $ORG --test-level RunSpecifiedTests $TL --wait 40 > saida/02-deploy.txt 2>&1
R=$?; resumo saida/02-deploy.txt; [ $R -eq 0 ] || falhou "deploy" 02-deploy.txt
ESTE=$(grep -aoE "Deploy ID: 0Af[A-Za-z0-9]{15}" saida/02-deploy.txt | tail -1 | awk '{print $3}')
sf org assign permset --name EBL_RAIZ_Cockpit --target-org $ORG > /dev/null 2>&1
sf org assign permset --name RAIZ_Engenharia --target-org $ORG > saida/02b-permset.txt 2>&1; echo "permission set RAIZ_Engenharia: $(grep -aoE "RAIZ_Engenharia|Duplicate|already" saida/02b-permset.txt | head -1)"
passo "3/7 Inventario de engenharia (upsert por API_Name__c; rodar de novo nao duplica)"
sf data upsert bulk --sobject RAIZ_Engineering_Status__c --file inventario/01-funcionalidades.csv --external-id API_Name__c --line-ending LF --target-org $ORG --wait 10 > saida/03a-func.txt 2>&1; grep -aE "Processed|Failed|Error|records" saida/03a-func.txt | head -5
sf data upsert bulk --sobject RAIZ_Engineering_Status__c --file inventario/02-componentes.csv --external-id API_Name__c --line-ending LF --target-org $ORG --wait 10 > saida/03b-comp.txt 2>&1; grep -aE "Processed|Failed|Error|records" saida/03b-comp.txt | head -5
passo "4/7 Implantacoes reais (sf project deploy report)"
for d in $DEPLOYS $ESTE; do sf project deploy report --job-id $d --target-org $ORG --json > saida/deploys/dep-$d.json 2>/dev/null; done
ARGS=(); IFS='|' read -ra PARES <<< "$ONDAS"; for p in "${PARES[@]}"; do ARGS+=("$p"); done; [ -n "$ESTE" ] && ARGS+=("$ESTE=Onda 8")
python3 scripts/py/implantacoes.py saida/deploys saida/implantacoes.csv "${ARGS[@]}"
sf data upsert bulk --sobject RAIZ_Implantacao__c --file saida/implantacoes.csv --external-id Deploy_Id__c --line-ending LF --target-org $ORG --wait 10 > saida/04-implantacoes.txt 2>&1; grep -aE "Processed|Failed|Error|records" saida/04-implantacoes.txt | head -5
fi
if [ $SO_EV -eq 0 ]; then
passo "5/7 Testes (antes da verificação, para o verificador ler o resultado) com cobertura"
sf apex run test $CN --code-coverage --result-format human --target-org $ORG --wait 20 > saida/07-testes.txt 2>&1
grep -aE "Outcome|Pass Rate|Tests Ran|Fail|RaizEngineeringVerifier |RaizEngineeringService |RaizGovernancaService " saida/07-testes.txt | head -20 | tee saida/07-resumo.txt
fi
passo "6/7 Evidencias do sf CLI (LWC e cobertura)"
sf data query --target-org $ORG --result-format csv --query "SELECT API_Name__c, Tipo_Componente__c FROM RAIZ_Engineering_Status__c WHERE Nivel__c = 'Componente'" > saida/inv.csv 2>/dev/null
sf data query --use-tooling-api --target-org $ORG --result-format csv --query "SELECT DeveloperName FROM LightningComponentBundle WHERE NamespacePrefix = null" > saida/lwc.csv 2>/dev/null
sf data query --use-tooling-api --target-org $ORG --result-format csv --query "SELECT ApexClassOrTrigger.Name, NumLinesCovered, NumLinesUncovered FROM ApexCodeCoverageAggregate" > saida/cobertura.csv 2>/dev/null
python3 scripts/py/evidencias.py saida/inv.csv saida/lwc.csv saida/cobertura.csv saida/evidencias.csv
sf data upsert bulk --sobject RAIZ_Evidencia__c --file saida/evidencias.csv --external-id Chave__c --line-ending LF --target-org $ORG --wait 10 > saida/05-evidencias.txt 2>&1; grep -aE "Processed|Failed|Error|records" saida/05-evidencias.txt | head -5
passo "7/7 Verificador + ajuste do cartao do documento bloqueado"
sf apex run --file scripts/apex/verificar-onda8.apex --target-org $ORG > saida/06-verificar-bruto.txt 2>&1
grep -aE "\|ERROR\|RAIZ |EXCEPTION|Error" saida/06-verificar-bruto.txt | sed 's/.*DEBUG|//' | tee saida/06-verificar.txt
echo; echo "OK — abra: sf org open --path lightning/n/RAIZ_Engineering_Intelligence --target-org $ORG"
echo "Para atualizar as evidencias depois: rode de novo os passos 6 e 7 (bash implantar-onda8.sh --evidencias)."
